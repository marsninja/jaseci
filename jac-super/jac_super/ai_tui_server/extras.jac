"""Extra agent API endpoints for the Ink TUI sidecar.

Config toggles and guides that are not part of ``ai_ui/server.jac`` but are
needed for slash-command parity with the plain REPL.
"""
import from jaclang.cli.ai_agent { agent }
import from jaclang.cli.guide_store { list_guides }

obj ActionResult {
    has ok: bool = True,
        message: str = "",
        error: str = "";
}

obj RuntimeConfigView {
    has yolo_mode: bool = False,
        verbose: bool = True,
        inline_feedback: bool = True,
        show_stats: bool = True,
        mode: str = "yolo";
}

obj GuideView {
    has name: str = "",
        description: str = "";
}

obj McpStatusView {
    has available: bool = False,
        message: str = "jac-mcp is not loaded in this session.";
}

"""Current agent display/config flags for the TUI."""
def:pub agent_runtime_config -> RuntimeConfigView {
    mode = "yolo" if agent.cfg.yolo_mode else "safe";
    return RuntimeConfigView(
        yolo_mode=agent.cfg.yolo_mode,
        verbose=agent.cfg.verbose,
        inline_feedback=agent.cfg.inline_feedback,
        show_stats=agent.cfg.show_stats,
        mode=mode
    );
}

"""Set safe (confirm writes) or yolo (auto-approve) mode."""
def:pub agent_apply_mode(mode: str) -> ActionResult {
    m = str(mode or "").strip().lower();
    if m == "yolo" {
        agent.cfg.yolo_mode = True;
        return ActionResult(ok=True, message="YOLO mode: writes run without confirm.");
    }
    if m == "safe" {
        agent.cfg.yolo_mode = False;
        return ActionResult(
            ok=True, message="Safe mode: confirms writes and shell commands."
        );
    }
    return ActionResult(ok=False, error="usage: /mode safe|yolo");
}

def:pub agent_toggle_verbose -> ActionResult {
    agent.cfg.verbose = not agent.cfg.verbose;
    if agent.cfg.verbose {
        return ActionResult(
            ok=True, message="Verbose: streaming reasoning, timings, and step detail."
        );
    }
    return ActionResult(ok=True, message="Quiet: tool calls and the answer only.");
}

def:pub agent_toggle_feedback -> ActionResult {
    agent.cfg.inline_feedback = not agent.cfg.inline_feedback;
    if agent.cfg.inline_feedback {
        return ActionResult(
            ok=True,
            message="Inline compiler feedback on: writes report errors they introduce."
        );
    }
    return ActionResult(
        ok=True, message="Inline compiler feedback off: use jac_check to compile."
    );
}

def:pub agent_toggle_stats -> ActionResult {
    agent.cfg.show_stats = not agent.cfg.show_stats;
    if agent.cfg.show_stats {
        return ActionResult(ok=True, message="Turn stats on.");
    }
    return ActionResult(ok=True, message="Turn stats off.");
}

def:pub agent_guides -> list[GuideView] {
    out: list[GuideView] = [];
    for g in list_guides() {
        out.append(GuideView(name=g.name, description=g.description));
    }
    return out;
}

def:pub agent_mcp_status -> McpStatusView {
    try {
        import from importlib.util { find_spec }
        if find_spec("jac_mcp") is not None {
            return McpStatusView(
                available=True,
                message="jac-mcp plugin is installed. Use `jac mcp` to manage servers."
            );
        }
    } except Exception { }
    return McpStatusView();
}
