import os;
import from jaclang.compiler.code_intel { CodeIntelligence }

impl Workspace.resolve(path: str) -> str {
    p = path or ".";
    if os.path.isabs(p) {
        return os.path.normpath(p);
    }
    base = self.cwd or os.getcwd();
    return os.path.normpath(os.path.join(base, p));
}

impl Workspace.set_cwd(new_dir: str) {
    real = os.path.normpath(new_dir);
    if not os.path.isdir(real) or real == self.cwd {
        return;
    }
    prev_root = _project_root_of(self.cwd) if self.cwd else "";
    self.cwd = real;
    new_root = _project_root_of(real);

    if self.ci is not None and new_root != prev_root {
        try {
            new_ci = CodeIntelligence(proj_dir=new_root, lazy=True);
            new_ci.on_event = self.ci.on_event;
            self.ci = new_ci;
            self.ci_dirty = False;
        } except Exception as e {
            _ = e;
        }
    }
}

impl Workspace.code_intel -> any {
    if self.ci is None {
        return None;
    }
    if self.ci_dirty {
        try {
            self.ci.refresh();
            self.ci_dirty = False;
        } except Exception { }
    }
    return self.ci;
}

impl Workspace.project_errors -> list {
    ci = self.code_intel();
    if ci is None or not ci.is_loaded() {
        return [];
    }
    try {
        return [
            d
            for d in ci.diagnostics()
            if d.severity == "error"
        ];
    } except Exception {
        return [];
    }
}

impl _project_root_of(start: str) -> str {
    import from jaclang.jac0core.modresolver { find_project_root }
    import from pathlib { Path }
    result = find_project_root(Path(start));
    return str(result[0]) if result else os.path.normpath(start);
}
