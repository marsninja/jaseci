"""Build the jaclang single binary for linux-x86_64 (v1).

Pipeline (each step is a function so CI and local runs share one code path):

  1. fetch      -- download + verify the pinned python-build-standalone *full*
                   archive (or reuse one via --pbs-archive), extract it.
  2. site       -- pip install jaclang (+ llvmlite) into site/ using the pbs
                   interpreter, then strip pip/setuptools.
  3. precompile -- generate site/jaclang/_precompiled/cpython-312/*.jir under the
                   *bundled* CPython so the JIR keys match the shipped interpreter.
  4. prune      -- drop test/idlelib/tkinter/ensurepip/lib2to3 + build config from
                   the stdlib; hash-pin all .pyc (unchecked-hash) for fast, mtime-
                   independent startup.
  5. pack       -- tar (GNU) the rt layout (python/ + site/) | zstd -19 -> payload.
  6. link       -- compile launcher.c against pbs headers and statically link it
                   with libpython3.12.a + every built-in extension + libzstd.a.
  7. concat     -- stub + payload + trailer(magic|len|sha256) -> the binary.
  8. smoke      -- run the binary under a clean env (no system Python) and assert.

The static link line is driven entirely from pbs's PYTHON.json manifest (the
collect_link_inputs / *_command functions below) rather than hand-guessed flags;
that manifest->argv translation is the one genuinely per-platform-specific part.

Scope: jaclang only. Per validation, the "full CLI" needs no vendored
pygls/lark/interegular/pluggy -- the parser/LSP/plugin system are native Jac and
the sole third-party runtime dep is llvmlite (lazy, native codegen only).

Declarations live here; implementations are in impl/build.impl.jac.

Local validation example:
    jac run tools/binary/build.jac \\
        --pbs-archive /tmp/pbs.tar.zst \\
        --jaclang-path ./jac \\
        --output /tmp/jac-dev-linux-x86_64
"""

import sys;
import from pathlib { Path }

glob HERE: Path = Path(str(__file__)).resolve().parent,
     LAUNCHER_C: Path = HERE / "launcher.c",
     # Pinned python-build-standalone release (3.12, linux-x86_64, full archive).
     # We use a *pgo* (not pgo+lto) full archive on purpose: pgo+lto ships LLVM
     # bitcode objects (object_file_format == "llvm-bitcode") that only a matching
     # clang/lld can consume, whereas pgo ships native ELF objects linkable with the
     # stock manylinux2014 gcc. This is the last release that publishes pgo-full.
     PBS_TAG: str = "20241206",
     PBS_ASSET: str = "cpython-3.12.8+20241206-x86_64-unknown-linux-gnu-pgo-full.tar.zst",
     STDLIB_PRUNE: list[str] = [
         "test",
         "idlelib",
         "tkinter",
         "turtledemo",
         "ensurepip",
         "lib2to3",
         "lib-dynload"
     ];


# ------------------------------- pbs PYTHON.json -> static link line ----------
"""Load and parse the pbs PYTHON.json manifest."""
def load_manifest(pbs_python_dir: Path) -> dict;

"""Resolve a PYTHON.json-relative path (paths are relative to ``python/``)."""
def abs_path(pbs_python_dir: Path, rel: str) -> str;

"""Parse the generated inittab (config.c) for the built-in module set.

Only extensions whose PyInit_* is in this table are compiled into the
interpreter; the rest are loaded as shared libraries (e.g. _tkinter needs
system tcl/tk). We must link exactly the built-in set: linking a shared
extension would drag in unshippable system deps, while omitting a built-in one
leaves config.o with an undefined PyInit_* symbol.
"""
def builtin_module_names(pbs_python_dir: Path, manifest: any) -> (set | None);

"""Return the structured pieces of the link line, all driven by PYTHON.json.

Keys: include_dir, objects, static_libs, system_libs, cflags.
"""
def collect_link_inputs(pbs_python_dir: Path) -> dict;

"""Build the full ``cc`` argv that links the launcher into a static binary.

``extra_libraries`` (e.g. a static libzstd.a the launcher needs for payload
extraction) are placed inside the archive group so their symbols resolve against
the launcher object regardless of ordering.
"""
def build_link_command(
    pbs_python_dir: Path,
    launcher_obj: str,
    output: str,
    cc: str = "cc",
    extra_objects: (list | None) = None,
    extra_libraries: (list | None) = None,
    extra_ldflags: (list | None) = None
) -> list;

"""Build the ``cc -c`` argv that compiles launcher.c against the pbs headers."""
def compile_launcher_command(
    pbs_python_dir: Path,
    launcher_c: str,
    obj_out: str,
    cc: str = "cc",
    zstd_include: (str | None) = None
) -> list;


# ------------------------------- build pipeline ------------------------------
"""Emit a build progress line."""
def log(msg: str);

"""Echo and run a subprocess; raise on non-zero exit."""
def run(argv: list, env: (dict | None) = None);

"""Return the bundled-interpreter path inside an extracted pbs tree."""
def pbs_python(pbs_dir: Path) -> Path;

"""Return the extracted ``python/`` dir from a pbs full archive."""
def fetch_pbs(workdir: Path, archive: (Path | None)) -> Path;

"""pip install jaclang (+ deps) into ``site`` using the bundled interpreter."""
def populate_site(pbs_dir: Path, site: Path, jaclang_spec: str);

"""Run precompile_bytecode.jac under the bundled CPython against site/jaclang."""
def generate_precompiled(pbs_dir: Path, site: Path);

"""Assemble the rt-layout (python/ + site/) and hash-pin all .pyc."""
def stage_runtime(pbs_dir: Path, site: Path, stage: Path);

"""tar (GNU) the stage dir | zstd -19 -> out_zst. Return (len, sha256hex)."""
def pack_payload(stage: Path, out_zst: Path) -> tuple;

"""Locate a static libzstd.a (pbs-shipped first, then common system paths)."""
def find_static_zstd(pbs_dir: Path) -> (str | None);

"""Compile launcher.c and statically link it into stub_out."""
def link_stub(pbs_dir: Path, stub_out: Path);

"""[stub][payload][trailer] -> out, +x. Trailer = magic|len(u64 LE)|hash(64)."""
def concat_binary(stub: Path, payload: Path, payload_len: int, digest: str, out: Path);

"""Run the binary once with a clean env; raise SystemExit on failure."""
def jac_invoke(binary: Path, env: dict, args: list, timeout: int = 120) -> str;

"""Run the binary with a clean env (no system Python) and assert behavior."""
def smoke_test(binary: Path);

"""Parse args and run the full build pipeline."""
def main -> int;


with entry:__main__ {
    sys.exit(main());
}
