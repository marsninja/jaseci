"""Tests for ink_compile (bundle_patch.jac and compile.jac)."""

import json;
import os;
import tempfile;
import from pathlib { Path }

import from jac_super.ink_compile.bundle_patch {
    _extract_brace_block,
    consolidate_bundle_imports,
    fix_broken_nullish_or,
    hoist_jac_runtime
}

import from jac_super.ink_compile.compile {
    _FETCH_TRANSPORT_HELPER,
    _apply_ai_tui_module_patches,
    _finalize_esm_exports,
    _inject_runtime_imports,
    _remove_register_client_module,
    _replace_python_os_import,
    _strip_inlined_jac_runtime,
    _strip_shimmed_react_imports,
    compile_ink_app
}


def _make_temp_module(content: str) -> Path {
    (fd, path) = tempfile.mkstemp(suffix=".mjs", text=True);
    os.close(fd);
    Path(path).write_text(content, encoding="utf-8");
    return Path(path);
}


# ---------------------------------------------------------------------------
# _extract_brace_block
# ---------------------------------------------------------------------------
test "_extract_brace_block simple block" {
    code = "{ return 42; }";
    (body, end) = _extract_brace_block(code, 1);
    assert "return 42;" in body;
    assert "{" not in body;
    assert "}" not in body;
    assert end == len(code);
}

test "_extract_brace_block nested braces" {
    code = "{ { a: 1 } { b: 2 } }";
    (body, end) = _extract_brace_block(code, 1);
    assert "{ a: 1 }" in body;
    assert "{ b: 2 }" in body;
    assert end == len(code);
}

test "_extract_brace_block empty block" {
    code = "{}";
    (body, end) = _extract_brace_block(code, 1);
    assert body == "";
    assert end == 2;
}

test "_extract_brace_block string with braces" {
    code = '{ foo("{hello}") } extra';
    (body, end) = _extract_brace_block(code, 1);
    assert "{hello}" in body;
    assert "extra" not in body;
    assert end > len(body);
}

test "_extract_brace_block string with escaped quote" {
    code = '{ foo("he\\"llo") } extra';
    (body, end) = _extract_brace_block(code, 1);
    assert '\\"llo' in body;
}

test "_extract_brace_block single quoted string with braces" {
    code = "{ foo('{hello}') } extra";
    (body, end) = _extract_brace_block(code, 1);
    assert "'{hello}'" in body;
}

test "_extract_brace_block line comment skipped" {
    code = "{ // this is a { comment\n  return 42;\n} extra";
    (body, end) = _extract_brace_block(code, 1);
    assert "return 42;" in body;
    assert "extra" not in body;
}

test "_extract_brace_block line comment at end of file" {
    code = "{ // comment with no newline";
    (body, end) = _extract_brace_block(code, 1);
    assert "comment" in body;
}

test "_extract_brace_block block comment skipped" {
    code = "{ /* { nested brace } */ return 42; } extra";
    (body, end) = _extract_brace_block(code, 1);
    assert "return 42;" in body;
}

test "_extract_brace_block block comment unterminated" {
    code = "{ /* unterminated comment";
    (body, end) = _extract_brace_block(code, 1);
    assert "/*" in body;
}

test "_extract_brace_block template literal skipped" {
    code = "{ foo(`hello {world}`) } extra";
    (body, end) = _extract_brace_block(code, 1);
    assert "`hello {world}`" in body;
    assert "extra" not in body;
}

test "_extract_brace_block template literal with backslash" {
    code = "{ foo(`he\\`llo`) } extra";
    (body, end) = _extract_brace_block(code, 1);
    assert "`he\\`llo`" in body;
}

test "_extract_brace_block template literal at start" {
    code = "{`{nested}`}";
    (body, end) = _extract_brace_block(code, 1);
    assert "`{nested}`" in body;
    assert end == len(code);
}

test "_extract_brace_block template literal with dollar brace" {
    code = "{ `hello ${x + (y * z)} world` }";
    (body, end) = _extract_brace_block(code, 1);
    assert "`" in body;
}

test "_extract_brace_block js object literal" {
    code = '{\n  key: "value",\n  nested: { a: 1 }\n}';
    (body, end) = _extract_brace_block(code, 1);
    assert "key:" in body;
    assert "nested:" in body;
    assert end == len(code);
}

test "_extract_brace_block js condition block" {
    code = "{\n  if ((x instanceof Error)) {}\n} extra";
    (body, end) = _extract_brace_block(code, 1);
    assert "instanceof Error" in body;
    assert "extra" not in body;
}


# ---------------------------------------------------------------------------
# fix_broken_nullish_or
# ---------------------------------------------------------------------------
test "fix_broken_nullish_or basic" {
    code = 'let x = foo ?? "" || "";';
    result = fix_broken_nullish_or(code);
    assert '|| ""' not in result;
}

test "fix_broken_nullish_or with bracket access" {
    code = 'let x = data[key] ?? "" || "";';
    result = fix_broken_nullish_or(code);
    assert '|| ""' not in result;
    assert "data[key]" in result;
}

test "fix_broken_nullish_or quoted bracket not matched" {
    code = 'let x = data["key"] ?? "" || "";';
    result = fix_broken_nullish_or(code);
    assert result == code;
}

test "fix_broken_nullish_or no match" {
    code = 'let x = foo ?? "";';
    result = fix_broken_nullish_or(code);
    assert result == code;
}

test "fix_broken_nullish_or multiple occurrences" {
    code = 'a ?? "" || ""; b ?? "" || "";';
    result = fix_broken_nullish_or(code);
    assert '|| ""' not in result;
}

test "fix_broken_nullish_or realistic jac output" {
    code = 'let v = ev ?? "" || "";';
    result = fix_broken_nullish_or(code);
    assert '|| ""' not in result;
}


# ---------------------------------------------------------------------------
# consolidate_bundle_imports
# ---------------------------------------------------------------------------
test "consolidate_bundle_imports merges duplicate imports" {
    code = 'import { Box } from "ink";\nimport { Text } from "ink";\nconsole.log(1);\n';
    result = consolidate_bundle_imports(code);
    assert result.count('from "ink"') == 1;
    assert "Box" in result;
    assert "Text" in result;
}

test "consolidate_bundle_imports preserves non-import lines" {
    code = 'import { Box } from "ink";\nconsole.log(1);\n';
    result = consolidate_bundle_imports(code);
    assert "console.log(1)" in result;
}


# ---------------------------------------------------------------------------
# hoist_jac_runtime
# ---------------------------------------------------------------------------
test "hoist_jac_runtime no runtime unchanged" {
    code = "console.log(1);";
    (result, runtime) = hoist_jac_runtime(code);
    assert result == code;
    assert runtime is None;
}

test "hoist_jac_runtime hoists runtime block" {
    code = (
        "const _jac = {\n" + "  exc: { Exception: class {} },\n" + "  builtin: {}\n" + "};\n" + "console.log(1);\n"
    );
    (result, runtime) = hoist_jac_runtime(code);
    assert runtime is not None;
    assert "exc" in runtime;
    assert "export { _jac }" in runtime;
    assert "const _jac" not in result;
}


# ---------------------------------------------------------------------------
# _strip_inlined_jac_runtime
# ---------------------------------------------------------------------------
test "_strip_inlined_jac_runtime strips runtime section" {
    code = (
        "// Imported .jac module: @jac/runtime\n" + "// runtime code here\n" + "// Imported .jac module: other\n" + "real code\n"
    );
    result = _strip_inlined_jac_runtime(code);
    assert "@jac/runtime" not in result;
    assert "real code" in result;
}

test "_strip_inlined_jac_runtime no runtime unchanged" {
    code = "real code\n";
    result = _strip_inlined_jac_runtime(code);
    assert result.strip() == code.strip();
}


# ---------------------------------------------------------------------------
# _remove_register_client_module
# ---------------------------------------------------------------------------
test "_remove_register_client_module removes register call" {
    code = "__jacRegisterClientModule(something);\nreal code\n";
    result = _remove_register_client_module(code);
    assert "__jacRegisterClientModule" not in result;
    assert "real code" in result;
}


# ---------------------------------------------------------------------------
# _replace_python_os_import
# ---------------------------------------------------------------------------
test "_replace_python_os_import replaces os environ import" {
    code = "import { environ } from \"os\";\nconsole.log(environ.get('KEY'));\n";
    result = _replace_python_os_import(code);
    assert "const environ = { ...process.env };" in result;
    assert 'from "os"' not in result;
}

test "_replace_python_os_import no os import unchanged" {
    code = "console.log(1);";
    result = _replace_python_os_import(code);
    assert result == code;
}


# ---------------------------------------------------------------------------
# _strip_shimmed_react_imports
# ---------------------------------------------------------------------------
test "_strip_shimmed_react_imports removes shimmed imports" {
    code = 'import { useState, useEffect } from "react";\nconsole.log(1);\n';
    result = _strip_shimmed_react_imports(code);
    assert "useState" not in result;
    assert "useEffect" not in result;
}

test "_strip_shimmed_react_imports keeps non-shimmed react imports" {
    code = 'import { createPortal } from "react";\nconsole.log(1);\n';
    result = _strip_shimmed_react_imports(code);
    assert "createPortal" in result;
}

test "_strip_shimmed_react_imports default plus named import" {
    code = 'import React, { useState, createPortal } from "react";\nconsole.log(1);\n';
    result = _strip_shimmed_react_imports(code);
    assert "React" in result;
    assert "createPortal" in result;
    assert "useState" not in result;
}


# ---------------------------------------------------------------------------
# _finalize_esm_exports
# ---------------------------------------------------------------------------
test "_finalize_esm_exports adds export statement" {
    code = "function app() {}\n";
    result = _finalize_esm_exports(code, ["app"]);
    assert "export { app }" in result;
}

test "_finalize_esm_exports no duplicate export" {
    code = "function app() {}\nexport { app };\n";
    result = _finalize_esm_exports(code, ["app"]);
    assert result.count("export { app }") == 1;
}


# ---------------------------------------------------------------------------
# _inject_runtime_imports
# ---------------------------------------------------------------------------
test "_inject_runtime_imports injects header" {
    code = "function app() {}";
    result = _inject_runtime_imports(code, True);
    assert "./runtime_shim.mjs" in result;
    assert "./jac_runtime_shim.mjs" in result;
    assert "./jac_builtin_runtime.mjs" in result;
}

test "_inject_runtime_imports replaces at jac runtime" {
    code = 'import { useState } from "@jac/runtime";';
    result = _inject_runtime_imports(code);
    assert '@jac/runtime"' not in result;
    assert "./jac_runtime_shim.mjs" in result;
}

test "_inject_runtime_imports no double injection" {
    code = 'import { useState } from "./jac_runtime_shim.mjs";\nfunction app() {}';
    result = _inject_runtime_imports(code, False);
    assert result.count("./runtime_shim.mjs") == 1;
}


# ---------------------------------------------------------------------------
# _apply_ai_tui_module_patches
# ---------------------------------------------------------------------------
test "_apply_ai_tui_module_patches injects fetch transport helper" {
    content = "let TUI_COMMANDS = [];\nfunction app() {}\n";
    path = _make_temp_module(content);
    try {
        _apply_ai_tui_module_patches(path);
        result = path.read_text(encoding="utf-8");
        assert "function isFetchTransportError" in result;
        assert "AbortError" in result;
        assert "TimeoutError" in result;
    } finally {
        path.unlink();
    }
}

test "_apply_ai_tui_module_patches does not double inject helper" {
    content = _FETCH_TRANSPORT_HELPER + "let TUI_COMMANDS = [];\n";
    path = _make_temp_module(content);
    try {
        _apply_ai_tui_module_patches(path);
        result = path.read_text(encoding="utf-8");
        assert result.count("function isFetchTransportError") == 1;
    } finally {
        path.unlink();
    }
}

test "_apply_ai_tui_module_patches widens catch guard basic" {
    content = (
        "function agent_fetch() {\n" + "  try {\n" + "    return fetch();\n" + "  } catch (__jac_e) {\n" + "    if ((__jac_e instanceof _jac.exc.Exception)) {} else {\n" + "      throw __jac_e;\n" + "    }\n" + "  }\n" + "}\n"
    );
    path = _make_temp_module(content);
    try {
        _apply_ai_tui_module_patches(path);
        result = path.read_text(encoding="utf-8");
        assert "isFetchTransportError(__jac_e)" in result;
        assert "(__jac_e instanceof _jac.exc.Exception) || isFetchTransportError(__jac_e)" in result;
    } finally {
        path.unlink();
    }
}

test "_apply_ai_tui_module_patches does not double widen" {
    content = (
        "function agent_fetch() {\n" + "  try {\n" + "    return fetch();\n" + "  } catch (__jac_e) {\n" + "    if ((__jac_e instanceof _jac.exc.Exception) || isFetchTransportError(__jac_e)) {} else {\n" + "      throw __jac_e;\n" + "    }\n" + "  }\n" + "}\n"
    );
    path = _make_temp_module(content);
    try {
        _apply_ai_tui_module_patches(path);
        result = path.read_text(encoding="utf-8");
        double_patched = "|| isFetchTransportError(__jac_e)) || isFetchTransportError(__jac_e))";
        assert double_patched not in result;
    } finally {
        path.unlink();
    }
}

test "_apply_ai_tui_module_patches widens multiple catch blocks" {
    content = (
        "let TUI_COMMANDS = [];\n" + "function agent_fetch() {\n" + "  try {\n" + "    return fetch();\n" + "  } catch (__jac_e) {\n" + "    if ((__jac_e instanceof _jac.exc.Exception)) {} else {\n" + "      throw __jac_e;\n" + "    }\n" + "  }\n" + "}\n" + "function streamLoop() {\n" + "  try {\n" + "    return fetch();\n" + "  } catch (__jac_e) {\n" + "    if ((__jac_e instanceof _jac.exc.Exception)) {} else {\n" + "      throw __jac_e;\n" + "    }\n" + "  }\n" + "}\n"
    );
    path = _make_temp_module(content);
    try {
        _apply_ai_tui_module_patches(path);
        result = path.read_text(encoding="utf-8");
        assert result.count("isFetchTransportError(__jac_e))") >= 2;
    } finally {
        path.unlink();
    }
}

test "_apply_ai_tui_module_patches stream loop unmount tolerance" {
    content = (
        "let TUI_COMMANDS = [];\n" + "    } catch (__jac_e) {\n" + "      if ((__jac_e instanceof _jac.exc.Exception) || isFetchTransportError(__jac_e)) {} else {\n" + "        throw __jac_e;\n" + "      }\n" + "    }\n" + "    if (_unmounted) {\n"
    );
    path = _make_temp_module(content);
    try {
        _apply_ai_tui_module_patches(path);
        result = path.read_text(encoding="utf-8");
        assert "|| _unmounted || isFetchTransportError(__jac_e)" in result;
    } finally {
        path.unlink();
    }
}

test "_apply_ai_tui_module_patches no helper without tui commands marker" {
    content = (
        "function app() {\n" + "  try {\n" + "    return fetch();\n" + "  } catch (__jac_e) {\n" + "    if ((__jac_e instanceof _jac.exc.Exception)) {} else {\n" + "      throw __jac_e;\n" + "    }\n" + "  }\n" + "}\n"
    );
    path = _make_temp_module(content);
    try {
        _apply_ai_tui_module_patches(path);
        result = path.read_text(encoding="utf-8");
        assert "function isFetchTransportError" not in result;
        assert "isFetchTransportError(__jac_e)" in result;
    } finally {
        path.unlink();
    }
}

test "_apply_ai_tui_module_patches helper fragment validates structure" {
    helper = _FETCH_TRANSPORT_HELPER;
    assert helper.startswith("function isFetchTransportError");
    assert "if (!err) return false" in helper;
    assert '"AbortError"' in helper;
    assert '"TimeoutError"' in helper;
    assert '"TypeError"' in helper;
    assert '"fetch failed"' in helper;
    assert '"econnreset"' in helper;
    assert '"network"' in helper;
    assert "return false" in helper;
}


# ---------------------------------------------------------------------------
# Integration / smoke test
# ---------------------------------------------------------------------------
test "compile runtime.cl.jac succeeds" {
    repo_root = Path(__file__).resolve().parent.parent;
    entry_path = repo_root / "jac_super" / "ai_tui_ink" / "runtime.cl.jac";
    if not entry_path.is_file() {
        return;
    }

    tmpdir = tempfile.mkdtemp();
    try {
        out = Path(tmpdir) / "tui";
        entry_name = compile_ink_app(entry_path, out, ai_tui_patches=True);

        assert entry_name in ("app", );
        assert (out / "module.mjs").is_file();
        assert (out / "runner.mjs").is_file();
        assert (out / "runtime_shim.mjs").is_file();
        assert (out / "jac_runtime_shim.mjs").is_file();
        assert (out / "package.json").is_file();

        module = (out / "module.mjs").read_text(encoding="utf-8");
        assert len(module) > 1000;
        assert "isFetchTransportError" in module;
        assert "streamLoop" in module or "agent_fetch" in module;

        pkg = json.loads((out / "package.json").read_text(encoding="utf-8"));
        assert pkg["type"] == "module";
        assert "ink" in pkg["dependencies"];
        assert "react" in pkg["dependencies"];
    } finally {
        import shutil;
        shutil.rmtree(tmpdir, ignore_errors=True);
    }
}

test "compile without ai_tui_patches" {
    repo_root = Path(__file__).resolve().parent.parent;
    entry_path = repo_root / "jac_super" / "ai_tui_ink" / "runtime.cl.jac";
    if not entry_path.is_file() {
        return;
    }

    tmpdir = tempfile.mkdtemp();
    try {
        out = Path(tmpdir) / "tui";
        compile_ink_app(entry_path, out, ai_tui_patches=False);

        module = (out / "module.mjs").read_text(encoding="utf-8");
        assert "function isFetchTransportError" not in module;
    } finally {
        import shutil;
        shutil.rmtree(tmpdir, ignore_errors=True);
    }
}
