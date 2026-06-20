/*
 * jaclang single-binary launcher (linux-x86_64, v1).
 *
 * This executable statically embeds libpython3.12 (CPython C API + built-in
 * extension modules) and carries a zstd-compressed runtime payload appended
 * after the ELF image.  On first run it materializes that payload (the pruned
 * pure-Python stdlib + the jaclang `site/`) into a versioned cache directory,
 * then initializes CPython *in-process* and runs the jaclang boot dance.  No
 * system Python, uv, or pip is required at install or runtime.
 *
 * File shape:   [ ELF stub ][ runtime.tar.zst payload ][ trailer ]
 * Trailer:      magic(8) | payload_len(u64 LE) | payload_sha256_hex(64)
 *               (fixed JAC_TRAILER_LEN bytes at EOF; written by build.jac)
 *
 * The boot dance and PyConfig below reproduce exactly the isolated, no-site
 * (`python -S` + manual finder install) startup that was validated against the
 * stock jaclang: zero third-party top-level imports, llvmlite stays lazy.
 *
 * Scope: jaclang only (no jaseci plugins).  The only embedded third-party
 * runtime dependency is llvmlite, which is lazy (native codegen only) and is
 * shipped under site/.  No vendored pygls/lark/interegular/pluggy are needed:
 * the parser, language server, and plugin system are all native Jac now.
 */

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <wchar.h>

#include <zstd.h>

#include <Python.h>

/* ------------------------------------------------------------------ trailer */

#define JAC_MAGIC "JACBIN01"
#define JAC_MAGIC_LEN 8
#define JAC_HASH_LEN 64 /* sha256 hex */
#define JAC_TRAILER_LEN (JAC_MAGIC_LEN + 8 + JAC_HASH_LEN)

static void die(const char *msg) {
    fprintf(stderr, "jac (launcher): %s", msg);
    if (errno) fprintf(stderr, ": %s", strerror(errno));
    fputc('\n', stderr);
    exit(70); /* EX_SOFTWARE */
}

/* Resolve the absolute path of this executable via /proc/self/exe. */
static void resolve_self(char *out, size_t cap) {
    ssize_t n = readlink("/proc/self/exe", out, cap - 1);
    if (n < 0) die("cannot resolve /proc/self/exe");
    out[n] = '\0';
}

/* ------------------------------------------------------------ cache root */

/* mkdir -p for a full directory path. Returns 0 on success. */
static int mkpath_dir(const char *dir) {
    char tmp[PATH_MAX];
    snprintf(tmp, sizeof tmp, "%s", dir);
    for (char *p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            if (mkdir(tmp, 0755) != 0 && errno != EEXIST) return -1;
            *p = '/';
        }
    }
    if (mkdir(tmp, 0755) != 0 && errno != EEXIST) return -1;
    return 0;
}

static int dir_writable(const char *path) {
    struct stat st;
    if (stat(path, &st) == 0) return access(path, W_OK) == 0;
    /* Not present yet: writable iff we can create it (parents included). */
    if (mkpath_dir(path) == 0) return access(path, W_OK) == 0;
    return errno == EEXIST ? access(path, W_OK) == 0 : 0;
}

/* Mirror jaclang's cache resolution: $XDG_CACHE_HOME -> $HOME/.cache, then
 * /jac.  Falls back to a temp dir when the preferred root is not writable
 * (read-only / offline $HOME), matching the launcher's hermeticity contract. */
static void cache_root(char *out, size_t cap) {
    const char *xdg = getenv("XDG_CACHE_HOME");
    const char *home = getenv("HOME");
    char base[PATH_MAX];

    if (xdg && xdg[0]) {
        snprintf(base, sizeof base, "%s", xdg);
    } else if (home && home[0]) {
        snprintf(base, sizeof base, "%s/.cache", home);
    } else {
        base[0] = '\0';
    }

    if (base[0]) {
        snprintf(out, cap, "%s/jac", base);
        if (dir_writable(out)) return; /* creates parents as needed */
    }

    /* Fallback: temp dir keyed by uid so concurrent users do not collide. */
    const char *tmp = getenv("TMPDIR");
    if (!tmp || !tmp[0]) tmp = "/tmp";
    snprintf(out, cap, "%s/jac-cache-%u", tmp, (unsigned)getuid());
    if (!dir_writable(out)) die("no writable cache directory (HOME and TMPDIR both unwritable)");
}

/* ----------------------------------------------------------- fs helpers */

/* mkdir -p for the directory part of `path` (path itself is a file). */
static int mkpath_parent(const char *path) {
    char tmp[PATH_MAX];
    snprintf(tmp, sizeof tmp, "%s", path);
    char *slash = strrchr(tmp, '/');
    if (!slash) return 0;
    *slash = '\0';
    for (char *p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            if (mkdir(tmp, 0755) != 0 && errno != EEXIST) return -1;
            *p = '/';
        }
    }
    if (mkdir(tmp, 0755) != 0 && errno != EEXIST) return -1;
    return 0;
}

/* Recursively remove a directory tree (best effort, used for GC + tmp cleanup). */
static void rm_rf(const char *path) {
    char cmd[PATH_MAX + 16];
    /* Internal-only path (our own cache subdirs); no untrusted input. */
    snprintf(cmd, sizeof cmd, "rm -rf '%s'", path);
    int rc = system(cmd);
    (void)rc;
}

/* ------------------------------------------------------------ tar (ustar/GNU) */

/* Octal field parse (tar numeric fields are NUL/space terminated octal). */
static uint64_t tar_octal(const char *p, int len) {
    uint64_t v = 0;
    int i = 0;
    while (i < len && (p[i] == ' ' || p[i] == '\0')) i++;
    for (; i < len && p[i] >= '0' && p[i] <= '7'; i++) v = (v << 3) | (uint64_t)(p[i] - '0');
    return v;
}

/* Extract a (already decompressed) GNU/ustar tar image into destdir.
 * Handles regular files, directories, symlinks, and GNU long-name ('L') and
 * long-link ('K') extension records.  build.jac writes tarfile.GNU_FORMAT. */
static void untar_mem(const unsigned char *data, size_t size, const char *destdir) {
    size_t off = 0;
    char longname[PATH_MAX];
    longname[0] = '\0';
    char longlink[PATH_MAX];
    longlink[0] = '\0';

    while (off + 512 <= size) {
        const unsigned char *h = data + off;
        off += 512;

        /* Two consecutive zero blocks mark end of archive. */
        int allzero = 1;
        for (int i = 0; i < 512; i++)
            if (h[i]) { allzero = 0; break; }
        if (allzero) continue;

        char name[PATH_MAX];
        if (longname[0]) {
            snprintf(name, sizeof name, "%s", longname);
            longname[0] = '\0';
        } else {
            /* ustar: optional prefix (345) + name (100). */
            char nm[101], pfx[156];
            memcpy(nm, h, 100);
            nm[100] = '\0';
            memcpy(pfx, h + 345, 155);
            pfx[155] = '\0';
            if (pfx[0])
                snprintf(name, sizeof name, "%s/%s", pfx, nm);
            else
                snprintf(name, sizeof name, "%s", nm);
        }

        uint64_t fsize = tar_octal((const char *)h + 124, 12);
        uint64_t mode = tar_octal((const char *)h + 100, 8);
        char typeflag = (char)h[156];
        size_t data_blocks = (size_t)((fsize + 511) / 512) * 512;

        if (typeflag == 'L') { /* GNU long name */
            size_t n = fsize < sizeof longname ? (size_t)fsize : sizeof longname - 1;
            memcpy(longname, data + off, n);
            longname[n] = '\0';
            off += data_blocks;
            continue;
        }
        if (typeflag == 'K') { /* GNU long link target */
            size_t n = fsize < sizeof longlink ? (size_t)fsize : sizeof longlink - 1;
            memcpy(longlink, data + off, n);
            longlink[n] = '\0';
            off += data_blocks;
            continue;
        }
        if (typeflag == 'x' || typeflag == 'g') { /* pax headers: skip */
            off += data_blocks;
            continue;
        }

        char full[PATH_MAX];
        snprintf(full, sizeof full, "%s/%s", destdir, name);

        if (typeflag == '5') { /* directory */
            mkpath_parent(full);
            mkdir(full, 0755);
            continue;
        }
        if (typeflag == '2') { /* symlink */
            char target[PATH_MAX];
            if (longlink[0]) {
                snprintf(target, sizeof target, "%s", longlink);
                longlink[0] = '\0';
            } else {
                char ln[101];
                memcpy(ln, h + 157, 100);
                ln[100] = '\0';
                snprintf(target, sizeof target, "%s", ln);
            }
            mkpath_parent(full);
            unlink(full);
            if (symlink(target, full) != 0 && errno != EEXIST) die("symlink failed");
            off += data_blocks;
            continue;
        }

        /* Regular file ('0' or '\0'). */
        if (mkpath_parent(full) != 0) die("mkdir failed during extract");
        int fd = open(full, O_WRONLY | O_CREAT | O_TRUNC, (mode_t)(mode & 0777));
        if (fd < 0) die("open for write failed during extract");
        size_t remaining = (size_t)fsize;
        const unsigned char *src = data + off;
        while (remaining) {
            ssize_t w = write(fd, src, remaining);
            if (w <= 0) die("write failed during extract");
            src += w;
            remaining -= (size_t)w;
        }
        close(fd);
        off += data_blocks;
    }
}

/* ------------------------------------------------------- payload + extract */

/* Read the trailer, returning payload length and hash (caller-provided buf). */
static void read_trailer(int fd, off_t total, uint64_t *payload_len, char hash[JAC_HASH_LEN + 1]) {
    if (total < JAC_TRAILER_LEN) die("binary too small to contain a payload trailer");
    unsigned char t[JAC_TRAILER_LEN];
    if (pread(fd, t, JAC_TRAILER_LEN, total - JAC_TRAILER_LEN) != JAC_TRAILER_LEN)
        die("cannot read payload trailer");
    if (memcmp(t, JAC_MAGIC, JAC_MAGIC_LEN) != 0)
        die("payload trailer magic mismatch (binary not built with build.jac?)");
    uint64_t len = 0;
    for (int i = 0; i < 8; i++) len |= (uint64_t)t[JAC_MAGIC_LEN + i] << (8 * i);
    *payload_len = len;
    memcpy(hash, t + JAC_MAGIC_LEN + 8, JAC_HASH_LEN);
    hash[JAC_HASH_LEN] = '\0';
}

/* Materialize the runtime payload into <cache>/rt/<hash16>; return that path. */
static void materialize_runtime(const char *self, char *rt_out, size_t rt_cap) {
    int fd = open(self, O_RDONLY);
    if (fd < 0) die("cannot open self for reading payload");
    off_t total = lseek(fd, 0, SEEK_END);

    uint64_t payload_len;
    char hash[JAC_HASH_LEN + 1];
    read_trailer(fd, total, &payload_len, hash);

    char hash16[17];
    memcpy(hash16, hash, 16);
    hash16[16] = '\0';

    char root[PATH_MAX];
    cache_root(root, sizeof root);
    char rtbase[PATH_MAX];
    snprintf(rtbase, sizeof rtbase, "%s/rt", root);
    mkdir(rtbase, 0755);
    snprintf(rt_out, rt_cap, "%s/%s", rtbase, hash16);

    /* Already materialized?  A `.ok` marker guards against partial extracts. */
    char okmark[PATH_MAX];
    snprintf(okmark, sizeof okmark, "%s/.ok", rt_out);
    if (access(okmark, F_OK) == 0) {
        close(fd);
        return;
    }

    /* Read the compressed payload (offset = total - trailer - payload_len). */
    off_t poff = total - JAC_TRAILER_LEN - (off_t)payload_len;
    if (poff < 0) die("payload offset underflow");
    unsigned char *zbuf = malloc(payload_len);
    if (!zbuf) die("oom reading payload");
    if (pread(fd, zbuf, payload_len, poff) != (ssize_t)payload_len) die("short payload read");
    close(fd);

    /* Decompress (zstd). */
    unsigned long long dsize = ZSTD_getFrameContentSize(zbuf, payload_len);
    if (dsize == ZSTD_CONTENTSIZE_ERROR || dsize == ZSTD_CONTENTSIZE_UNKNOWN)
        die("payload is not a valid zstd frame");
    unsigned char *tarbuf = malloc((size_t)dsize);
    if (!tarbuf) die("oom decompressing payload");
    size_t got = ZSTD_decompress(tarbuf, (size_t)dsize, zbuf, payload_len);
    if (ZSTD_isError(got)) die("zstd decompress failed");
    free(zbuf);

    /* Extract into a per-pid temp dir, then atomically rename into place. */
    char tmpdir[PATH_MAX];
    snprintf(tmpdir, sizeof tmpdir, "%s.tmp.%d", rt_out, (int)getpid());
    rm_rf(tmpdir);
    if (mkdir(tmpdir, 0755) != 0 && errno != EEXIST) die("cannot create temp extract dir");
    untar_mem(tarbuf, (size_t)got, tmpdir);
    free(tarbuf);

    /* Stamp the success marker inside the temp dir before the rename. */
    char tmpok[PATH_MAX];
    snprintf(tmpok, sizeof tmpok, "%s/.ok", tmpdir);
    int okfd = open(tmpok, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (okfd >= 0) close(okfd);

    if (rename(tmpdir, rt_out) != 0) {
        /* Lost a race with a concurrent first run, or target exists: that's
         * fine as long as the winner left a complete tree. */
        rm_rf(tmpdir);
        if (access(okmark, F_OK) != 0) die("runtime materialization failed (rename)");
    }

    /* GC stale rt/<old-hash> dirs from previous binary versions (best effort). */
    char gc[PATH_MAX];
    snprintf(gc, sizeof gc,
             "find '%s' -mindepth 1 -maxdepth 1 -type d ! -name '%s' "
             "! -name '*.tmp.*' -exec rm -rf {} + 2>/dev/null",
             rtbase, hash16);
    int rc = system(gc);
    (void)rc;
}

/* ------------------------------------------------------------ CPython boot */

static void set_path(PyConfig *cfg, PyWideStringList *list, const char *utf8) {
    wchar_t *w = Py_DecodeLocale(utf8, NULL);
    if (!w) die("Py_DecodeLocale failed");
    PyStatus st = PyWideStringList_Append(list, w);
    PyMem_RawFree(w);
    if (PyStatus_Exception(st)) die("PyWideStringList_Append failed");
    (void)cfg;
}

static void set_str(PyStatus (*fn)(PyConfig *, wchar_t **, const wchar_t *),
                    PyConfig *cfg, wchar_t **target, const char *utf8) {
    wchar_t *w = Py_DecodeLocale(utf8, NULL);
    if (!w) die("Py_DecodeLocale failed");
    PyStatus st = fn(cfg, target, w);
    PyMem_RawFree(w);
    if (PyStatus_Exception(st)) die("PyConfig_SetString failed");
}

int main(int argc, char **argv) {
    char self[PATH_MAX];
    resolve_self(self, sizeof self);

    char rt[PATH_MAX];
    materialize_runtime(self, rt, sizeof rt);

    /* Pre-initialize in UTF-8 mode (PEP 540) so stdio/filesystem encoding is
     * UTF-8 regardless of the ambient locale. Isolated config ignores PYTHON*
     * env, so this must be set on the PreConfig, not via PYTHONUTF8. */
    PyPreConfig preconfig;
    PyPreConfig_InitIsolatedConfig(&preconfig);
    preconfig.utf8_mode = 1;
    PyStatus pst = Py_PreInitialize(&preconfig);
    if (PyStatus_Exception(pst)) die("Py_PreInitialize failed");

    char home[PATH_MAX], stdlib[PATH_MAX], site[PATH_MAX];
    snprintf(home, sizeof home, "%s/python", rt);
    snprintf(stdlib, sizeof stdlib, "%s/python/lib/python3.12", rt);
    snprintf(site, sizeof site, "%s/site", rt);

    PyConfig config;
    PyConfig_InitIsolatedConfig(&config); /* ignore PYTHON* env, isolated */
    config.site_import = 0;               /* no site.py / .pth (validated) */
    config.parse_argv = 0;                /* we own argv parsing (none) */
    config.write_bytecode = 0;            /* shipped stdlib is .pyc; don't litter */
    config.module_search_paths_set = 1;

    set_str(PyConfig_SetString, &config, &config.home, home);
    set_str(PyConfig_SetString, &config, &config.program_name, "jac");
    set_path(&config, &config.module_search_paths, stdlib);
    set_path(&config, &config.module_search_paths, site);

    /* argv[0] -> "jac"; pass the rest through to start_cli via sys.argv. */
    PyStatus st = PyConfig_SetBytesArgv(&config, argc, argv);
    if (PyStatus_Exception(st)) die("PyConfig_SetBytesArgv failed");

    st = Py_InitializeFromConfig(&config);
    PyConfig_Clear(&config);
    if (PyStatus_Exception(st)) die("Py_InitializeFromConfig failed");

    /* The validated boot dance: install the lazy .jac finder (no .pth needed),
     * then hand off to the jaclang CLI, which reads sys.argv. */
    int rc = PyRun_SimpleString(
        "import _jac_finder; _jac_finder.install()\n"
        "from jaclang.jac0core.cli_boot import start_cli\n"
        "start_cli()\n");

    if (Py_FinalizeEx() < 0) rc = -1;
    return rc == 0 ? 0 : 1;
}
