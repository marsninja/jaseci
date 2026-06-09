"""TUI mode adapter implementation."""

impl TuiMode.run(req: object) -> int {
    import from jac_super.ai_agent.run_tui_session { run_tui_session }
    return run_tui_session(req);
}
