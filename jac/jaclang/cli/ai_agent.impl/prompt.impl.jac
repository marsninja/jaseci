import from jaclang.cli.guide_store { list_guides as gs_list }

impl system_prompt -> str {
    index_lines: list[str] = [];
    for g in gs_list() {
        index_lines.append(f"- {g.name}: {g.description}");
    }
    guide_index = "\n".join(index_lines);
    return (
        AGENT_RULES + "\n## Reference guides available (open one with read_guide)\n\n" + guide_index
    );
}

impl reset_session{
    agent.ledger = Ledger();
}

impl Prompt.for_phase(state_ty: type, objective: str, ledger: Ledger) -> str {
    role = str(state_ty?._jac_semstr or "");
    return (
        system_prompt() + "\n\n## Current state\n\nYou are in " + role + "\n\n## Objective\n\n" + objective + "\n\n## Progress so far (shared across states)\n\n" + ledger.render()
    );
}
