import os;
import from jaclang.cli.console { console }
import from jaclang.compiler.code_intel { CodeIntelligence }


obj AgentRequest {
    has prompt: str = "",
        model: str = "",
        n_ctx: int = 0,
        safe: bool = False,
        quiet: bool = False,
        ui: bool = False,
        tui: bool = False,
        cwd: str = "",
        code_intel: CodeIntelligence | None = None,
        resume: str = "",
        continue_last: bool = False,
        session_name: str = "";
}


def build_agent_request(
    prompt: str = "",
    model: str = "",
    n_ctx: int = 0,
    safe: bool = False,
    quiet: bool = False,
    ui: bool = False,
    tui: bool = False,
    resume: str = "",
    continue_last: bool = False,
    session_name: str = ""
) -> AgentRequest {
    cwd = os.getcwd();
    return AgentRequest(
        prompt=prompt,
        model=model,
        n_ctx=n_ctx,
        safe=safe,
        quiet=quiet,
        ui=ui,
        tui=tui,
        cwd=cwd,
        code_intel=CodeIntelligence(proj_dir=cwd, lazy=True),
        resume=resume,
        continue_last=continue_last,
        session_name=session_name
    );
}


def validate_agent_request(req: AgentRequest) -> int {
    if req.ui and req.tui {
        console.error("`jac ai`: `--ui` and `--tui` are mutually exclusive.");
        return 1;
    }
    return 0;
}
