"""Launch the self-hosting embed TUI host for `jac ai --tui`.

The single `--tui` backend. `jac-ai-tui` (compiled from `ai_tui_na/host_embed.na.jac`)
IS the host: the renderer is linked Jac and the agent runs in an embedded CPython
that `libjacpyembed` brings up. This module locates (and on a dev tree compiles)
that binary, exports the env contract it reads (JAC_AI_UI_* + the byLLM runtime
seams + JAC_RT_DIR when we ourselves run fused), then `execve`s it so the host
owns the controlling terminal with no relay layer.

Replaces the retired in-process (`libtui.so` via ctypes) and subprocess
(`jac-na-tui` sidecar) backends: both ran the agent in the parent jac interpreter
with NA only as the renderer; the embed host runs the whole stack self-contained.
"""

import from jaclang.cli.agent_api { AgentRequest }

def run_tui_embed(req: AgentRequest) -> int;
