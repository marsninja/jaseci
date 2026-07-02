import from jaclang.cli.console { console }
import from jaclang.cli.guide_store { list_guides as gs_list }

def _hc_help(arg: str) -> bool {
    agent.view.print_help();
    return False;
}

def _hc_clear(arg: str) -> bool {
    reset_session();
    console.success("Conversation cleared.");
    return False;
}

def _hc_guides(arg: str) -> bool {
    for g in gs_list() {
        console.print(f"  {g.name}", style="bold");
        console.print(f"      {g.description}", style="muted");
    }
    return False;
}

def _hc_stats(arg: str) -> bool {
    agent.cfg.show_stats = not agent.cfg.show_stats;
    console.success("Turn stats on." if agent.cfg.show_stats else "Turn stats off.");
    return False;
}

def _hc_verbose(arg: str) -> bool {
    agent.cfg.verbose = not agent.cfg.verbose;
    console.success(
        "Verbose: streaming reasoning, timings, and step detail."
            if agent.cfg.verbose
            else "Quiet: tool calls and the answer only."
    );
    return False;
}

def _hc_feedback(arg: str) -> bool {
    agent.cfg.inline_feedback = not agent.cfg.inline_feedback;
    console.success(
        "Inline compiler feedback on: writes report errors they introduce."
            if agent.cfg.inline_feedback
            else "Inline compiler feedback off: use jac_check to compile."
    );
    return False;
}

def _hc_exit(arg: str) -> bool {
    return True;
}

def _host_cmds -> list[HostCmd] {
    return [
        HostCmd(["/help"], "/help", "show this help", False, _hc_help),
        HostCmd(["/clear"], "/clear", "reset the conversation", False, _hc_clear),
        HostCmd(
            ["/guides"],
            "/guides",
            "list the bundled Jac reference guides",
            False,
            _hc_guides
        ),
        HostCmd(
            ["/stats"], "/stats", "toggle the per-turn stat line", False, _hc_stats
        ),
        HostCmd(
            ["/verbose"],
            "/verbose",
            "toggle live reasoning, timings, and step detail",
            False,
            _hc_verbose
        ),
        HostCmd(
            ["/feedback"],
            "/feedback",
            "toggle inline compiler feedback after each write",
            False,
            _hc_feedback
        ),
        HostCmd(["/exit", "/quit"], "/exit", "quit", False, _hc_exit),

    ];
}

def _lookup_host_cmd(name: str) -> HostCmd | None {
    for c in _host_cmds() {
        if name in c.names {
            return c;
        }
    }
    return None;
}
