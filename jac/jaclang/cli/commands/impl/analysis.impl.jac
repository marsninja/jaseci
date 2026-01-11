"""Implementation of analysis commands.

These implementations delegate to the existing CLI implementation functions.
"""

import sys;

"""Run type checker for specified .jac files."""
impl check(paths: list, print_errs: bool = True, warnonly: bool = False) -> int {
    import from jaclang.cli.cli { check as cli_check }
    try {
        cli_check(paths=paths, print_errs=print_errs, warnonly=warnonly);
        return 0;
    } except SystemExit as e {
        return e.code if isinstance(e.code, int) else 1;
    } except Exception as e {
        print(f"Error: {e}", file=sys.stderr);
        return 1;
    }
}

"""Build the specified .jac file."""
impl build(filename: str, typecheck: bool = False) -> int {
    import from jaclang.cli.cli { build as cli_build }
    try {
        cli_build(filename=filename, typecheck=typecheck);
        return 0;
    } except SystemExit as e {
        return e.code if isinstance(e.code, int) else 1;
    } except Exception as e {
        print(f"Error: {e}", file=sys.stderr);
        return 1;
    }
}

"""Format .jac files with improved code style."""
impl format(paths: list, to_screen: bool = False, fix: bool = False) -> int {
    import from jaclang.cli.cli { format as cli_format }
    try {
        cli_format(paths=paths, to_screen=to_screen, fix=fix);
        return 0;
    } except SystemExit as e {
        return e.code if isinstance(e.code, int) else 1;
    } except Exception as e {
        print(f"Error: {e}", file=sys.stderr);
        return 1;
    }
}

"""Run the test suite in the specified .jac file or directory."""
impl test(
    filepath: str = "",
    test_name: str = "",
    filter: str = "",
    xit: bool = False,
    maxfail: int = None,
    directory: str = "",
    verbose: bool = False
) -> int {
    import from jaclang.cli.cli { test as cli_test }
    try {
        cli_test(
            filepath=filepath,
            test_name=test_name,
            filter=filter,
            xit=xit,
            maxfail=maxfail,
            directory=directory,
            verbose=verbose
        );
        return 0;
    } except SystemExit as e {
        return e.code if isinstance(e.code, int) else 1;
    } except Exception as e {
        print(f"Error: {e}", file=sys.stderr);
        return 1;
    }
}

"""Generate static parser."""
impl gen_parser -> int {
    import from jaclang.cli.cli { gen_parser as cli_gen_parser }
    try {
        result = cli_gen_parser();
        print(result);
        return 0;
    } except SystemExit as e {
        return e.code if isinstance(e.code, int) else 1;
    } except Exception as e {
        print(f"Error: {e}", file=sys.stderr);
        return 1;
    }
}
