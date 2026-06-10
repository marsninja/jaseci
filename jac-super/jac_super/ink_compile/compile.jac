"""Compile Jac client (.cl.jac) sources to an Ink terminal bundle.

Internal to jac-super -- powers ``jac ai --tui`` without a jac-ink dependency.
"""

import json;
import re;
import tomllib;
import from pathlib { Path }
import from .bundle_patch {
    consolidate_bundle_imports,
    fix_broken_nullish_or,
    hoist_jac_runtime
}
import from jaclang { JacRuntime as Jac }
import from jaclang.runtimelib.client_bundle { ClientBundleBuilder, ClientBundleError }

glob _RUNTIME_SHIM_IMPORT_HEADER: str = (
         'import { __jacJsx, __jacSpawn } from "./runtime_shim.mjs";\n' + "import { Fragment, createContext, useCallback, useContext, useEffect, " + 'useMemo, useRef, useState } from "./jac_runtime_shim.mjs";\n'
     ),
     _RUNTIME_SHIM: str = """import React from "react";

function __jacJsx(tag, props = {}, children = []) {
  const raw = Array.isArray(children) ? children : [children];
  const list = raw
    .flat()
    .filter((c) => c !== false && c != null && c !== undefined);
  return React.createElement(tag, props || {}, ...list);
}

function __jacSpawn() {
  throw new Error("jac2ink runtime shim: __jacSpawn is not supported in Ink mode yet.");
}

export {__jacJsx, __jacSpawn};
""",
     _JAC_RUNTIME_SHIM: str = """import React from "react";

const unsupported = (name) => {
  return (..._args) => {
    throw new Error(`jac2ink: @jac/runtime export '${name}' is not supported in Ink mode yet.`);
  };
};

const jacSignup = unsupported("jacSignup");
const jacLogin = unsupported("jacLogin");
const jacLogout = unsupported("jacLogout");
const jacIsLoggedIn = unsupported("jacIsLoggedIn");

export const {
  useState,
  useEffect,
  useMemo,
  useCallback,
  useRef,
  useContext,
  createContext,
  Fragment,
} = React;

export {
  jacSignup,
  jacLogin,
  jacLogout,
  jacIsLoggedIn,
};
""",
     _FETCH_TRANSPORT_HELPER: str = """function isFetchTransportError(err) {
  if (!err) return false;
  const name = String(err.name || "");
  const msg = String(err.message || err).toLowerCase();
  if (name === "AbortError" || name === "TimeoutError" || name === "TypeError") return true;
  if (msg.includes("aborted") || msg.includes("fetch failed") || msg.includes("econnreset") || msg.includes("network")) return true;
  return false;
}

""";


class CompileError(Exception) {}


def compile_ink_app(
    entry_file: Path, out_dir: Path, entry_fn: str = "", ai_tui_patches: bool = True,
) -> str {
    entry_file = entry_file.resolve();
    out_dir = out_dir.resolve();

    if not entry_file.is_file() {
        raise CompileError(f"Entry file not found: {entry_file}");
    }
    if not str(entry_file).endswith(".jac") {
        raise CompileError(f"Not a .jac file: {entry_file}");
    }

    base_path = str(entry_file.parent);
    module_stem = _module_stem(entry_file);

    try {
        (_, ) = Jac.jac_import(module_stem, base_path);
    } except Exception as exc {
        raise CompileError(f"Compilation failed: {exc}") from exc;
    }

    source_path = entry_file;
    try {
        builder = ClientBundleBuilder();
        (js_code, jac_mod) = builder._compile_to_js(source_path);
    } except ClientBundleError as exc {
        raise CompileError(f"JS compilation failed: {exc}") from exc;
    } except Exception as exc {
        raise CompileError(f"JS compilation failed: {exc}") from exc;
    }

    if not js_code.strip() {
        raise CompileError(
            "Compilation produced no JS output. "
            "Use a .cl.jac entry with def:pub client exports."
        );
    }

    manifest = jac_mod.gen.client_manifest if jac_mod else None;
    exports: list[str] = [];
    if manifest {
        exports = sorted(manifest.exports or []);
    }
    if not exports {
        for name in re.findall(r"def:pub\s+(\w+)\s*\(", source_path.read_text()) {
            exports.append(str(name));
        }
    }
    if not exports {
        raise CompileError(
            "No public client functions found. "
            "Export an entry with def:pub app() -> JsxElement in client code."
        );
    }

    entry_name = _pick_entry(entry_fn, exports);
    out_dir.mkdir(parents=True, exist_ok=True);

    (module_code, jac_runtime) = _prepare_tui_module(js_code, exports, entry_file);
    (out_dir / "module.mjs").write_text(module_code, encoding="utf-8");
    (out_dir / "runtime_shim.mjs").write_text(_RUNTIME_SHIM, encoding="utf-8");
    (out_dir / "jac_runtime_shim.mjs").write_text(_JAC_RUNTIME_SHIM, encoding="utf-8");
    if jac_runtime {
        runtime_path = out_dir / "jac_builtin_runtime.mjs";
        runtime_path.write_text(jac_runtime, encoding="utf-8");
        if ai_tui_patches {
            _apply_ai_tui_module_patches(out_dir / "module.mjs");
        }
    }

    _emit_runner(out_dir, entry_name, exports);
    _emit_package_json(out_dir, module_code, entry_file.parent);
    return entry_name;
}


def _module_stem(file_path: Path) -> str {
    name = file_path.name;
    if name.endswith(".cl.jac") {
        return name[:-7];
    }
    return file_path.stem;
}


def _pick_entry(entry_fn: str, exports: list[str]) -> str {
    chosen = entry_fn.strip();
    if chosen {
        return chosen;
    }
    if "app" in exports {
        return "app";
    }
    return exports[0];
}


def _prepare_tui_module(
    bundle_code: str, exports: list[str], entry_file: Path,
) -> tuple[str, str | None] {
    code = _strip_inlined_jac_runtime(bundle_code);
    code = _remove_register_client_module(code);
    (code, jac_runtime) = hoist_jac_runtime(code);
    code = fix_broken_nullish_or(code);
    if jac_runtime {
        jac_runtime = fix_broken_nullish_or(jac_runtime);
    }
    code = _inject_runtime_imports(code, jac_runtime is not None);
    code = _strip_shimmed_react_imports(code);
    code = _replace_python_os_import(code);
    code = consolidate_bundle_imports(code);
    return (_finalize_esm_exports(code, exports), jac_runtime);
}


def _strip_inlined_jac_runtime(code: str) -> str {
    lines = code.split("\n");
    out: list[str] = [];
    skipping = False;
    for line in lines {
        stripped = line.strip();
        if (
            stripped.startswith("// Imported .jac module: @jac/runtime")
            or stripped == "// @jac/runtime"
        ) {
            skipping = True;
            continue;
        }
        if skipping {
            if (
                stripped.startswith("// Imported .jac module:")
                and "@jac/runtime" not in stripped
            )
            or stripped.startswith("// Client module:") {
                skipping = False;
                out.append(line);
            }
            continue;
        }
        out.append(line);
    }
    return "\n".join(out);
}


def _remove_register_client_module(code: str) -> str {
    lines = code.split("\n");
    kept: list[str] = [];
    for line in lines {
        if line.strip().startswith("__jacRegisterClientModule(") {
            continue;
        }
        kept.append(line);
    }
    return "\n".join(kept);
}


def _inject_runtime_imports(js_code: str, with_jac_builtin: bool = False) -> str {
    code = js_code.replace('from "@jac/runtime"', 'from "./jac_runtime_shim.mjs"');
    header = _RUNTIME_SHIM_IMPORT_HEADER;
    if with_jac_builtin {
        header = header + 'import { _jac } from "./jac_builtin_runtime.mjs";\n';
    }
    if 'from "./runtime_shim.mjs"' in code {
        if with_jac_builtin and 'from "./jac_builtin_runtime.mjs"' not in code {
            return header + code;
        }
        return code;
    }
    return header + code;
}


def _is_shimmed_react_export(name: str) -> bool {
    return name in {
        "useState",
        "useEffect",
        "useMemo",
        "useCallback",
        "useRef",
        "useContext",
        "createContext",
        "Fragment",

    };
}


def _strip_shimmed_react_imports(code: str) -> str {
    lines = code.split("\n");
    out: list[str] = [];
    for line in lines {
        stripped = line.strip();
        if (not stripped.startswith("import "))
        or (('from "react"' not in stripped) and ("from 'react'" not in stripped)) {
            out.append(line);
            continue;
        }
        from_idx = stripped.index(" from ");
        clause = stripped[7:from_idx].strip();
        quote = '"react"' if 'from "react"' in stripped else "'react'";
        indent = line[:len(line) - len(line.lstrip())];

        if clause.startswith("{") and clause.endswith("}") {
            inner = clause[1:-1];
            kept = [
                part.strip()
                for part in inner.split(",")
                if part.strip() and not _is_shimmed_react_export(part.strip())
            ];
            if kept {
                out.append(
                    indent + "import { " + ", ".join(kept) + " } from " + quote + ";"
                );
            }
            continue;
        }

        if ", {" in clause {
            default_part = clause.split(", {", 1)[0].strip();
            brace_inner = clause.split(", {", 1)[1];
            if brace_inner.endswith("}") {
                brace_inner = brace_inner[:-1];
            }
            kept = [
                part.strip()
                for part in brace_inner.split(",")
                if part.strip() and not _is_shimmed_react_export(part.strip())
            ];
            if kept {
                out.append(
                    indent + "import " + default_part + ", { " + ", ".join(kept) + " } from " + quote + ";"
                );
            } else {
                out.append(indent + "import " + default_part + " from " + quote + ";");
            }
            continue;
        }

        out.append(line);
    }
    return "\n".join(out);
}


def _replace_python_os_import(code: str) -> str {
    os_import_re = re.compile(
        r'^import\s+\{\s*environ\s*\}\s+from\s+["\']os["\'];\s*$'
    );
    lines = code.split("\n");
    out: list[str] = [];
    shimmed = False;
    for line in lines {
        if os_import_re.match(line.strip()) {
            if not shimmed {
                out.append("const environ = { ...process.env };");
                shimmed = True;
            }
            continue;
        }
        out.append(line);
    }
    return "\n".join(out);
}


def _finalize_esm_exports(code: str, exports: list[str]) -> str {
    if re.search(r"(?m)^\s*export\s*\{", code) {
        return code;
    }
    if not exports {
        return code;
    }
    names = ", ".join(exports);
    return code.rstrip() + "\nexport { " + names + " };\n";
}


def _apply_ai_tui_module_patches(module_path: Path) -> None {
    if not module_path.is_file() {
        return;
    }

    text = module_path.read_text(encoding="utf-8");

    if "function isFetchTransportError" not in text {
        marker = "let TUI_COMMANDS = ";
        idx = text.find(marker);
        if idx != -1 {
            text = text[:idx] + _FETCH_TRANSPORT_HELPER + text[idx:];
        }
    }

    text = re.sub(
        r"(__jac_e instanceof _jac\.exc\.Exception)\)\)(?!.*isFetchTransportError)",
        r"\1) || isFetchTransportError(__jac_e))",
        text,
    );

    stream_narrow = (
        "    } catch (__jac_e) {\n"
        "      if ((__jac_e instanceof _jac.exc.Exception) || isFetchTransportError(__jac_e)) {} else {\n"
        "        throw __jac_e;\n"
        "      }\n"
        "    }\n"
        "    if (_unmounted) {"
    );
    stream_tolerant = (
        "    } catch (__jac_e) {\n"
        "      if ((__jac_e instanceof _jac.exc.Exception) || _unmounted || isFetchTransportError(__jac_e)) {} else {\n"
        "        throw __jac_e;\n"
        "      }\n"
        "    }\n"
        "    if (_unmounted) {"
    );
    if stream_narrow in text {
        text = text.replace(stream_narrow, stream_tolerant, 1);
    }

    module_path.write_text(text, encoding="utf-8");
}


def _emit_runner(out_dir: Path, entry_name: str, exports: list[str]) {
    runner: str = (
        'import React from "react";\n' + 'import {render, Text} from "ink";\n' + 'import * as JacModule from "./module.mjs";\n' + "\n" + 'const entryName = process.env.JAC_INK_ENTRY || "__ENTRY__";\n' + "const exportsList = __EXPORTS_JSON__;\n" + "\n" + "const showError = (msg) => {\n" + '  render(React.createElement(Text, {color: "red"}, msg));\n' + "  process.exitCode = 1;\n" + "};\n" + "\n" + "const mount = (value) => {\n" + "  if (React.isValidElement(value)) {\n" + "    render(value);\n" + "    return;\n" + "  }\n" + "  render(React.createElement(Text, {}, String(value)));\n" + "};\n" + "\n" + "const chosen = JacModule[entryName];\n" + "if (chosen === undefined) {\n" + "  const avail = exportsList.length > 0 ? exportsList.join(\", \") : \"(none)\";\n" + "  showError(`jac2ink: export '${entryName}' not found. Available exports: ${avail}`);\n" + "} else {\n" + "  try {\n" + "    if (typeof chosen === \"function\") {\n" + "      render(React.createElement(chosen));\n" + "    } else {\n" + "      mount(chosen);\n" + "    }\n" + "  } catch (err) {\n" + "    showError(`jac2ink: entry '${entryName}' failed: ${String(err)}`);\n" + "  }\n" + "}\n"
    );
    runner = runner.replace("__ENTRY__", entry_name);
    runner = runner.replace("__EXPORTS_JSON__", json.dumps(exports));
    (out_dir / "runner.mjs").write_text(runner, encoding="utf-8");
}


def _emit_package_json(out_dir: Path, module_code: str, project_dir: Path) {
    deps: dict[str, str] = {"ink": "^7.0.3", "react": "^19.2.4"};

    for pkg in _scan_npm_imports(module_code) {
        if pkg not in deps {
            deps[pkg] = "*";
        }
    }

    for (name, version) in _read_jac_toml_npm_deps(project_dir).items() {
        deps[name] = version;
    }

    pkg_path = out_dir / "package.json";
    if pkg_path.exists() {
        try {
            existing = json.loads(pkg_path.read_text(encoding="utf-8"));
            existing_deps = existing.get("dependencies", {});
            if isinstance(existing_deps, dict) {
                for (key, value) in existing_deps.items() {
                    if key not in deps {
                        deps[key] = str(value);
                    }
                }
            }
        } except Exception { }
    }

    pkg = {
        "name": "jac-ink-app",
        "private": True,
        "type": "module",
        "engines": {"node": ">=22"},
        "scripts": {"start": "node runner.mjs"},
        "dependencies": deps,

    };
    pkg_path.write_text(json.dumps(pkg, indent=2) + "\n", encoding="utf-8");
}


def _scan_npm_imports(module_code: str) -> list[str] {
    found: list[str] = [];
    pattern = r'from\s+["\']([^"\']+)["\']';
    for npm_pkg in re.findall(pattern, module_code) {
        pkg = str(npm_pkg);
        if pkg.startswith(".") or pkg.startswith("@jac/") {
            continue;
        }
        pkg_root = pkg.split("/")[0];
        if pkg.startswith("@") and "/" in pkg {
            pkg_root = "/".join(pkg.split("/")[:2]);
        }
        if pkg_root not in found {
            found.append(pkg_root);
        }
    }
    return found;
}


def _read_jac_toml_npm_deps(project_dir: Path) -> dict[str, str] {
    toml_path = _find_jac_toml(project_dir);
    if toml_path is None {
        return {};
    }
    try {
        data = tomllib.loads(toml_path.read_text(encoding="utf-8"));
    } except Exception {
        return {};
    }
    deps: dict[str, str] = {};
    root_deps = data.get("dependencies", {}).get("npm", {});
    if isinstance(root_deps, dict) {
        for (key, value) in root_deps.items() {
            deps[str(key)] = str(value);
        }
    }
    plugin_deps = (
        data.get("plugins", {}).get("client", {}).get("dependencies", {}).get("npm", {})
    );
    if isinstance(plugin_deps, dict) {
        for (key, value) in plugin_deps.items() {
            deps[str(key)] = str(value);
        }
    }
    return deps;
}


def _find_jac_toml(start_dir: Path) -> Path | None {
    current = start_dir.resolve();
    for _ in range(32) {
        candidate = current / "jac.toml";
        if candidate.is_file() {
            return candidate;
        }
        if current.parent == current {
            break;
        }
        current = current.parent;
    }
    return None;
}
