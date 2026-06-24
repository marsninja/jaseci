"""Bundled native `os.path` (posixpath) cross-backend equivalence fixture
(issues #6404 / #6940).

The SAME `import from os.path { ... }` binds CPython's `posixpath` on the sv
(Python) backend and the bundled `na_stdlib/os/path.na.jac` Mechanism-B module
on the na (native LLVM) backend — the first module to ride the bundled native
stdlib resolution keystone. This fixture pins the two implementations congruent
on the pure-string POSIX path helpers, including the `normpath`/`splitext`
edge cases. ES/JS opts out.
"""

import from os.path { normpath, dirname, basename, splitext, isabs }

def ospath_py() -> dict {
    (stem, ext) = splitext("/a/archive.tar.gz");
    return {
        "np_rel": normpath("a/b/../c"),
        "np_abs": normpath("/a//b/./c/"),
        "np_dot": normpath("."),
        "np_empty": normpath(""),
        "np_updir": normpath("../../a"),
        "np_double": normpath("//a/b"),
        "np_triple": normpath("///a"),
        "np_collapse": normpath("a/./b/../../c"),
        "dirname": dirname("/usr/local/bin"),
        "basename": basename("/usr/local/bin"),
        "dirname_bare": dirname("file.txt"),
        "splitext_root": stem,
        "splitext_ext": ext,
        "isabs_yes": 1 if isabs("/x") else 0,
        "isabs_no": 1 if isabs("rel/x") else 0,
    };
}

cl def ospath_cl() -> dict {
    return {};
}

na {
    def ospath_na() -> dict[str, any] {
        (stem, ext) = splitext("/a/archive.tar.gz");
        return {
            "np_rel": normpath("a/b/../c"),
            "np_abs": normpath("/a//b/./c/"),
            "np_dot": normpath("."),
            "np_empty": normpath(""),
            "np_updir": normpath("../../a"),
            "np_double": normpath("//a/b"),
            "np_triple": normpath("///a"),
            "np_collapse": normpath("a/./b/../../c"),
            "dirname": dirname("/usr/local/bin"),
            "basename": basename("/usr/local/bin"),
            "dirname_bare": dirname("file.txt"),
            "splitext_root": stem,
            "splitext_ext": ext,
            "isabs_yes": 1 if isabs("/x") else 0,
            "isabs_no": 1 if isabs("rel/x") else 0,
        };
    }
}
