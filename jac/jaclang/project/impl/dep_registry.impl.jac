"""Implementation of dependency type registry."""

# ===============================================================================
# DependencyRegistry Implementation
# ===============================================================================
"""Register a new dependency type from plugin hook data."""
impl DependencyRegistry.register(dep_type_info: dict[str, Any]) -> None {
    import from jaclang.project.dep_registry { DependencyType }
    name = dep_type_info.get("name");
    if not name {
        raise ValueError("Dependency type must have a 'name' field");
    }
    # Create DependencyType from the dict
    dep_type = DependencyType(
        name=name,
        dev_name=dep_type_info.get("dev_name", f"{name}.dev"),
        cli_flag=dep_type_info.get("cli_flag", ""),
        install_dir=dep_type_info.get("install_dir", ""),
        install_handler=dep_type_info.get("install_handler"),
        remove_handler=dep_type_info.get("remove_handler"),
        install_all_handler=dep_type_info.get("install_all_handler")
    );
    # Validate required handlers
    if dep_type.install_handler is None {
        raise ValueError(f"Dependency type '{name}' must have an 'install_handler'");
    }
    if dep_type.remove_handler is None {
        raise ValueError(f"Dependency type '{name}' must have a 'remove_handler'");
    }
    # Register the type
    self._types[name] = dep_type;
    # Map CLI flag to type name
    if dep_type.cli_flag {
        self._flag_map[dep_type.cli_flag] = name;
    }
}

"""Get dependency type by name (e.g., 'npm')."""
impl DependencyRegistry.get_by_name(name: str) -> DependencyType | None {
    import from jaclang.project.dep_registry { DependencyType }
    return self._types.get(name);
}

"""Get dependency type by CLI flag (e.g., '--cl')."""
impl DependencyRegistry.get_by_flag(flag: str) -> DependencyType | None {
    import from jaclang.project.dep_registry { DependencyType }
    type_name = self._flag_map.get(flag);
    if type_name {
        return self._types.get(type_name);
    }
    return None;
}

"""Get all registered dependency types."""
impl DependencyRegistry.get_all -> dict[str, DependencyType] {
    import from jaclang.project.dep_registry { DependencyType }
    return self._types.copy();
}

"""Get all registered CLI flags."""
impl DependencyRegistry.get_all_flags -> list[str] {
    return list(self._flag_map.keys());
}

"""Check if a dependency type is registered."""
impl DependencyRegistry.has_type(name: str) -> bool {
    return name in self._types;
}

"""Clear all registered types (for testing)."""
impl DependencyRegistry.clear -> None {
    self._types.clear();
    self._flag_map.clear();
}

# ===============================================================================
# Module-level Functions Implementation
# ===============================================================================
"""Get or create the global dependency registry (auto-initializes on first access)."""
impl get_dependency_registry -> DependencyRegistry {
    import from jaclang.project.dep_registry { DependencyRegistry }
    global _registry;
    if _registry is None {
        reg = DependencyRegistry();
        _registry = reg;
    } else {
        reg = _registry;
    }
    if not reg._initialized {
        reg._initialized = True;
        _auto_initialize_dep_registry(reg);
    }
    return reg;
}

"""Auto-initialize the dependency registry by calling plugin hooks."""
def _auto_initialize_dep_registry(registry: object) -> None {
    try {
        import from jaclang.jac0core.runtime { JacRuntime }
        results = JacRuntime.register_dependency_type();
        if results is None {
            return;
        }
        if isinstance(results, dict) {
            registry.register(results);
        } elif isinstance(results, list) {
            for result in results {
                if result and isinstance(result, dict) {
                    registry.register(result);
                }
            }
        }
    } except Exception { }
}

"""Initialize the registry by calling plugin hooks.

Kept for backwards compatibility — get_dependency_registry() now auto-initializes.
"""
impl initialize_dependency_registry -> None {
    get_dependency_registry();
}
