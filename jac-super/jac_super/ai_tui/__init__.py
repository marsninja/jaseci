"""In-process Textual TUI for ``jac ai --tui``.

Replaces the former Node/Ink frontend + HTTP sidecar. The agent backend
(``jaclang.cli.ai_agent``) exposes a complete in-process Python API
(``ui_send`` / ``ui_stream`` / ``ui_poll`` / ...), so the renderer runs in the
same process and subscribes to the agent's event bus directly -- no server, no
SSE, no Node, no npm, no compile step.
"""

__all__ = ["run_app"]


def run_app(initial_prompt: str = "") -> int:
    """Construct and run the Textual app; return its process exit code."""
    from jac_super.ai_tui.app import run_app as _run_app

    return _run_app(initial_prompt=initial_prompt)
