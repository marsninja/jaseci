"""Web UI mode adapter."""

import from jac_super.ai_modes.registry { AiMode }

class WebMode(AiMode) {
    override def run(req: object) -> int;
}
