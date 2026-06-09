"""Register built-in `jac ai` modes."""

import from jac_super.ai_modes.registry { get_ai_mode_registry, AiModeType }
import from jac_super.ai_modes.plain_mode { PlainMode }
import from jac_super.ai_modes.web_mode { WebMode }
import from jac_super.ai_modes.tui_mode { TuiMode }

def register_modes {
    registry = get_ai_mode_registry();
    registry.register(AiModeType.PLAIN, PlainMode());
    registry.register(AiModeType.WEB, WebMode());
    registry.register(AiModeType.TUI, TuiMode());
}

with entry {
    register_modes();
}
