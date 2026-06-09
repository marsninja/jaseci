"""Plain terminal mode adapter implementation."""

impl PlainMode.run(req: object) -> int {
    import from jaclang.cli.ai_agent { run_agent }
    return run_agent(req);
}
