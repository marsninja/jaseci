"""Implementation of transform commands.

These implementations delegate to the existing CLI implementation functions.
"""

import sys;

"""Convert Python to Jac."""
impl py2jac(filename: str) -> int {
    import from jaclang.cli.cli { py2jac as cli_py2jac }
    try {
        cli_py2jac(filename=filename);
        return 0;
    } except SystemExit as e {
        return e.code if isinstance(e.code, int) else 1;
    } except Exception as e {
        print(f"Error: {e}", file=sys.stderr);
        return 1;
    }
}

"""Convert Jac to Python."""
impl jac2py(filename: str) -> int {
    import from jaclang.cli.cli { jac2py as cli_jac2py }
    try {
        cli_jac2py(filename=filename);
        return 0;
    } except SystemExit as e {
        return e.code if isinstance(e.code, int) else 1;
    } except Exception as e {
        print(f"Error: {e}", file=sys.stderr);
        return 1;
    }
}

"""Convert Jac to JavaScript."""
impl js(filename: str) -> int {
    import from jaclang.cli.cli { js as cli_js }
    try {
        cli_js(filename=filename);
        return 0;
    } except SystemExit as e {
        return e.code if isinstance(e.code, int) else 1;
    } except Exception as e {
        print(f"Error: {e}", file=sys.stderr);
        return 1;
    }
}
