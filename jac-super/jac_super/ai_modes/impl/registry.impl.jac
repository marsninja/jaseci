"""Implementation of AI mode registry."""

impl AiModeRegistry.register(mode_type: AiModeType, mode: AiMode) -> None {
    self._modes[mode_type] = mode;
}

impl AiModeRegistry.get(mode_type: AiModeType) -> AiMode | None {
    return self._modes.get(mode_type);
}

impl AiModeRegistry.select(req: object) -> AiMode {
    r: any = req;
    if bool(r?.ui) and bool(r?.tui) {
        raise ValueError("`jac ai`: `--ui` and `--tui` are mutually exclusive.");
    }
    mode_ty = AiModeType.PLAIN;
    if bool(r?.ui) {
        mode_ty = AiModeType.WEB;
    } elif bool(r?.tui) {
        mode_ty = AiModeType.TUI;
    }
    mode = self.get(mode_ty);
    if mode is None {
        raise ValueError(f"No AI mode registered for '{mode_ty.value}'.");
    }
    return mode;
}

impl AiModeRegistry.clear -> None {
    self._modes = {};
}
