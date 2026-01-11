"""Start the command line interface.

Uses the new registry infrastructure for command registration,
help formatting, and execution with plugin hook support.
"""

import os;
import pickle;
import sys;
import from importlib.metadata { version as pkg_version }
import from pathlib { Path }

glob _runtime_initialized = False;

impl start_cli -> None {
    import from jaclang.pycore.runtime { JacRuntime as Jac }
    import from jaclang.cli.registry { get_registry }
    import from jaclang.cli.executor { get_executor }
    import from jaclang.cli.help { get_help_formatter }
    # Auto-discover and load jac.toml project configuration
    _load_project_config();
    # Load plugins which may register additional commands
    Jac.create_cmd();
    # Get the registry and finalize it (builds argparse parser)
    registry = get_registry();
    parser = registry.finalize();
    # Handle implicit 'run' command for .jac files
    raw_argv = sys.argv[1:];
    if (
        raw_argv
        and not raw_argv[0].startswith('-')
        and raw_argv[0].lower().endswith(('.jac', '.jir', '.py'))
    ) {
        sys.argv = [sys.argv[0], 'run'] + raw_argv;
    }
    # Parse arguments
    args = parser.parse_args();
    # Handle --version flag
    if args.version {
        print(f"Jac version {pkg_version('jaclang')}");
        print('Jac path:', __file__);
        return;
    }
    # Handle no command specified
    if (args.command is None) {
        # Display custom help with grouped commands
        formatter = get_help_formatter();
        help_text = formatter.format_main_help(
            registry.get_all(), prog="jac", version=pkg_version('jaclang')
        );
        print(help_text);
        return;
    }
    # Get the command specification
    command_spec = registry.get(args.command);
    if not command_spec {
        print(f"Unknown command: {args.command}", file=sys.stderr);
        parser.print_help();
        return;
    }
    # Prepare arguments for execution
    args_dict = vars(args);
    args_dict.pop('command');
    args_dict.pop('version', None);
    # Apply environment profile if specified
    _apply_env_profile(args_dict);
    # Execute using the new executor with hook support
    executor = get_executor();
    result = executor.execute(command_spec, args_dict);
    # Exit with the command's return code
    if result.error {
        print(f"Error: {result.error}", file=sys.stderr);
    }
    if result.return_code != 0 {
        sys.exit(result.return_code);
    }
}

"""Load project configuration from jac.toml if present."""
def _load_project_config -> None {
    try {
        import from jaclang.project.config { get_config, set_config }
        import from jaclang.project.dependencies { add_packages_to_path }

        # Auto-discover jac.toml
        config = get_config();
        if config is not None {
            # Add packages/ directory to Python path
            add_packages_to_path(config);
        }

        # Initialize plugin-registered dependency types
        _initialize_dependency_registry();
    } except Exception {
        # Silently ignore if project module not available or config discovery fails
        pass;
    }
}

"""Initialize the dependency registry from plugin hooks."""
def _initialize_dependency_registry -> None {
    try {
        import from jaclang.project.dep_registry { initialize_dependency_registry }
        initialize_dependency_registry();
    } except Exception {
        # Silently ignore if registry initialization fails
        pass;
    }
}

"""Apply environment profile from --env flag or JAC_ENV environment variable."""
def _apply_env_profile(args_dict: dict) -> None {
    try {
        import from jaclang.project.config { get_config }

        config = get_config();
        if config is None {
            return;
        }

        # Check for --env argument or JAC_ENV environment variable
        profile = args_dict.pop('env', None);
        if profile is None {
            profile = os.environ.get('JAC_ENV');
        }
        if profile is None and config.environment.default_profile {
            profile = config.environment.default_profile;
        }

        if profile {
            config.apply_profile(profile);
        }
    } except Exception {
        # Silently ignore profile loading errors
        pass;
    }
}

"""Initialize Jac runtime once on first use."""
impl _ensure_jac_runtime -> None {
    global _runtime_initialized;
    if not _runtime_initialized {
        import from jaclang.pycore.runtime { JacRuntime as Jac }
        Jac.setup();
        _runtime_initialized = True;
    }
}

"""Create JacRuntime and return the base path, module name, and runtime state."""
impl proc_file_sess(filename: str, session: str, <>root: (str | None) = None) -> tuple {
    import from jaclang.pycore.runtime { JacRuntime as Jac }
    import from jaclang.pycore.runtime { JacUtils }
    (base, mod) = os.path.split(filename);
    base = base or './';
    if (filename.endswith('.jac') or filename.endswith('.jir')) {
        mod = mod[:-4];
    } elif filename.endswith('.py') {
        mod = mod[:-3];
    } else {
        print(
            'Not a valid file!\nOnly supports `.jac`, `.jir`, and `.py`',
            file=sys.stderr
        );
        <>exit(1);
    }
    mach = Jac.create_j_context(session=session, <>root=<>root);
    Jac.set_context(mach);
    return (base, mod, mach);
}

"""Get an object by ID from a Jac program (utility for debugging/testing).

Args:
    filename: Path to the .jac or .jir file
    id: Object ID to retrieve
    session: Optional session identifier
    main: Treat the module as __main__ (default: True)

Returns:
    Dictionary containing the object's state
"""
impl get_object(filename: str, id: str, session: str = '', main: bool = True) -> dict {
    _ensure_jac_runtime();
    import from jaclang.pycore.runtime { JacRuntime as Jac }
    (base, mod, mach) = proc_file_sess(filename, session);
    if filename.endswith('.jac') {
        Jac.jac_import(
            target=mod, base_path=base, override_name='__main__' if main else None
        );
    } elif filename.endswith('.jir') {
        with open(filename, 'rb') as f {
            Jac.attach_program(pickle.load(f));
            Jac.jac_import(
                target=mod, base_path=base, override_name='__main__' if main else None
            );
        }
    } else {
        mach.close();
        raise ValueError('Not a valid file!\nOnly supports `.jac` and `.jir`') ;
    }
    <>obj = Jac.get_object(id);
    if <>obj {
        data = <>obj.__jac__.__getstate__();
    } else {
        print(f"Object with id {id} not found.", file=sys.stderr);
        mach.close();
        <>exit(1);
    }
    mach.close();
    return data;
}

"""Start REST API server (delegated to execution.serve).

This is kept for backward compatibility with tests that use cli.serve().
"""
impl serve(
    filename: str,
    session: str = '',
    port: int = 8000,
    main: bool = True,
    faux: bool = False
) -> None {
    _ensure_jac_runtime();
    import from jaclang.pycore.runtime { JacRuntime as Jac }
    # Compute session_path BEFORE proc_file_sess so context has proper persistence
    (base, mod) = os.path.split(filename);
    base = base or os.getcwd();
    if (filename.endswith('.jac') or filename.endswith('.jir')) {
        mod = mod[:-4];
    } elif filename.endswith('.py') {
        mod = mod[:-3];
    }
    # Use .jac/data/ directory for session files (runtime artifacts)
    data_dir = os.path.join(base, ".jac", "data");
    os.makedirs(data_dir, exist_ok=True);
    session_path = session or os.path.join(data_dir, f"{mod}.session");
    # Now call proc_file_sess with the computed session_path
    (base, mod, mach) = proc_file_sess(filename, session_path);
    lng = filename.split('.')[-1];
    Jac.set_base_path(base);
    try {
        if filename.endswith(('.jac', '.py')) {
            Jac.jac_import(target=mod, base_path=base, lng=lng);
        } elif filename.endswith('.jir') {
            with open(filename, 'rb') as f {
                Jac.attach_program(pickle.load(f));
                Jac.jac_import(target=mod, base_path=base, lng=lng);
            }
        }
        if Jac.program.errors_had {
            for error in Jac.program.errors_had {
                print(f"Error: {error}", file=sys.stderr);
            }
            mach.close();
            <>exit(1);
        }
    } except Exception as e {
        print(f"Error loading {filename}: {e}", file=sys.stderr);
        mach.close();
        <>exit(1);
    }
    # Get server class from plugin hook (allows jac-scale to provide enhanced server)
    ServerClass = Jac.get_api_server_class();
    server = ServerClass(
        module_name=mod, session_path=session_path, port=port, base_path=base
    );
    if faux {
        try {
            server.print_endpoint_docs();
            mach.close();
            return;
        } except Exception as e {
            print(f"Error generating endpoint documentation: {e}", file=sys.stderr);
            mach.close();
            <>exit(1);
        }
    }
    try {
        server.start();
    } except KeyboardInterrupt {
        print('\nServer stopped.');
        mach.close();
    } except Exception as e {
        print(f"Server error: {e}", file=sys.stderr);
        mach.close();
        <>exit(1);
    }
}
