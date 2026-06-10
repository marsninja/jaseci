"""Jac Super AI plugin -- `jac ai --tui` handoff via `run_ai_agent` hook.

Intercepts `--tui` before the core byLLM agent runs. Non-TUI requests
return None so the default `run_ai_agent` hook implementation handles them.
"""
import from jaclang.jac0core.runtime { hookimpl, plugin_manager }

class JacSuperAiPlugin {
    @hookimpl
    static def run_ai_agent(req: object) -> int;
}

with entry {
    plugin_manager.register(JacSuperAiPlugin());
}
