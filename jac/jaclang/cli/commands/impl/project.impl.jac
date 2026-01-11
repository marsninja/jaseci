"""Implementation of project commands.

Direct imports from cli.impl - no indirection through cli.jac.
"""

import sys;

"""Initialize a new Jac project."""
impl create(name: str = "", force: bool = False) -> int {
    import from jaclang.cli.impl.cli { create as cli_create }
    try {
        cli_create(name=name, force=force);
        return 0;
    } except SystemExit as e {
        return e.code if isinstance(e.code, int) else 1;
    } except Exception as e {
        print(f"Error: {e}", file=sys.stderr);
        return 1;
    }
}

"""Install all dependencies from jac.toml."""
impl install(dev: bool = False, verbose: bool = False) -> int {
    import from jaclang.cli.impl.cli { install as cli_install }
    try {
        cli_install(dev=dev, verbose=verbose);
        return 0;
    } except SystemExit as e {
        return e.code if isinstance(e.code, int) else 1;
    } except Exception as e {
        print(f"Error: {e}", file=sys.stderr);
        return 1;
    }
}

"""Add dependencies to the project."""
impl add(
    packages: list = [],
    dev: bool = False,
    git: str = "",
    cl: bool = False,
    verbose: bool = False
) -> int {
    import from jaclang.cli.impl.cli { add as cli_add }
    try {
        cli_add(packages=packages, dev=dev, git=git, cl=cl, verbose=verbose);
        return 0;
    } except SystemExit as e {
        return e.code if isinstance(e.code, int) else 1;
    } except Exception as e {
        print(f"Error: {e}", file=sys.stderr);
        return 1;
    }
}

"""Remove dependencies from the project."""
impl remove(packages: list = [], dev: bool = False, cl: bool = False) -> int {
    import from jaclang.cli.impl.cli { remove as cli_remove }
    try {
        cli_remove(packages=packages, dev=dev, cl=cl);
        return 0;
    } except SystemExit as e {
        return e.code if isinstance(e.code, int) else 1;
    } except Exception as e {
        print(f"Error: {e}", file=sys.stderr);
        return 1;
    }
}

"""Run custom scripts defined in jac.toml."""
impl script(name: str = "", list_scripts: bool = False) -> int {
    import from jaclang.cli.impl.cli { script as cli_script }
    try {
        cli_script(name=name, list_scripts=list_scripts);
        return 0;
    } except SystemExit as e {
        return e.code if isinstance(e.code, int) else 1;
    } except Exception as e {
        print(f"Error: {e}", file=sys.stderr);
        return 1;
    }
}
