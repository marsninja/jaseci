"""Terminal UI mode adapter."""

import from jac_super.ai_modes.registry { AiMode }

class TuiMode(AiMode) {
    override def run(req: object) -> int;
}
