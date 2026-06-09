"""AI mode registry for `jac ai` launch adapters."""

enum AiModeType { PLAIN = "plain", WEB = "web", TUI = "tui" }

class AiMode {
    def run(req: object) -> int abs;
}

obj AiModeRegistry {
    has _modes: dict[AiModeType, AiMode] = {};

    def register(mode_type: AiModeType, mode: AiMode) -> None;
    def get(mode_type: AiModeType) -> AiMode | None;
    def select(req: object) -> AiMode;
    def clear -> None;
}

glob _registry: AiModeRegistry | None = None;

def get_ai_mode_registry -> AiModeRegistry {
    global _registry;
    if _registry is None {
        _registry = AiModeRegistry();
    }
    return _registry;
}
