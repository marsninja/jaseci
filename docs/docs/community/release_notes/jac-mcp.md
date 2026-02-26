# jac-mcp Release Notes

## jac-mcp 0.1.1 (Unreleased)

- **Expanded documentation resources**: DOC_MAPPINGS now covers all 42 mkdocs pages (up from 12), including tutorials, developer workflow, and quick-start guides
- **Auto-generated doc bundling**: New `scripts/bundle_docs.jac` script replaces hardcoded CI copy commands, using DOC_MAPPINGS as the single source of truth for PyPI release bundling
- **New `get_ir` tool**: Full IR inspection with 12 output formats -- sym, sym_dot, ast, ast_dot, cfg_dot, unparse, pyast, py, docir, esast, es, llvmir (replaces stub `get_ast`)
- **New `lint_jac` tool**: Lint Jac code for style/correctness violations with optional auto-fix
- **New `jac_to_py` tool**: Compile Jac code to Python, returning generated source
- **New `jac_to_js` tool**: Compile Jac code to JavaScript, returning generated source

## jac-mcp 0.1.0

Initial release of jac-mcp, the MCP (Model Context Protocol) server plugin for Jac.

### Features

- **MCP Server**: Full MCP server with stdio, SSE, and streamable-http transport support
- **Resources (24+)**: Grammar spec, token definitions, 11 documentation sections, example index, bundled pitfalls/patterns guides
- **Tools (9)**: validate_jac, check_syntax, format_jac, py_to_jac, explain_error, list_examples, get_example, search_docs, get_ast
- **Prompts (9)**: write_module, write_impl, write_walker, write_node, write_test, write_ability, debug_error, fix_type_error, migrate_python
- **Compiler Bridge**: Parse, typecheck, format, and py2jac operations with timeout protection and input size limits
- **CLI Integration**: `jac mcp` command with --transport, --port, --host, --inspect flags
- **Plugin System**: Full Jac plugin with JacCmd and JacPluginConfig hooks
