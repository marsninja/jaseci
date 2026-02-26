"""Compiler bridge for jac-mcp.

This module wraps jaclang's compiler pipeline for use by MCP tools,
providing parse, typecheck, format, IR generation, lint, and code
generation operations.
"""

import from typing { Any }

glob MAX_INPUT_SIZE: int = 102400,
     DEFAULT_TIMEOUT: int = 10,
     IR_FORMATS: list[str] = [
         "sym",
         "sym_dot",
         "ast",
         "ast_dot",
         "cfg_dot",
         "unparse",
         "pyast",
         "py",
         "docir",
         "esast",
         "es",
         "llvmir"
     ];

"""Run a function with timeout protection."""
def run_with_timeout(func: object, timeout: int = 10) -> tuple;

"""Bridge to jaclang compiler pipeline."""
obj CompilerBridge {
    """Parse Jac code and return structured errors."""
    static def parse_snippet(
        code: str, filename: str = "snippet.jac"
    ) -> dict[str, Any];

    """Full type-check pipeline on Jac code."""
    static def typecheck_snippet(
        code: str, filename: str = "snippet.jac"
    ) -> dict[str, Any];

    """Format Jac code."""
    static def format_snippet(code: str) -> dict[str, Any];

    """Convert Python code to Jac."""
    static def py_to_jac(python_code: str) -> dict[str, Any];

    """Generate IR output in the specified format."""
    static def ir_gen(code: str, output_format: str) -> dict[str, Any];

    """Lint Jac code with optional auto-fix."""
    static def lint_snippet(code: str, fix: bool = False) -> dict[str, Any];

    """Compile Jac code to Python."""
    static def jac_to_py_code(code: str) -> dict[str, Any];

    """Compile Jac code to JavaScript."""
    static def jac_to_js_code(code: str) -> dict[str, Any];
}
