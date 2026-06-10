"""`run_ai_agent` hook: hand off `--tui` to the Ink launcher."""

impl JacSuperAiPlugin.run_ai_agent(req: object) -> int {
    r: any = req;
    if not bool(r?.tui) {
        return None;
    }
    import from jac_super.ai_agent.run_tui_session { run_tui_session }
    return run_tui_session(r);
}
