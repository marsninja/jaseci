"""In-process Textual launcher for `jac ai --tui`.

Configures the agent backend and runs the Textual renderer in this same
process. The renderer drives the agent through the in-process `ui_*` API and
subscribes to `agent.bus` directly, so there is no HTTP server, SSE transport,
Node runtime, npm install, or client compile step -- the whole former
server/Ink sidecar is gone.
"""
import os;
import from jaclang.cli.console { console }
import from jaclang.cli.ai_agent { ui_configure, ui_stop }
import from jac_super.ai_tui { run_app }

impl run_tui_session(req: object) -> int {
    r: any = req;
    project = os.path.normpath(str(r?.cwd or os.getcwd()));
    # The agent backend reads these in `ui_configure`. `JAC_AI_TUI=1` flips
    # `agent.cfg.tui_active`, which suppresses the agent's own terminal output so
    # it never prints underneath the Textual screen.
    os.environ["JAC_AI_UI_PROJECT"] = project;
    os.environ["JAC_AI_UI_MODEL"] = str(r?.model or "");
    os.environ["JAC_AI_UI_NCTX"] = str(int(r?.n_ctx or 0));
    os.environ["JAC_AI_TUI"] = "1";
    initial = str(r?.prompt or "").strip();
    try {
        console.print("");
        console.print(f"  project: {project}", style="muted");
        # Builds the model and turns on the event feed; failures here surface as
        # an error event in the TUI, not a launch failure.
        ui_configure();
        return int(run_app(initial_prompt=initial));
    } except KeyboardInterrupt {
        return 130;
    } except Exception as e {
        console.error(f"Failed to launch TUI: {e}");
        return 1;
    } finally {
        # Don't let a background turn outlive the UI.
        try {
            ui_stop();
        } except Exception { }
    }
}
