"""Plain terminal mode adapter."""

import from jac_super.ai_modes.registry { AiMode }

class PlainMode(AiMode) {
    override def run(req: object) -> int;
}
