"""PyCore - Bootstrap-critical Python core for Jac.

This package contains the minimal Python code required to bootstrap the Jac
compiler. Everything else in the jaclang codebase can be written in Jac.

Modules:
- ast/: Core AST definitions (unitree, constant, codeinfo)
- parser/: Jac parser using Lark
- passes/: Bootstrap-critical compiler passes
- runtime/: Runtime bootstrap infrastructure
- settings: Configuration settings
- utils/: Utility functions
"""

# Note: Don't eagerly import submodules here to avoid circular imports.
# Submodules are imported lazily when accessed.

__all__ = ["ast", "parser", "passes", "runtime", "settings", "utils"]
