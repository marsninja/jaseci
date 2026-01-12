"""Jac Compiler module.

This module provides the JacCompiler class, a singleton that handles all
compilation operations. The compiler is separate from the JacProgram which
holds the compiled user program state.
"""

from __future__ import annotations

import ast as py_ast
import marshal
import types
from threading import Event
from typing import TYPE_CHECKING

import jaclang.pycore.unitree as uni
from jaclang.pycore.bccache import (
    BytecodeCache,
    CacheKey,
    get_bytecode_cache,
)
from jaclang.pycore.helpers import read_file_with_encoding
from jaclang.pycore.jac_parser import JacParser
from jaclang.pycore.passes import (
    DeclImplMatchPass,
    JacAnnexPass,
    PyastGenPass,
    PyBytecodeGenPass,
    SemanticAnalysisPass,
    SymTabBuildPass,
    Transform,
)
from jaclang.pycore.tsparser import TypeScriptParser

if TYPE_CHECKING:
    from jaclang.pycore.program import JacProgram


# Lazy schedule getters - enables converting analysis passes to Jac
def get_symtab_ir_sched() -> list[type[Transform[uni.Module, uni.Module]]]:
    """Return symbol table build schedule with lazy imports."""
    return [SymTabBuildPass, DeclImplMatchPass]


def get_ir_gen_sched() -> list[type[Transform[uni.Module, uni.Module]]]:
    """Return full IR generation schedule with lazy imports."""
    from jaclang.compiler.passes.main import CFGBuildPass, SemDefMatchPass

    return [
        SymTabBuildPass,
        DeclImplMatchPass,
        SemanticAnalysisPass,
        SemDefMatchPass,
        CFGBuildPass,
    ]


def get_type_check_sched() -> list[type[Transform[uni.Module, uni.Module]]]:
    """Return type checking schedule with lazy imports."""
    from jaclang.compiler.passes.main import TypeCheckPass

    return [TypeCheckPass]


def get_py_code_gen() -> list[type[Transform[uni.Module, uni.Module]]]:
    """Return Python code generation schedule with lazy imports."""
    from jaclang.compiler.passes.ecmascript import EsastGenPass
    from jaclang.compiler.passes.main import PyJacAstLinkPass

    return [EsastGenPass, PyastGenPass, PyJacAstLinkPass, PyBytecodeGenPass]


def get_minimal_ir_gen_sched() -> list[type[Transform[uni.Module, uni.Module]]]:
    """Return minimal IR generation schedule (no CFG for faster bootstrap).

    This schedule is used for bootstrap-critical modules that need basic
    semantic analysis but don't need full control flow analysis.
    """
    return [SymTabBuildPass, DeclImplMatchPass, SemanticAnalysisPass]


def get_minimal_py_code_gen() -> list[type[Transform[uni.Module, uni.Module]]]:
    """Return minimal Python code generation schedule (bytecode only, no JS/type analysis).

    This schedule is used for bootstrap-critical modules (like runtimelib) that must
    be compiled without triggering imports that could cause circular dependencies.
    """
    return [PyastGenPass, PyBytecodeGenPass]


def get_format_sched(
    auto_lint: bool = False,
) -> list[type[Transform[uni.Module, uni.Module]]]:
    """Return format schedule with lazy imports to allow doc_ir.jac conversion.

    Args:
        auto_lint: If True, include auto-linting pass before formatting. Defaults to False.
    """
    from jaclang.compiler.passes.tool.comment_injection_pass import (
        CommentInjectionPass,
    )
    from jaclang.compiler.passes.tool.doc_ir_gen_pass import DocIRGenPass
    from jaclang.compiler.passes.tool.jac_auto_lint_pass import JacAutoLintPass
    from jaclang.compiler.passes.tool.jac_formatter_pass import JacFormatPass
    from jaclang.pycore.passes.annex_pass import JacAnnexPass

    if auto_lint:
        return [
            JacAnnexPass,  # Load impl modules before auto-linting
            JacAutoLintPass,
            DocIRGenPass,
            CommentInjectionPass,
            JacFormatPass,
        ]
    else:
        return [
            DocIRGenPass,
            CommentInjectionPass,
            JacFormatPass,
        ]


class JacCompiler:
    """Jac Compiler - singleton that handles all compilation operations.

    The compiler is responsible for:
    - Parsing source files into AST
    - Running compilation passes
    - Managing bytecode caching
    - Coordinating compilation for a target JacProgram

    The compiler itself is stateless with respect to any particular program.
    All program-specific state (modules, errors, warnings) lives in JacProgram.
    """

    def __init__(self, bytecode_cache: BytecodeCache | None = None) -> None:
        """Initialize the JacCompiler.

        Args:
            bytecode_cache: Optional custom bytecode cache. If None, uses default.
        """
        self._bytecode_cache: BytecodeCache = bytecode_cache or get_bytecode_cache()

    def get_bytecode(
        self, full_target: str, target_program: JacProgram, minimal: bool = False
    ) -> types.CodeType | None:
        """Get the bytecode for a specific module.

        This method implements a three-tier caching strategy:
        1. In-memory cache (target_program.mod.hub) - fastest, within current process
        2. Disk cache (.jac/cache/) - persists across restarts
        3. Full compilation - slowest, only when cache misses

        Args:
            full_target: The full path to the module file.
            target_program: The JacProgram to compile into.
            minimal: If True, use minimal compilation (no JS/type analysis).
                     This avoids circular imports for bootstrap-critical modules.
        """
        # Tier 1: Check in-memory cache (mod.hub)
        if (
            full_target in target_program.mod.hub
            and target_program.mod.hub[full_target].gen.py_bytecode
        ):
            codeobj = target_program.mod.hub[full_target].gen.py_bytecode
            return marshal.loads(codeobj) if isinstance(codeobj, bytes) else None

        # Tier 2: Check disk cache (.jac/cache/)
        cache_key = CacheKey.for_source(full_target, minimal)
        cached_code = self._bytecode_cache.get(cache_key)
        if cached_code is not None:
            return cached_code

        # Tier 3: Compile and cache bytecode
        result = self.compile(
            file_path=full_target, target_program=target_program, minimal=minimal
        )
        if result.gen.py_bytecode:
            self._bytecode_cache.put(cache_key, result.gen.py_bytecode)
            return marshal.loads(result.gen.py_bytecode)
        return None

    def parse_str(
        self,
        source_str: str,
        file_path: str,
        target_program: JacProgram,
        cancel_token: Event | None = None,
    ) -> uni.Module:
        """Parse source string into an AST module.

        Args:
            source_str: The source code string to parse.
            file_path: Path to the source file (for error messages).
            target_program: The JacProgram to store the parsed module in.
            cancel_token: Optional event to cancel parsing.
        """
        had_error = False
        if file_path.endswith(".py") or file_path.endswith(".pyi"):
            from jaclang.compiler.passes.main import PyastBuildPass

            parsed_ast = py_ast.parse(source_str)
            py_ast_ret = PyastBuildPass(
                ir_in=uni.PythonModuleAst(
                    parsed_ast,
                    orig_src=uni.Source(source_str, mod_path=file_path),
                ),
                prog=target_program,
                cancel_token=cancel_token,
            )
            had_error = len(py_ast_ret.errors_had) > 0
            mod = py_ast_ret.ir_out
        elif file_path.endswith((".js", ".ts", ".jsx", ".tsx")):
            # Parse TypeScript/JavaScript files
            source = uni.Source(source_str, mod_path=file_path)
            ts_ast_ret = TypeScriptParser(
                root_ir=source, prog=target_program, cancel_token=cancel_token
            )
            had_error = len(ts_ast_ret.errors_had) > 0
            mod = ts_ast_ret.ir_out
        else:
            source = uni.Source(source_str, mod_path=file_path)
            jac_ast_ret: Transform[uni.Source, uni.Module] = JacParser(
                root_ir=source, prog=target_program
            )
            had_error = len(jac_ast_ret.errors_had) > 0
            mod = jac_ast_ret.ir_out
        if had_error:
            return mod
        if target_program.mod.main.stub_only:
            target_program.mod = uni.ProgramModule(mod)
        target_program.mod.hub[mod.loc.mod_path] = mod
        JacAnnexPass(ir_in=mod, prog=target_program)
        return mod

    def compile(
        self,
        file_path: str,
        target_program: JacProgram,
        use_str: str | None = None,
        no_cgen: bool = False,
        type_check: bool = False,
        symtab_ir_only: bool = False,
        minimal: bool = False,
        cancel_token: Event | None = None,
    ) -> uni.Module:
        """Compile a Jac file into a module AST.

        Args:
            file_path: Path to the Jac file to compile.
            target_program: The JacProgram to compile into.
            use_str: Optional source string to use instead of reading from file.
            no_cgen: If True, skip code generation entirely.
            type_check: If True, run type checking pass.
            symtab_ir_only: If True, only build symbol table (skip semantic analysis).
            minimal: If True, use minimal compilation mode (bytecode only, no JS).
                     This avoids circular imports for bootstrap-critical modules.
            cancel_token: Optional event to cancel compilation.
        """
        keep_str = use_str or read_file_with_encoding(file_path)
        mod_targ = self.parse_str(
            keep_str, file_path, target_program, cancel_token=cancel_token
        )
        if symtab_ir_only:
            # only build symbol table and match decl/impl (skip semantic analysis and CFG)
            self.run_schedule(
                mod=mod_targ,
                target_program=target_program,
                passes=get_symtab_ir_sched(),
                cancel_token=cancel_token,
            )
        elif minimal:
            # Minimal IR generation (skip CFG for faster bootstrap)
            self.run_schedule(
                mod=mod_targ,
                target_program=target_program,
                passes=get_minimal_ir_gen_sched(),
                cancel_token=cancel_token,
            )
        else:
            # Full IR generation
            self.run_schedule(
                mod=mod_targ,
                target_program=target_program,
                passes=get_ir_gen_sched(),
                cancel_token=cancel_token,
            )
        if type_check and not minimal:
            self.run_schedule(
                mod=mod_targ,
                target_program=target_program,
                passes=get_type_check_sched(),
                cancel_token=cancel_token,
            )
        # If the module has syntax errors, we skip code generation.
        if (not mod_targ.has_syntax_errors) and (not no_cgen):
            codegen_sched = get_minimal_py_code_gen() if minimal else get_py_code_gen()
            self.run_schedule(
                mod=mod_targ,
                target_program=target_program,
                passes=codegen_sched,
                cancel_token=cancel_token,
            )
        return mod_targ

    def build(
        self,
        file_path: str,
        target_program: JacProgram,
        use_str: str | None = None,
        type_check: bool = False,
    ) -> uni.Module:
        """Build a Jac file with import dependency resolution.

        Args:
            file_path: Path to the Jac file to build.
            target_program: The JacProgram to build into.
            use_str: Optional source string to use instead of reading from file.
            type_check: If True, run type checking pass.
        """
        from jaclang.compiler.passes.main import JacImportDepsPass

        mod_targ = self.compile(
            file_path, target_program, use_str, type_check=type_check
        )
        JacImportDepsPass(ir_in=mod_targ, prog=target_program)
        SemanticAnalysisPass(ir_in=mod_targ, prog=target_program)
        return mod_targ

    def run_schedule(
        self,
        mod: uni.Module,
        target_program: JacProgram,
        passes: list[type[Transform[uni.Module, uni.Module]]],
        cancel_token: Event | None = None,
    ) -> None:
        """Run a schedule of passes on a module.

        Args:
            mod: The module to run passes on.
            target_program: The JacProgram for error/warning tracking.
            passes: List of pass classes to run in order.
            cancel_token: Optional event to cancel the schedule.
        """
        for current_pass in passes:
            current_pass(ir_in=mod, prog=target_program, cancel_token=cancel_token)  # type: ignore

    @staticmethod
    def jac_file_formatter(file_path: str, auto_lint: bool = False) -> JacProgram:
        """Format a Jac file and return the JacProgram.

        Args:
            file_path: Path to the Jac file to format.
            auto_lint: If True, apply auto-linting corrections before formatting.
        """
        from jaclang.pycore.program import JacProgram

        prog = JacProgram()
        source_str = read_file_with_encoding(file_path)
        source = uni.Source(source_str, mod_path=file_path)
        parser_pass = JacParser(root_ir=source, prog=prog)
        current_mod = parser_pass.ir_out
        for pass_cls in get_format_sched(auto_lint=auto_lint):
            current_mod = pass_cls(ir_in=current_mod, prog=prog).ir_out
        prog.mod = uni.ProgramModule(current_mod)
        return prog

    @staticmethod
    def jac_str_formatter(
        source_str: str, file_path: str, auto_lint: bool = False
    ) -> JacProgram:
        """Format a Jac string and return the JacProgram.

        Args:
            source_str: The Jac source code string to format.
            file_path: Path to use for error messages.
            auto_lint: If True, apply auto-linting corrections before formatting.
        """
        from jaclang.pycore.program import JacProgram

        prog = JacProgram()
        source = uni.Source(source_str, mod_path=file_path)
        parser_pass = JacParser(root_ir=source, prog=prog)
        current_mod = parser_pass.ir_out
        for pass_cls in get_format_sched(auto_lint=auto_lint):
            current_mod = pass_cls(ir_in=current_mod, prog=prog).ir_out
        prog.mod = uni.ProgramModule(current_mod)
        return prog
