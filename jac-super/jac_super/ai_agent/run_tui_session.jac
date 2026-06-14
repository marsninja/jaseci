"""TUI session entry point for `jac ai --tui`.

Runs the in-process Textual renderer (`jac_super.ai_tui`) against the agent
backend's `ui_*` API. No external server or client process is spawned.
"""

def run_tui_session(req: object) -> int;
