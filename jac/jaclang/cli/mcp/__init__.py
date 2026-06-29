"""Built-in Model Context Protocol (MCP) server for AI-assisted Jac development.

Formerly the standalone ``jac-mcp`` plugin; now part of jaclang core. The MCP
protocol (JSON-RPC 2.0 over stdio / streamable-HTTP / SSE) is implemented on the
Python standard library in :mod:`jaclang.cli.mcp.protocol`, so it has no
third-party dependencies. The ``jac mcp`` command is registered by
:mod:`jaclang.cli.commands.mcp`.
"""
