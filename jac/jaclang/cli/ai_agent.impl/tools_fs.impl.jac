import os;
import re;
import from pathlib { Path }

impl FileTools.write_feedback(path: str) -> str {
    if self.ws.ci is None or not self.cfg.inline_feedback {
        if self.ws.ci is not None and not self.cfg.inline_feedback {
            self.ws.ci_dirty = True;
        }
        return "";
    }

    self.ws.ci_dirty = True;
    try {
        diags: list = list(self.ws.ci.refresh_and_diff(path));
    } except Exception {
        return "";
    }
    self.ws.ci_dirty = False;
    if not diags {
        return "";
    }
    (n_err, n_warn) = _count_diags(diags);
    lines = [
        f"\ncompiler feedback for editing {path} -- {n_err} error(s), "
        f"{n_warn} warning(s); fix what you introduced (some may be in other "
        "files your edit affects):"
    ];
    for d in diags[:20] {
        lines.append("  " + str(d.render()));
    }
    if len(diags) > 20 {
        lines.append(f"  ... and {len(diags) - 20} more");
    }
    return "\n".join(lines);
}

impl FileTools._js_drift_error(path: str, content: str) -> str {
    base = os.path.basename(path);

    for ext in [".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs"] {
        if base.endswith(ext) {
            return (
                f"REFUSED: '{base}' is a JavaScript/TypeScript file, but this is a "
                "Jac project -- all source is Jac. Write a .jac file instead "
                "(a client UI component goes in a .cl.jac file, e.g. "
                "components/Calculator.cl.jac), using Jac syntax (def:pub "
                "Name() -> JsxElement, has fields, def handlers). Do not create "
                ".js/.ts files."
            );
        }
    }

    if not base.endswith(".jac") {
        return "";
    }

    checks: list[tuple[str, str]] = [
        (
            "`import React` / a React import",
            "import\\s+React\\b|from\\s+['\"]react['\"]"
        ),
        (
            "`export` (Jac has no export -- a `def:pub` is the public form)",
            "(?m)^\\s*export\\b"
        ),
        ("`function` (use `def`)", "(?m)^\\s*(async\\s+)?function\\b"),
        (
            "an arrow function `=>` (use `lambda(x: T) -> R { ... }`)",
            "(\\w|\\)|\\]|\\})\\s*=>"
        ),
        (
            "`const`/`let`/`var` (declare typed: `x: int = 1`)",
            "(?m)^\\s*(const|let|var)\\s"
        ),
        ("`this.` (use `self.`; props are function params)", "\\bthis\\."),
        (
            "a `constructor(` (a component is `def:pub Name() -> JsxElement`)",
            "(?m)^\\s*constructor\\s*\\("
        ),
        ("`===` / `!==` (use `==` / `!=`)", "===|!==")
    ];
    hits: list[str] = [];
    for (label, pat) in checks {
        if re.search(pat, content) {
            hits.append(label);
        }
    }
    if not hits {
        return "";
    }
    found = "; ".join(hits);
    return (
        f"REFUSED: {base} contains JavaScript/React, not Jac. Found: {found}. "
        "Rewrite it in Jac: a UI component is `def:pub Name(prop: T) -> "
        "JsxElement { has state: int = 0; def on_click(e: MouseEvent) {...} "
        "return <div>...</div>; }`. Read read_guide(\"jac-cl-components\") for "
        "the exact shapes, then write the file again as Jac."
    );
}

sem FileTools.read_file = "Read and return the full text of a file.";
sem FileTools.read_file.path = "Path to the file to read, relative to the project.";
impl FileTools.read_file(path: str) -> str {
    try {
        return truncate(Path(self.ws.resolve(path)).read_text(encoding="utf-8"));
    } except Exception as e {
        return f"ERROR reading {path}: {e}";
    }
}

sem FileTools.write_file = "Create a file or overwrite it entirely with new content.";
sem FileTools.write_file.path = "Path of the file to write.";
sem FileTools.write_file.content = "The full new contents of the file.";
impl FileTools.write_file(path: str, content: str) -> str {
    drift = self._js_drift_error(path, content);
    if drift {
        return drift;
    }
    if not confirm(f"write {len(content)} chars to {path}") {
        return "DENIED: the user declined this write.";
    }
    try {
        rp = self.ws.resolve(path);
        p = Path(rp);
        p.parent.mkdir(parents=True, exist_ok=True);
        p.write_text(content, encoding="utf-8");
        return f"OK: wrote {len(content)} chars to {path}" + self.write_feedback(rp);
    } except Exception as e {
        return f"ERROR writing {path}: {e}";
    }
}

sem FileTools.edit_file = "Replace one exact, unique occurrence of text in a file.";
sem FileTools.edit_file.path = "Path of the file to edit.";
sem FileTools.edit_file.old_text = "Exact text to find; must occur exactly once in the file.";
sem FileTools.edit_file.new_text = "Text to replace it with.";
impl FileTools.edit_file(path: str, old_text: str, new_text: str) -> str {
    rp = self.ws.resolve(path);
    if not os.path.isfile(rp) {
        return (
            f"ERROR: {path} does not exist, so there is nothing to edit. "
            "Create it with write_file(path, content) instead. (Paths resolve "
            f"against the current directory {self.ws.cwd or os.getcwd()}.)"
        );
    }
    try {
        original = Path(rp).read_text(encoding="utf-8");
    } except Exception as e {
        return f"ERROR reading {path}: {e}";
    }
    occurrences = original.count(old_text);
    if occurrences == 0 {
        return f"ERROR: old_text was not found in {path}. Read the file first.";
    }
    if occurrences > 1 {
        return (
            f"ERROR: old_text appears {occurrences} times in {path}; "
            "include more surrounding context so it matches exactly once."
        );
    }
    updated = original.replace(old_text, new_text);
    drift = self._js_drift_error(path, updated);
    if drift {
        return drift;
    }
    if not confirm(f"edit {path}") {
        return "DENIED: the user declined this edit.";
    }
    try {
        Path(rp).write_text(updated, encoding="utf-8");
        return f"OK: edited {path}" + self.write_feedback(rp);
    } except Exception as e {
        return f"ERROR writing {path}: {e}";
    }
}

sem FileTools.list_dir = "List the entries of a directory (hidden entries excluded).";
sem FileTools.list_dir.path = "Directory path; empty string means the current directory.";
impl FileTools.list_dir(path: str) -> str {
    try {
        target = Path(self.ws.resolve(path));
        names: list[str] = [];
        for entry in sorted(target.iterdir()) {
            if entry.name.startswith(".") {
                continue;
            }
            names.append(entry.name + ("/" if entry.is_dir() else ""));
        }
        return "\n".join(names) or "(empty directory)";
    } except Exception as e {
        return f"ERROR listing {path}: {e}";
    }
}

sem FileTools.grep = "Search for a regular expression across .jac files (or one file).";
sem FileTools.grep.pattern = "Python regular expression to search for.";
sem FileTools.grep.path = "File or directory to search; empty string means current directory.";
impl FileTools.grep(pattern: str, path: str) -> str {
    try {
        regex = re.compile(pattern);
    } except Exception as e {
        return f"ERROR: invalid regular expression: {e}";
    }
    search_root = Path(self.ws.resolve(path));
    if search_root.is_file() {
        files = [search_root];
    } elif search_root.is_dir() {
        files = [
            f
            for f in search_root.rglob("*.jac")
            if f.is_file()
        ];
    } else {
        return f"ERROR: no such path: {path}";
    }
    hits: list[str] = [];
    for f in files {
        try {
            text = f.read_text(encoding="utf-8");
        } except Exception {
            continue;
        }
        for (line_no, line) in enumerate(text.splitlines(), 1) {
            if regex.search(line) {
                hits.append(f"{f}:{line_no}: {line.strip()}");
                if len(hits) >= 100 {
                    return "\n".join(hits) + "\n... [stopped at 100 matches]";
                }
            }
        }
    }
    return "\n".join(hits) or "(no matches)";
}
