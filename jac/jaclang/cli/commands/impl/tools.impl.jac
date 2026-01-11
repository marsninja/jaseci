"""Implementation of tools commands.

These implementations delegate to the existing CLI implementation functions.
"""

import sys;

"""Run the specified AST tool with optional arguments."""
impl tool(tool: str, args: list = []) -> int {
    import from jaclang.cli.cli { tool as cli_tool }
    try {
        cli_tool(tool=tool, args=args or None);
        return 0;
    } except SystemExit as e {
        return e.code if isinstance(e.code, int) else 1;
    } except Exception as e {
        print(f"Error: {e}", file=sys.stderr);
        return 1;
    }
}

"""Generate graph visualization."""
impl dot(
    filename: str,
    session: str = "",
    initial: str = "",
    depth: int = -1,
    traverse: bool = False,
    connection: list = [],
    bfs: bool = False,
    edge_limit: int = 512,
    node_limit: int = 512,
    saveto: str = "",
    to_screen: bool = False,
    format: str = "dot"
) -> int {
    import from jaclang.cli.cli { dot as cli_dot }
    try {
        cli_dot(
            filename=filename,
            session=session,
            initial=initial,
            depth=depth,
            traverse=traverse,
            connection=connection,
            bfs=bfs,
            edge_limit=edge_limit,
            node_limit=node_limit,
            saveto=saveto,
            to_screen=to_screen,
            format=format
        );
        return 0;
    } except SystemExit as e {
        return e.code if isinstance(e.code, int) else 1;
    } except Exception as e {
        print(f"Error: {e}", file=sys.stderr);
        return 1;
    }
}

"""Run Jac Language Server Protocol."""
impl lsp -> int {
    import from jaclang.cli.cli { lsp as cli_lsp }
    try {
        cli_lsp();
        return 0;
    } except SystemExit as e {
        return e.code if isinstance(e.code, int) else 1;
    } except Exception as e {
        print(f"Error: {e}", file=sys.stderr);
        return 1;
    }
}
