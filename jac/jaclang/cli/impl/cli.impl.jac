"""Start the command line interface.

Uses the new registry infrastructure for command registration,
help formatting, and execution with plugin hook support.
"""

import os;
import sys;
import from importlib.metadata { version as pkg_version }
import from pathlib { Path }

impl start_cli -> None {
    import from jaclang.cli.registry { get_registry }
    import from jaclang.cli.executor { get_executor }
    import from jaclang.cli.help { get_help_formatter }
    import from jaclang.cli.console { console }
    # Auto-discover and load jac.toml project configuration
    _load_project_config();
    # Register plugin commands lazily from TOML metadata (no plugin imports).
    # Falls back to Jac.create_cmd() for plugins without command metadata.
    registry = get_registry();
    _register_lazy_plugin_commands(registry);
    # Finalize the registry (builds argparse parser)
    parser = registry.finalize();
    # Handle implicit 'run' command for .jac files
    # Scan past any leading flags (e.g. --autonative) to find a .jac/.py file
    raw_argv = sys.argv[1:];
    has_jac_file = any(
        not tok.startswith('-') and tok.lower().endswith(('.jac', '.py'))
        for tok in raw_argv
    );
    if has_jac_file and (not raw_argv or raw_argv[0] not in registry.commands) {
        sys.argv = [sys.argv[0], 'run'] + raw_argv;
    }
    # Extract script arguments before argparse parsing (Python-like behavior).
    # For commands with REMAINDER args, everything after the filename goes
    # to the script — no '--' separator needed.
    script_args = _extract_script_args(registry);
    # Parse arguments
    args = parser.parse_args();
    # Handle --version flag
    if args.version {
        import from jaclang.cli.banners { print_version_banner }
        print_version_banner(pkg_version('jaclang'));
        return;
    }
    # Handle no command specified
    if (args.command is None) {
        # Display custom help with grouped commands
        formatter = get_help_formatter();
        help_text = formatter.format_main_help(
            registry.get_all(), prog="jac", version=pkg_version('jaclang')
        );
        console.print(help_text);
        return;
    }
    # Get the command specification
    command_name = args.command;
    command_spec = registry.get(command_name);
    if not command_spec {
        console.error(f"Unknown command: {command_name}");
        parser.print_help();
        return;
    }
    # Prepare arguments for execution
    args_dict = vars(args);
    args_dict.pop('command');
    args_dict.pop('version', None);
    # Override REMAINDER args with the pre-extracted script arguments
    if script_args {
        args_dict['args'] = script_args;
    }
    _apply_profile(args_dict);
    # Before execution, load lazy plugins if needed for this command
    _ensure_plugins_for_command(command_name, args_dict, registry);
    # Re-fetch spec after potential lazy loading (may have been replaced)
    command_spec = registry.get(command_name);
    # Execute using the new executor with hook support
    executor = get_executor();
    result = executor.execute(command_spec, args_dict);
    # Exit with the command's return code
    if result.error {
        console.error(f"{result.error}");
    }
    if result.return_code != 0 {
        sys.exit(result.return_code);
    }
}

"""Extract script arguments before argparse parsing.

For commands with REMAINDER args (like 'run' and 'enter'), this mimics
Python's behavior: jac flags must come before the script filename, and
everything after the filename is passed to the script.

    jac run file.jac arg1 arg2        -> args = [arg1, arg2]
    jac run --no-cache file.jac arg1  -> args = [arg1]
    jac run file.jac -- --flag        -> args = [--flag]

Modifies sys.argv in-place so argparse only sees jac's own flags.
"""
def _extract_script_args(registry: object) -> list {
    import from jaclang.cli.command { ArgKind }

    raw = sys.argv[1:];
    if len(raw) < 2 {
        return [];
    }

    cmd_name = raw[0];
    spec = registry.get(cmd_name);
    if spec is None {
        return [];
    }

    # Only apply to commands with REMAINDER args
    all_args = spec.get_all_args();
    has_remainder = any(a.kind == ArgKind.REMAINDER for a in all_args);
    if not has_remainder {
        return [];
    }

    # Count expected positional args (excluding REMAINDER)
    n_positionals = sum(
        1
        for a in all_args
        if a.kind == ArgKind.POSITIONAL
    );

    # Build set of flags that consume a value argument
    value_flags: set = set();
    for arg in all_args {
        if arg.kind in (ArgKind.POSITIONAL, ArgKind.MULTI, ArgKind.REMAINDER) {
            continue;
        }
        if arg.kind == ArgKind.FLAG or arg.typ == bool {
            continue;
        }
        value_flags.add(f"--{arg.name}");
        if arg.short {
            value_flags.add(f"-{arg.short}");
        }
    }

    # Scan argv after command name
    i = 1;
    positionals_seen = 0;

    while i < len(raw) {
        token = raw[i];

        if token == '--' {
            # Explicit separator: everything after goes to script
            script_args = raw[i + 1:];
            sys.argv = [sys.argv[0]] + raw[:i];
            return script_args;
        }

        if token.startswith('-') {
            if token in value_flags {
                i += 2;
            } else {
                i += 1;
            }
        } else {
            positionals_seen += 1;
            if positionals_seen >= n_positionals {
                # Found the last expected positional (filename)
                # Everything after is for the script
                script_args = raw[i + 1:];
                # Strip leading '--' for backward compat with old separator syntax
                if script_args and script_args[0] == '--' {
                    script_args = script_args[1:];
                }
                sys.argv = [sys.argv[0]] + raw[:i + 1];
                return script_args;
            }
            i += 1;
        }
    }

    return [];
}

"""Load project configuration from jac.toml if present."""
def _load_project_config -> None {
    try {
        import from jaclang.project.config { get_config, set_config }
        import from jaclang.project.dependencies { add_venv_to_path }

        # Auto-discover jac.toml
        config = get_config();
        if config is not None {
            # Add venv site-packages to Python path
            add_venv_to_path(config);
        }
    } except Exception {
    # Silently ignore if project module not available or config discovery fails
    }
}

"""Resolve the active profile name and apply multi-file config overlay.

Profile priority: --profile flag > JAC_PROFILE > JAC_ENV (deprecated) > default_profile
"""
def _apply_profile(args_dict: dict) -> None {
    import from jaclang.cli.console { console }
    try {
        import from jaclang.project.config { get_config }

        config = get_config();
        if config is None {
            return;
        }

        # Determine profile name: --profile flag > JAC_PROFILE > JAC_ENV (deprecated) > default
        profile = args_dict.pop('profile', None);
        if not profile {
            profile = os.environ.get('JAC_PROFILE');
        }
        if not profile {
            jac_env = os.environ.get('JAC_ENV');
            if jac_env {
                console.print(
                    "Warning: JAC_ENV is deprecated, use JAC_PROFILE instead.",
                    style="warning"
                );
                profile = jac_env;
            }
        }
        if not profile and config.environment.default_profile {
            profile = config.environment.default_profile;
        }

        config.apply_profile_overlay(profile or None);

        # Bridge config values into args_dict when the CLI arg is at its
        # argparse default so that config file values take effect.
        # Only override when the config explicitly sets the value (in _raw_data
        # or via profile overlay) — otherwise leave the argparse default alone.
        _apply_config_defaults(config, args_dict);
    } except (KeyError, ValueError, OSError) as e {
        console.print(f"Warning: Failed to apply profile: {e}", style="warning");
    }
}

"""Apply config values to args_dict for keys still at their argparse defaults.

Maps config fields to CLI arg names with their argparse defaults.
Only overrides an arg if:
  1. The arg exists in args_dict (the command accepts it)
  2. The arg value equals the argparse default (user didn't explicitly pass it)
  3. The config has an explicitly-set value (from file or profile, not just the object default)
"""
def _apply_config_defaults(config: object, args_dict: dict) -> None {
    # (arg_name, argparse_default, config_value, raw_data_section, raw_data_key)
    bridges: list = [
        ("port", 8000, config.serve.port, "serve", "port"),
        ("cache", True, config.run.cache, "run", "cache"),
        ("main", True, config.run.main, "run", "main"),
        ("verbose", False, config.test.verbose, "test", "verbose"),
        ("autonative", False, config.run.autonative, "run", "autonative"),

    ];
    for (arg_name, arg_default, config_value, section, key) in bridges {
        if arg_name not in args_dict {
            continue;
        }
        if args_dict[arg_name] != arg_default {
            continue;  # User explicitly passed this arg
        }
        # Check if the config explicitly sets this value
        raw = config._raw_data.get(section, {});
        if isinstance(raw, dict) and key in raw {
            args_dict[arg_name] = config_value;
        }
    }
}

# =============================================================================
# Lazy Plugin Command Registration
# =============================================================================
"""Convert TOML arg metadata to Arg objects."""
def _toml_args_to_arg_list(args_data: list) -> list {
    import from jaclang.cli.command { Arg, ArgKind }
    result: list = [];
    type_map: dict = {"int": int, "float": float, "bool": bool, "str": str};
    kind_map: dict = {
        "positional": ArgKind.POSITIONAL,
        "flag": ArgKind.FLAG,
        "multi": ArgKind.MULTI,
        "remainder": ArgKind.REMAINDER,
        "option": ArgKind.OPTION
    };
    for a in args_data {
        kind = kind_map.get(a.get("kind", "option"), ArgKind.OPTION);
        typ = type_map.get(a.get("type", "str"), str);
        # For flags, always use bool type
        if kind == ArgKind.FLAG {
            typ = bool;
        }
        arg = Arg.create(
            name=a["name"],
            kind=kind,
            typ=typ,
            default=a.get("default"),
            help=a.get("help", ""),
            short=a.get("short"),
            choices=a.get("choices")
        );
        result.append(arg);
    }
    return result;
}

"""Register plugin commands and extensions from TOML metadata.

Reads [tool.jac.commands] and [tool.jac.extensions] from each plugin's
pyproject.toml manifest. Commands are registered as lazy stubs that load
the plugin only when actually invoked.

For plugins without command metadata, falls back to calling create_cmd
eagerly (backwards compatibility).
"""
def _register_lazy_plugin_commands(registry: object) -> None {
    import from jaclang { _jac_manifest }
    import importlib.metadata;

    # Collect which EPs have create_cmd (to find the EP to load for each dist)
    # Also track which dists have command metadata (for fallback detection)
    dists_with_cmd_metadata: set = set();
    eps_with_create_cmd: dict = {};  # dist_name -> ep_name that has create_cmd

    for (dist_name, manifest) in _jac_manifest.items() {
        hooks = manifest.get("hooks", {});
        for (ep_name, hook_csv) in hooks.items() {
            hook_names = [
                h.strip()
                for h in hook_csv.split(",")
                if h.strip()
            ];
            if "create_cmd" in hook_names {
                eps_with_create_cmd[dist_name] = ep_name;
            }
        }

        # Register new commands from [tool.jac.commands]
        commands = manifest.get("commands", {});
        if commands {
            dists_with_cmd_metadata.add(dist_name);
            ep_name = eps_with_create_cmd.get(dist_name, "");
            for (cmd_name, cmd_spec) in commands.items() {
                args = _toml_args_to_arg_list(cmd_spec.get("args", []));
                registry.register_lazy_command(
                    name=cmd_name,
                    help=cmd_spec.get("help", ""),
                    group=cmd_spec.get("group", "general"),
                    args=args,
                    ep_name=ep_name,
                    source=dist_name
                );
            }
        }

        # Register extensions from [tool.jac.extensions]
        extensions = manifest.get("extensions", {});
        if extensions {
            dists_with_cmd_metadata.add(dist_name);
            ep_name = eps_with_create_cmd.get(dist_name, "");
            for (cmd_name, ext_spec) in extensions.items() {
                args = _toml_args_to_arg_list(ext_spec.get("args", []));
                registry.register_lazy_extension(
                    command_name=cmd_name, args=args, ep_name=ep_name, source=dist_name
                );
            }
        }
    }

    # Fallback: for plugins that have create_cmd but NO command metadata,
    # load them eagerly (backwards compatibility for third-party plugins).
    for (dist_name, ep_name) in eps_with_create_cmd.items() {
        if dist_name not in dists_with_cmd_metadata {
            _load_plugin_ep(ep_name);
        }
    }
}

"""Load a plugin entry point by name and call its create_cmd."""
def _load_plugin_ep(ep_name: str) -> None {
    import importlib.metadata;
    import from jaclang.jac0core.runtime { plugin_manager }

    try {
        jac_eps = importlib.metadata.entry_points(group="jac");
    } except TypeError {
        jac_eps = importlib.metadata.entry_points().get("jac", []);
    }
    for ep in jac_eps {
        if ep.name == ep_name {
            try {
                plugin_class = ep.load();
                # Register with plugin manager if not already registered
                if ep.name not in plugin_manager._name2plugin {
                    plugin_manager.register(plugin_class, name=ep.name);
                }
                # Call create_cmd if available
                if hasattr(plugin_class, 'create_cmd') {
                    plugin_class.create_cmd();
                }
            } except Exception as e {
                import from jaclang.cli.console { console }
                console.print(f"Warning: Failed to load plugin '{ep_name}': {e}");
            }
            break;
        }
    }
}

"""Load lazy plugins needed for the given command before execution.

If the command itself is lazy, loads its plugin. Also checks if any
lazy extension flags are set and loads those plugins.
"""
def _ensure_plugins_for_command(
    command_name: str, args_dict: dict, registry: object
) -> None {
    loaded_eps: set = set();

    # 1. If the command itself is lazy, load its plugin
    spec = registry.get(command_name);
    if spec and spec._lazy and spec._lazy_ep_name {
        _load_plugin_ep(spec._lazy_ep_name);
        loaded_eps.add(spec._lazy_ep_name);
    }

    # 2. Check lazy extensions for this command
    lazy_exts = registry._lazy_extensions.get(command_name, []);
    for (ep_name, source, flag_names) in lazy_exts {
        if ep_name in loaded_eps {
            continue;
        }
        # Only load if one of the extension's flags is set (non-default value)
        should_load = False;
        for flag in flag_names {
            val = args_dict.get(flag);
            if val is not None and val is not False and val != "" {
                should_load = True;
                break;
            }
        }
        if should_load {
            _load_plugin_ep(ep_name);
            loaded_eps.add(ep_name);
        }
    }
}
