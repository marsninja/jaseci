"""Implementation of config commands.

These implementations delegate to the existing CLI implementation functions.
"""

import sys;

"""Manage Jac configuration."""
impl config(
    action: str = "show",
    key: str = "",
    value: str = "",
    group: str = "",
    output: str = "table"
) -> int {
    import from jaclang.cli.impl.cli { config as cli_config }
    try {
        cli_config(action=action, key=key, value=value, group=group, output=output);
        return 0;
    } except SystemExit as e {
        return e.code if isinstance(e.code, int) else 1;
    } except Exception as e {
        print(f"Error: {e}", file=sys.stderr);
        return 1;
    }
}

"""Manage Jac plugins."""
impl plugins(action: str = "list", names: list = [], verbose: bool = False) -> int {
    import from jaclang.cli.impl.cli { plugins as cli_plugins }
    try {
        cli_plugins(action=action, names=names, verbose=verbose);
        return 0;
    } except SystemExit as e {
        return e.code if isinstance(e.code, int) else 1;
    } except Exception as e {
        print(f"Error: {e}", file=sys.stderr);
        return 1;
    }
}
