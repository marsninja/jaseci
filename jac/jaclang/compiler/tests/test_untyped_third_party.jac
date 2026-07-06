"""Type-checker tests for installed-but-untyped third-party imports.

Regression coverage for issue #7161: attributes reached through an
installed third-party package that ships no type information (no PEP 561
``py.typed`` marker, no ``.pyi`` stub) used to infer as ``Unknown`` and the
strict-Unknown discipline then hard-errored on every downstream attribute
access (E1030/E1032) and assignment (E1002). That strictness is meant to
surface *internal* inference gaps the author can fix, but it fired
identically on *external* code the user cannot annotate.

The fix degrades symbols resolved from an external untyped module to a
permissive foreign ``Any`` (usable, no cascade), while keeping strict
``Unknown`` for the user's own project source. A single ``untyped-external``
diagnostic (W1102 by default) still marks the boundary.
"""

import os;
import sys;
import shutil;
import tempfile;
import importlib;
import from jaclang.jac0core.program { JacProgram }


"""Write a package dir under ``base_dir`` and return the containing dir."""
def _write_pkg(base_dir: str, name: str, body: str) -> str {
    pkg_dir = os.path.join(base_dir, name);
    os.makedirs(pkg_dir, exist_ok=True);
    with open(os.path.join(pkg_dir, "__init__.py"), "w") as f {
        f.write(body);
    }
    return base_dir;
}


"""Type-check ``src`` with ``search_dir`` visible on ``sys.path``."""
def _check(src: str, search_dir: str) -> JacProgram {
    sys.path.insert(0, search_dir);
    importlib.invalidate_caches();
    try {
        prog = JacProgram();
        prog.compile(file_path="untyped_tp_src.jac", use_str=src, type_check=True);
        return prog;
    } finally {
        sys.path.remove(search_dir);
        importlib.invalidate_caches();
    }
}


# A requests-shaped untyped client: no annotations anywhere.
glob _UNTYPED_BODY: str = (
         "def get(url):\n"
         "    return Response()\n"
         "\n"
         "class Response:\n"
         "    def __init__(self):\n"
         "        self.status_code = 200\n"
         "        self.headers = {}\n"
         "    def json(self):\n"
         "        return {}\n"
     );

# Attribute chain off a plain `import`: attribute reads plus a call whose
# result flows into an annotated return -- every step cascades pre-fix.
glob _IMPORT_SRC: str = (
         "import untyped_client;\n"
         "\n"
         "def fetch -> dict[str, str] {\n"
         "    resp = untyped_client.get(\"http://example.com\");\n"
         "    print(resp.status_code);\n"
         "    print(resp.headers);\n"
         "    return resp.json();\n"
         "}\n"
     );

# Same access through a `from ... import` of a name defined in the package.
glob _FROM_IMPORT_SRC: str = (
         "import from untyped_client { get }\n"
         "\n"
         "def fetch -> dict[str, str] {\n"
         "    resp = get(\"http://example.com\");\n"
         "    print(resp.headers);\n"
         "    return resp.json();\n"
         "}\n"
     );


test "installed untyped third-party attrs do not cascade errors" {
    base_dir = tempfile.mkdtemp(prefix="jac_tp_");
    try {
        # Emulate an installed dependency: it lives under ``site-packages``.
        sp = os.path.join(base_dir, "site-packages");
        _write_pkg(sp, "untyped_client", _UNTYPED_BODY);

        prog = _check(_IMPORT_SRC, sp);
        errors = [str(e) for e in prog.errors_had];
        assert errors == [] , errors;
    } finally {
        shutil.rmtree(base_dir, ignore_errors=True);
    }
}


test "from-import of an untyped third-party name degrades to foreign any" {
    base_dir = tempfile.mkdtemp(prefix="jac_tp_");
    try {
        sp = os.path.join(base_dir, "site-packages");
        _write_pkg(sp, "untyped_client", _UNTYPED_BODY);

        prog = _check(_FROM_IMPORT_SRC, sp);
        errors = [str(e) for e in prog.errors_had];
        assert errors == [] , errors;

        # The import boundary is surfaced once, as an informational warning.
        warns = [str(w) for w in prog.warnings_had];
        assert any("untyped_client" in w for w in warns) , warns;
    } finally {
        shutil.rmtree(base_dir, ignore_errors=True);
    }
}


test "project-local untyped module still enforces strict Unknown" {
    base_dir = tempfile.mkdtemp(prefix="jac_tp_");
    try {
        # No ``site-packages`` segment: this is treated as the user's own
        # source, so the strict-Unknown discipline must remain in force.
        _write_pkg(base_dir, "untyped_client", _UNTYPED_BODY);

        prog = _check(_IMPORT_SRC, base_dir);
        errors = [str(e) for e in prog.errors_had];
        assert errors != [] , "internal untyped source should still cascade";
    } finally {
        shutil.rmtree(base_dir, ignore_errors=True);
    }
}
