"""Type checker tests for client `cl` npm imports (issue #7152).

Regression coverage for jac-shadcn's generated `lib/utils.cl.jac`:

    cl import from "clsx" { clsx }
    cl import from "tailwind-merge" { twMerge }

    def:pub cn(*inputs: any) -> str {
        return twMerge(clsx(inputs));
    }

The checker used to not resolve string-form npm imports from the project's
installed `.jac/client/node_modules`, so `clsx`/`twMerge` typed as Unknown
(W1100 "Module not found"). That Unknown then escalated into a hard
E1002 ("Cannot return <Unknown>, expected str") in the return statement --
so `jac check` failed on code jac itself generates.

The fix resolves installed npm packages to an external (untyped) module and
lets values imported from such foreign-source modules flow gradually, the
way an untyped JS import flows in TypeScript.
"""

import os;
import from pathlib { Path }
import from tempfile { TemporaryDirectory }
import jaclang;
import from jaclang.compiler.passes.main.type_checker_pass { TypeCheckPass }
import from jaclang.jac0core.program { JacProgram }
import from jaclang.jac0core.modresolver { resolve_client_npm_package }

"""Materialize a minimal client project with two installed npm packages.

Returns the path to `lib/utils.cl.jac`, the verbatim jac-shadcn helper.
"""
def _make_npm_client_project(proj_dir: Path) -> Path {
    node_modules = proj_dir / ".jac" / "client" / "node_modules";

    clsx_dist = node_modules / "clsx" / "dist";
    clsx_dist.mkdir(parents=True, exist_ok=True);
    (node_modules / "clsx" / "package.json").write_text(
        '{"name":"clsx","version":"2.1.1",'
        '"module":"dist/clsx.mjs","main":"dist/clsx.js"}'
    );
    (clsx_dist / "clsx.mjs").write_text("export function clsx() {}\n");
    (clsx_dist / "clsx.js").write_text("module.exports.clsx = function () {};\n");

    tw_dist = node_modules / "tailwind-merge" / "dist";
    tw_dist.mkdir(parents=True, exist_ok=True);
    (node_modules / "tailwind-merge" / "package.json").write_text(
        '{"name":"tailwind-merge","version":"2.5.0",'
        '"module":"dist/bundle-mjs.mjs","main":"dist/bundle-cjs.js"}'
    );
    (tw_dist / "bundle-mjs.mjs").write_text("export function twMerge() {}\n");
    (tw_dist / "bundle-cjs.js").write_text(
        "module.exports.twMerge = function () {};\n"
    );

    (proj_dir / "jac.toml").write_text(
        '[project]\nname = "npmfixture"\nversion = "0.1.0"\n'
        'entry-point = "lib/utils.cl.jac"\n\n'
        '[dependencies.npm]\nclsx = "^2.1.1"\ntailwind-merge = "^2.5.0"\n'
    );

    lib = proj_dir / "lib";
    lib.mkdir(parents=True, exist_ok=True);
    util = lib / "utils.cl.jac";
    util.write_text(
        'cl import from "clsx" { clsx }\n'
        'cl import from "tailwind-merge" { twMerge }\n\n'
        'def:pub cn(*inputs: any) -> str {\n'
        '    return twMerge(clsx(inputs));\n'
        '}\n'
    );
    return util;
}

test "generated cn() type-checks against installed npm packages" {
    with TemporaryDirectory() as td {
        util = _make_npm_client_project(Path(td));
        program = JacProgram();
        mod = program.compile(str(util));
        TypeCheckPass(ir_in=mod, prog=program);
        err_codes = [
            e.code.code
            for e in program.errors_had
            if e.code is not None
        ];
        warn_codes = [
            w.code.code
            for w in program.warnings_had
            if w.code is not None
        ];
        pretty = "\n".join([e.pretty_print() for e in program.errors_had]);
        # The core regression: the wrapped npm call no longer escalates an
        # unresolved import into a hard "Cannot return <Unknown>" error.
        assert "E1002" not in err_codes , "Generated cn() must not raise E1002; "
        f"npm-imported values must flow to the str return. Got:\n{pretty}";
        assert len(program.errors_had) == 0 , f"Expected no errors, got: {pretty}";
        # Layer 1: the npm packages resolve, so there is no "Module not found".
        assert "W1100" not in warn_codes , "Installed npm packages must resolve "
        f"from .jac/client/node_modules, but got W1100. codes={warn_codes}";
    }
}

test "resolve_client_npm_package resolves installed packages by entry point" {
    with TemporaryDirectory() as td {
        util = _make_npm_client_project(Path(td));
        base = str(util);
        clsx_entry = resolve_client_npm_package("clsx", base);
        assert clsx_entry is not None , "clsx must resolve";
        assert clsx_entry.endswith("clsx.mjs") , "must prefer the ESM 'module' entry, "
        f"got {clsx_entry}";
        tw_entry = resolve_client_npm_package("tailwind-merge", base);
        assert tw_entry is not None and tw_entry.endswith("bundle-mjs.mjs") , "tailwind-merge must resolve to its module entry, "
        f"got {tw_entry}";
        # A package that is not installed stays unresolved (falls back to the
        # existing "module not found" path rather than a false positive).
        assert resolve_client_npm_package("not-installed", base) is None , "uninstalled packages must not resolve";
        # Relative specifiers are never treated as npm packages.
        assert resolve_client_npm_package("./local", base) is None , "relative imports must not resolve as npm";
    }
}
