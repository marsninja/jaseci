"""sv<->na equivalence: os + os.path.

`import os` binds CPython on sv and the native intrinsics (libc) on na. getcwd /
getenv / realpath are process-stable (both run in one process) and compare by
value; the mutating ops (mkdir/makedirs/rmdir) use a backend-distinct temp tree
and report only a success flag; os.path string ops compare exactly.

Syscall predicates (exists/isdir/isfile) are bound to an `int` before use: na
returns them as a distinct bool that is no longer `== 1`, so the coercion is what
keeps the two backends comparable (matching the prim_os idiom).
"""
import os;

def _diff(label: str, want: str, got: str) -> int {
    wl = want.split("\n");
    gl = got.split("\n");
    n = len(wl) if len(wl) > len(gl) else len(gl);
    bad = 0;
    for i in range(n) {
        w = wl[i] if i < len(wl) else "<none>";
        g = gl[i] if i < len(gl) else "<none>";
        if w != g {
            print(f"  [FAIL] {label}: sv={repr(w)} na={repr(g)}");
            bad += 1;
        }
    }
    status = "OK" if bad == 0 else "MISMATCH";
    print(f"{label}: {n - bad}/{n} lines match -- {status}");
    return bad;
}

def _dec(x: any) -> str {
    if isinstance(x, bytes) { return x.decode("utf-8", "surrogatepass"); }
    return x as str;
}

sv {
    def os_sv() -> str {
        made_ok: int = 0;
        d: str = "/tmp/jac_eq_sv_dir";
        ex0: int = os.path.exists(d);
        if ex0 == 0 { os.mkdir(d); }
        isd: int = os.path.isdir(d);
        if isd == 1 {
            os.rmdir(d);
            ex1: int = os.path.exists(d);
            if ex1 == 0 { made_ok = 1; }
        }
        mk_ok: int = 0;
        deep: str = "/tmp/jac_eq_sv_mk/a/b/c";
        exd: int = os.path.exists(deep);
        if exd == 0 { os.makedirs(deep); }
        isdd: int = os.path.isdir(deep);
        if isdd == 1 {
            mk_ok = 1;
            os.rmdir("/tmp/jac_eq_sv_mk/a/b/c");
            os.rmdir("/tmp/jac_eq_sv_mk/a/b");
            os.rmdir("/tmp/jac_eq_sv_mk/a");
            os.rmdir("/tmp/jac_eq_sv_mk");
        }
        et: int = os.path.exists("/tmp");
        dt: int = os.path.isdir("/tmp");
        ft: int = os.path.isfile("/tmp");
        em: int = os.path.exists("/no/such/xyz123");
        pid: int = 1 if os.getpid() > 0 else 0;
        p: list[str] = [];
        p.append("cwd=" + os.getcwd());
        p.append("path_env=" + (os.getenv("PATH") as str));
        p.append("pid_pos=" + str(pid));
        p.append("mkdir_rmdir_ok=" + str(made_ok));
        p.append("makedirs_ok=" + str(mk_ok));
        p.append("realpath_root=" + os.path.realpath("/"));
        p.append("join2=" + os.path.join("a", "b"));
        p.append("join_trail=" + os.path.join("a/", "b"));
        p.append("join_abs=" + os.path.join("a", "/b"));
        p.append("join3=" + os.path.join("x", "y", "z"));
        p.append("basename=" + os.path.basename("/usr/local/bin"));
        p.append("dirname=" + os.path.dirname("/usr/local/bin"));
        p.append("basename_bare=" + os.path.basename("file.txt"));
        p.append("dirname_bare=" + os.path.dirname("file.txt"));
        p.append("exists_tmp=" + str(1 if et else 0));
        p.append("isdir_tmp=" + str(1 if dt else 0));
        p.append("isfile_tmp=" + str(1 if ft else 0));
        p.append("exists_missing=" + str(1 if em else 0));
        return "\n".join(p);
    }
}

na {
    def os_na() -> str {
        made_ok: int = 0;
        d: str = "/tmp/jac_eq_na_dir";
        ex0: int = os.path.exists(d);
        if ex0 == 0 { os.mkdir(d); }
        isd: int = os.path.isdir(d);
        if isd == 1 {
            os.rmdir(d);
            ex1: int = os.path.exists(d);
            if ex1 == 0 { made_ok = 1; }
        }
        mk_ok: int = 0;
        deep: str = "/tmp/jac_eq_na_mk/a/b/c";
        exd: int = os.path.exists(deep);
        if exd == 0 { os.makedirs(deep); }
        isdd: int = os.path.isdir(deep);
        if isdd == 1 {
            mk_ok = 1;
            os.rmdir("/tmp/jac_eq_na_mk/a/b/c");
            os.rmdir("/tmp/jac_eq_na_mk/a/b");
            os.rmdir("/tmp/jac_eq_na_mk/a");
            os.rmdir("/tmp/jac_eq_na_mk");
        }
        et: int = os.path.exists("/tmp");
        dt: int = os.path.isdir("/tmp");
        ft: int = os.path.isfile("/tmp");
        em: int = os.path.exists("/no/such/xyz123");
        pid: int = 1 if os.getpid() > 0 else 0;
        p: list[str] = [];
        p.append("cwd=" + os.getcwd());
        p.append("path_env=" + (os.getenv("PATH") as str));
        p.append("pid_pos=" + str(pid));
        p.append("mkdir_rmdir_ok=" + str(made_ok));
        p.append("makedirs_ok=" + str(mk_ok));
        p.append("realpath_root=" + os.path.realpath("/"));
        p.append("join2=" + os.path.join("a", "b"));
        p.append("join_trail=" + os.path.join("a/", "b"));
        p.append("join_abs=" + os.path.join("a", "/b"));
        p.append("join3=" + os.path.join("x", "y", "z"));
        p.append("basename=" + os.path.basename("/usr/local/bin"));
        p.append("dirname=" + os.path.dirname("/usr/local/bin"));
        p.append("basename_bare=" + os.path.basename("file.txt"));
        p.append("dirname_bare=" + os.path.dirname("file.txt"));
        p.append("exists_tmp=" + str(1 if et else 0));
        p.append("isdir_tmp=" + str(1 if dt else 0));
        p.append("isfile_tmp=" + str(1 if ft else 0));
        p.append("exists_missing=" + str(1 if em else 0));
        return "\n".join(p);
    }
}

with entry {
    bad = _diff("os", os_sv(), _dec(os_na()));
    assert bad == 0, f"os: {bad} mismatch(es)";
}
