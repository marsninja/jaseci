"""Implementation of target registry."""

"""Register a new build target."""
impl TargetRegistry.register(target: ClientTarget) -> None {
    self._targets[target.name] = target;
}

"""Get a target by name."""
impl TargetRegistry.get(name: str) -> Optional[ClientTarget] {
    return self._targets.get(name);
}

"""Get all registered targets."""
impl TargetRegistry.get_all -> list[ClientTarget] {
    return list(self._targets.values());
}

"""Create a target by name string from the plugin registry."""
impl TargetFactory.create(name: str, project_dir: Path) -> ClientTarget {
    import from jaclang.runtimelib.client.targets.registry { get_target_registry }
    registry = get_target_registry();
    target_name = name.lower().strip();
    target = registry.get(target_name);
    if target is None {
        available = [t.name for t in registry.get_all()];
        raise ValueError(f"Unknown target: {name}. Available: {', '.join(available)}.");
    }
    target.project_dir = project_dir;
    return target;
}

"""Get list of available target names as strings."""
impl TargetFactory.get_available_target_names -> list[str] {
    import from jaclang.runtimelib.client.targets.registry { get_target_registry }
    registry = get_target_registry();
    return [target.name for target in registry.get_all()];
}
