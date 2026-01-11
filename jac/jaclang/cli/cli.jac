"""Command line interface tool for the Jac language.

This module provides the main CLI entry point. Command implementations
are in cli/impl/cli.impl.jac, and command registrations are in cli/commands/.
"""

# Import new registry infrastructure
import from jaclang.cli.registry { get_registry }
import from jaclang.cli.executor { get_executor }

# Import commands module to trigger auto-registration
import from jaclang.cli {
    commands
}

#===============================================================================
# SHARED UTILITIES (exported for use by plugins and tests)
#===============================================================================
"""Create JacRuntime and return the base path, module name, and runtime state."""
def proc_file_sess(filename: str, session: str, <>root: (str | None) = None) -> tuple;

"""Get an object by ID from a Jac program (utility for debugging/testing)."""
def get_object(filename: str, id: str, session: str = '', main: bool = True) -> dict;

"""Start REST API server (kept for backward compatibility with tests)."""
def serve(
    filename: str,
    session: str = '',
    port: int = 8000,
    main: bool = True,
    faux: bool = False
) -> None;

# Internal helper
def _ensure_jac_runtime -> None;

#===============================================================================
# ENTRY POINT
#===============================================================================
def start_cli -> None;

with entry:__main__ {
    start_cli();
}
