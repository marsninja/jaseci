"""Implementation of execution commands.

These implementations delegate to the existing CLI implementation functions.
"""

import sys;

"""Run the specified .jac, .jir, or .py file."""
impl run(
    filename: str, session: str = "", main: bool = True, cache: bool = True
) -> int {
    import from jaclang.cli.cli { run as cli_run }
    try {
        cli_run(filename=filename, session=session, main=main, cache=cache);
        return 0;
    } except SystemExit as e {
        return e.code if isinstance(e.code, int) else 1;
    } except Exception as e {
        print(f"Error: {e}", file=sys.stderr);
        return 1;
    }
}

"""Run the specified entrypoint function in the given .jac file."""
impl enter(
    filename: str,
    entrypoint: str,
    args: list = [],
    session: str = "",
    main: bool = True,
    <>root: str = "",
    <>node: str = ""
) -> int {
    import from jaclang.cli.cli { enter as cli_enter }
    try {
        cli_enter(
            filename=filename,
            entrypoint=entrypoint,
            args=args,
            session=session,
            main=main,
            <>root=<>root,
            <>node=<>node
        );
        return 0;
    } except SystemExit as e {
        return e.code if isinstance(e.code, int) else 1;
    } except Exception as e {
        print(f"Error: {e}", file=sys.stderr);
        return 1;
    }
}

"""Start REST API server."""
impl serve(
    filename: str,
    session: str = "",
    port: int = 8000,
    main: bool = True,
    faux: bool = False
) -> int {
    import from jaclang.cli.cli { serve as cli_serve }
    try {
        cli_serve(filename=filename, session=session, port=port, main=main, faux=faux);
        return 0;
    } except SystemExit as e {
        return e.code if isinstance(e.code, int) else 1;
    } except Exception as e {
        print(f"Error: {e}", file=sys.stderr);
        return 1;
    }
}

"""Debug a Jac program using Python debugger."""
impl debug(filename: str, main: bool = True, cache: bool = False) -> int {
    import from jaclang.cli.cli { debug as cli_debug }
    try {
        cli_debug(filename=filename, main=main, cache=cache);
        return 0;
    } except SystemExit as e {
        return e.code if isinstance(e.code, int) else 1;
    } except Exception as e {
        print(f"Error: {e}", file=sys.stderr);
        return 1;
    }
}
