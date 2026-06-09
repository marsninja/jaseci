"""Agent API server for the Ink TUI.

Re-exports the HTTP endpoints from `jaclang.cli.ai_ui.server` so `jac start`
discovers them as POST /function/<name> routes. The imported server module runs
`ui_configure()` in its entry block, which boots the agent using env vars set by
the launcher.
"""
import from jaclang.cli.ai_ui.server {
    agent_poll,
    agent_send,
    agent_reset,
    agent_stop,
    agent_settings,
    agent_apply_settings,
    agent_stream,
    agent_graph,
    agent_call_detail,
    agent_phase_context
}
import from extras {
    agent_runtime_config,
    agent_apply_mode,
    agent_toggle_verbose,
    agent_toggle_feedback,
    agent_toggle_stats,
    agent_guides,
    agent_mcp_status
}
