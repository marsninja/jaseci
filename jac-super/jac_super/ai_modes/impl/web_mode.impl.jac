"""Web UI mode adapter implementation."""

impl WebMode.run(req: object) -> int {
    import from jaclang.cli.ai_agent { _run_ui_server }
    r: any = req;
    return _run_ui_server(r);
}
