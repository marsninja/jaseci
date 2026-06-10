"""Post-process Jac client bundles for Ink terminal output.

Vendored from jac-ink (jac_ink.plugin.bundle_patch) for jac-super's internal
compile path -- no jac-ink pip dependency required for ``jac ai --tui``.
"""

import re;

glob _JAC_RUNTIME_START = re.compile(r"(?m)^\s*const _jac = \{\s*$"),
     _IMPORT_LINE_RE = re.compile(
         r'^import\s+\{([^}]+)\}\s+from\s+(["\'])([^"\']+)\2;\s*$'
     ),
     _THEME_IMPORT_RE = re.compile(r"^\./(?:.*/)?theme\.js$"),
     _MODULE_MARKER = re.compile(
         r"(?m)^//\s*(?:Imported \.jac module:|Client module:)\s*(.+?)\s*$"
     ),
     _IMPORT_ORDER: list[str] = [
         "./runtime_shim.mjs",
         "./jac_runtime_shim.mjs",
         "./jac_builtin_runtime.mjs",
         "ink",
         "@inkjs/ui",
         "./jac_pi_runtime_shim.mjs",

     ],
     _BROKEN_NULLISH_OR = re.compile(r'(\w+(?:\[\w+\])?\s*\?\?\s*""\s*)\|\|\s*""');


def hoist_jac_runtime(code: str) -> tuple[str, str | None] {
    matches: list[re.Match[str]] = list(_JAC_RUNTIME_START.finditer(code));
    if not matches {
        return (code, None);
    }

    remove_ranges: list[tuple[int, int]] = [];
    runtime_body: str | None = None;
    for (idx, m) in enumerate(matches) {
        start = m.start();
        end = _end_of_jac_runtime_block(code, m.end());
        if idx == 0 {
            runtime_body = code[start:end].strip();
        }
        remove_ranges.append((start, end));
    }

    out: list[str] = [];
    pos = 0;
    for (start, end) in remove_ranges {
        out.append(code[pos:start]);
        pos = end;
    }
    out.append(code[pos:]);
    stripped = "".join(out);

    runtime_module = f"{runtime_body}\nexport {{ _jac }};\n";
    return (stripped, runtime_module);
}


def _end_of_jac_runtime_block(code: str, open_brace_end: int) -> int {
    (_, end) = _extract_brace_block(code, open_brace_end);
    while end < len(code) and code[end] in " \t" {
        end += 1;
    }
    if end < len(code) and code[end] == ";" {
        end += 1;
    }
    while end < len(code) and code[end] in " \t" {
        end += 1;
    }
    if end < len(code) and code[end] == "\r" {
        end += 1;
    }
    if end < len(code) and code[end] == "\n" {
        end += 1;
    }
    return end;
}


def _is_theme_module_marker(line: str) -> bool {
    stripped = line.strip();
    if not stripped.startswith("// Imported .jac module:") {
        return False;
    }
    path = stripped.split(":", 1)[1].strip();
    return path == ".theme" or path.endswith(".theme") or path.endswith("theme.cl.jac");
}


def consolidate_bundle_imports(code: str) -> str {
    lines = code.split("\n");
    merged: dict[str, set[str]] = {};
    body: list[str] = [];
    theme_block: list[str] | None = None;

    i = 0;
    while i < len(lines) {
        line = lines[i];

        if _is_theme_module_marker(line) {
            i += 1;
            block: list[str] = [];
            while i < len(lines) {
                tl = lines[i];
                if _MODULE_MARKER.match(tl) {
                    i -= 1;
                    break;
                }
                if tl.strip() == "" and block {
                    break;
                }
                block.append(tl);
                i += 1;
            }
            if theme_block is None {
                theme_block = block;
            }
            i += 1;
            continue;
        }

        m = _IMPORT_LINE_RE.match(line);
        if m {
            spec = m.group(3);
            if not _THEME_IMPORT_RE.match(spec) {
                if spec not in merged {
                    merged[spec] = set();
                }
                merged[spec].update(
                    [
                        name.strip()
                        for name in m.group(1).split(",")
                        if name.strip()
                    ]
                );
            }
            i += 1;
            continue;
        }

        body.append(line);
        i += 1;
    }

    full_code = "\n".join(body);

    if re.search(r"\bStatic\b", full_code) {
        if "ink" not in merged {
            merged["ink"] = set();
        }
        merged["ink"].add("Static");
    }
    if re.search(r"\bSpinner\b", full_code) {
        if "@inkjs/ui" not in merged {
            merged["@inkjs/ui"] = set();
        }
        merged["@inkjs/ui"].add("Spinner");
    }
    for sym in ("Box", "Text", "useInput") {
        if re.search(rf"\b{sym}\b", full_code) {
            if "ink" not in merged {
                merged["ink"] = set();
            }
            merged["ink"].add(sym);
        }
    }

    import_lines: list[str] = [];
    seen: set[str] = set();
    for spec in _IMPORT_ORDER {
        names = merged.get(spec);
        if not names {
            continue;
        }
        sorted_names = sorted(names);
        import_lines.append(f'import {{ {", ".join(sorted_names)} }} from "{spec}";');
        seen.add(spec);
    }

    for spec in sorted(merged) {
        if spec in seen or not merged[spec] {
            continue;
        }
        sorted_names = sorted(merged[spec]);
        import_lines.append(f'import {{ {", ".join(sorted_names)} }} from "{spec}";');
    }

    theme_lines: list[str] = theme_block if theme_block is not None else [];
    parts: list[str] = [*import_lines, *theme_lines];
    if body {
        if parts {
            parts.append("");
        }
        parts.extend(body);
    }
    return "\n".join(parts);
}


def _extract_brace_block(code: str, start: int) -> tuple[str, int] {
    depth = 0;
    i = start - 1;
    if i < 0 or code[i] != "{" {
        return ("", start);
    }
    depth = 1;
    i = start;
    while i < len(code) and depth != 0 {
        ch = code[i];
        if ch == "'" or ch == "\"" {
            i = _skip_string(code, i);
            continue;
        }
        if ch == "/" and i + 1 < len(code) and code[i + 1] == "/" {
            nl = code.find("\n", i);
            if nl == -1 {
                i = len(code);
            } else {
                i = nl;
            }
            continue;
        }
        if ch == "/" and i + 1 < len(code) and code[i + 1] == "*" {
            end_comment = code.find("*/", i + 2);
            if end_comment != -1 {
                i = end_comment + 2;
            } else {
                i = len(code);
            }
            continue;
        }
        if ch == "`" {
            i += 1;
            while i < len(code) {
                if code[i] == "\\" {
                    i += 2;
                    continue;
                }
                if code[i] == "`" {
                    i += 1;
                    break;
                }
                i += 1;
            }
            continue;
        }
        if ch == "{" {
            depth += 1;
        } elif ch == "}" {
            depth -= 1;
            if depth == 0 {
                return (code[start:i], i + 1);
            }
        }
        i += 1;
    }
    return (code[start:], len(code));
}


def _skip_string(code: str, i: int) -> int {
    quote = code[i];
    i += 1;
    while i < len(code) {
        ch = code[i];
        if ch == "\\" {
            i += 2;
            continue;
        }
        if ch == quote {
            return i + 1;
        }
        i += 1;
    }
    return len(code);
}


def fix_broken_nullish_or(code: str) -> str {
    result: str = _BROKEN_NULLISH_OR.sub(r"\1", code);
    return result;
}
