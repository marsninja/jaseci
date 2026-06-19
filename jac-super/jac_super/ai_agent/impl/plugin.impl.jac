"""`run_ai_agent` hook: dispatches `jac ai --tui` to an NA TUI backend.

Backend selection (PLAN-tui-in-process §12/§15-D). `JAC_AI_TUI_BACKEND` picks the
renderer transport:
  - unset / `inprocess` (default) -- load `libtui.so` via ctypes and drive it
    in-process (run_tui_in_process). One process, no sidecar spawn latency.
  - `subprocess` -- spawn the `jac-na-tui` sidecar over pipes (run_tui_session).
    Crash-isolated fallback if the in-process renderer regresses.
"""

impl JacSuperAiPlugin.run_ai_agent(req: object) -> int | None {
    import os;

    r: any = req;
    if bool(r?.tui) {
        backend = os.environ.get("JAC_AI_TUI_BACKEND", "").strip().lower();
        if backend == "subprocess" {
            import sys;
            if sys.platform == "win32" {
                import from jaclang.cli.console { console }
                console.error(
                    "JAC_AI_TUI_BACKEND=subprocess is not supported on Windows "
                    "(IPC stdio remap is not yet wired). "
                    "Unset JAC_AI_TUI_BACKEND to use the default in-process backend."
                );
                return 1;
            }
            import from jac_super.ai_agent.run_tui_session { run_tui_session }
            return run_tui_session(req);
        }
        import from jac_super.ai_agent.run_tui_in_process { run_tui_in_process }
        return run_tui_in_process(req);
    }
    return None;
}
