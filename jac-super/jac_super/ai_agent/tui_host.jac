"""ctypes binding to the in-process NA TUI shared library (libtui.so).

This is the sv-side half of the in-process seam (PLAN-tui-in-process §5/§6). It
`ctypes.CDLL`s `ai_tui_na/bin/libtui.so` and wraps its eight `:pub` exports in a
`TuiHost` object. na -> sv is a PULL QUEUE, not callbacks: there are no
`CFUNCTYPE` trampolines and no keep-alive globals -- the host calls
`next_command()` after each key to drain commands the native layer enqueued.

Threading contract the caller (run_tui_in_process) MUST honor, mirrored from the
native side (PLAN §9): `wait_key` is the ONLY lock-free call (pure poll(2), GIL
released for the duration of the foreign call); `apply_frame` / `handle_key` /
`next_command` / `quit_requested` / `render` all read or mutate the native
TuiState and MUST run under the host's render lock.
"""

obj TuiHost {
    has lib: any = None;

    def load(lib_path: str) {
        # Resolve to an absolute path before CDLL: a bare name only works if it is
        # next to the loader or on the search path (a Windows footgun; harmless on
        # Linux/macOS). See PLAN §16 "Windows DLL search path".
        import ctypes;
        import os;

        abs_path = os.path.abspath(lib_path);
        self.lib = ctypes.CDLL(abs_path);

        # int <-> c_int64, str <-> c_char_p (the frame blob / command lines). The
        # native TuiState never crosses the ABI, so no pointer/handle marshalling.
        self.lib.tui_init.restype = ctypes.c_int64;
        self.lib.tui_init.argtypes = [
            ctypes.c_char_p,
            ctypes.c_char_p,
            ctypes.c_char_p,
            ctypes.c_char_p
        ];
        self.lib.tui_apply_frame.restype = ctypes.c_int64;
        self.lib.tui_apply_frame.argtypes = [ctypes.c_char_p];
        self.lib.tui_wait_key.restype = ctypes.c_int64;
        self.lib.tui_wait_key.argtypes = [ctypes.c_int64];
        self.lib.tui_handle_key.restype = ctypes.c_int64;
        self.lib.tui_handle_key.argtypes = [];
        self.lib.tui_next_command.restype = ctypes.c_char_p;
        self.lib.tui_next_command.argtypes = [];
        self.lib.tui_quit_requested.restype = ctypes.c_int64;
        self.lib.tui_quit_requested.argtypes = [];
        self.lib.tui_render.restype = ctypes.c_int64;
        self.lib.tui_render.argtypes = [];
        self.lib.tui_shutdown.restype = ctypes.c_int64;
        self.lib.tui_shutdown.argtypes = [];
    }

    def start(project: str, files_env: str, presets_env: str, tty_dev: str) -> int {
        return int(
            self.lib.tui_init(
                project.encode("utf-8"),
                files_env.encode("utf-8"),
                presets_env.encode("utf-8"),
                tty_dev.encode("utf-8")
            )
        );
    }

    def apply_frame(blob: str) -> int {
        return int(self.lib.tui_apply_frame(blob.encode("utf-8")));
    }

    def wait_key(timeout_ms: int) -> int {
        # Lock-free: the GIL is released for the native poll(2). Returns 1 if a
        # key is ready, 0 on timeout.
        return int(self.lib.tui_wait_key(int(timeout_ms)));
    }

    def handle_key -> int {
        # MUTATES native TuiState; caller must hold the render lock. Returns 1 if
        # the key requested quit.
        return int(self.lib.tui_handle_key());
    }

    def next_command -> str {
        # Drain one queued command (FIFO), "" when empty. c_char_p returns bytes.
        raw = self.lib.tui_next_command();
        if raw is None {
            return "";
        }
        return raw.decode("utf-8", "replace");
    }

    def quit_requested -> int {
        return int(self.lib.tui_quit_requested());
    }

    def render -> int {
        # Paints to the native-owned tty fd (NOT fd 1). Caller holds the lock.
        return int(self.lib.tui_render());
    }

    def shutdown -> int {
        return int(self.lib.tui_shutdown());
    }
}


def _tui_lib_path(pkg_root: any) -> str {
    return str(pkg_root / "ai_tui_na" / "bin" / "libtui.so");
}


def _ensure_tui_lib(pkg_root: any) -> dict {
    # Mirror of run_tui_session's _ensure_tui_binary, for libtui.so. Compile on
    # first launch when NA sources are present (dev tree); installed packages ship
    # a prebuilt .so. JAC_AI_TUI_REBUILD=1 forces a recompile. build.sh (even with
    # --quick) builds both jac-na-tui and libtui.so, so the same invocation works.
    import os;
    import subprocess;
    import from jaclang.cli.console { console }

    lib = _tui_lib_path(pkg_root);
    exists = os.path.exists(lib);
    force = os.environ.get("JAC_AI_TUI_REBUILD", "").strip().lower() in (
        "1",
        "true",
        "yes",
        "on"
    );
    if exists and not force {
        return {"ok": True, "error": "", "hint": ""};
    }
    na_dir = str(pkg_root / "ai_tui_na");
    host_src = str(pkg_root / "ai_tui_na" / "host.na.jac");
    build_sh = str(pkg_root / "ai_tui_na" / "build.sh");
    if not os.path.isfile(host_src) or not os.path.isfile(build_sh) {
        # No sources to (re)build from. Use a prebuilt .so if present (installed
        # package); only fail when there is nothing to load.
        if exists {
            return {"ok": True, "error": "", "hint": ""};
        }
        return {
            "ok": False,
            "error": f"libtui.so not found at {lib}",
            "hint": "Build it with: jac-super/jac_super/ai_tui_na/build.sh --quick",

        };
    }
    if force and exists {
        console.print(
            "[tui] JAC_AI_TUI_REBUILD set; recompiling libtui.so ...", style="dim"
        );
    } else {
        console.print(
            "[tui] libtui.so missing; compiling (first run) ...", style="dim"
        );
    }
    try {
        res = subprocess.run(
            ["bash", build_sh, "--quick"],
            cwd=na_dir,
            capture_output=True,
            text=True,
            timeout=300,
        );
        if res.returncode != 0 {
            detail = (res.stderr or res.stdout or "").strip();
            if detail {
                console.error(detail);
            }
            return {
                "ok": False,
                "error": "libtui.so compile failed",
                "hint": f"Run manually: {build_sh} --quick",

            };
        }
    } except Exception as e {
        return {
            "ok": False,
            "error": f"libtui.so compile failed: {e}",
            "hint": f"Run manually: {build_sh} --quick",

        };
    }
    if not os.path.exists(lib) {
        return {
            "ok": False,
            "error": f"libtui.so not found at {lib} after compile",
            "hint": f"Run manually: {build_sh} --quick",

        };
    }
    return {"ok": True, "error": "", "hint": ""};
}
