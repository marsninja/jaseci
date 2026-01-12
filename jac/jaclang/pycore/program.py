"""Jac Program module.

This module provides the JacProgram class which holds the state of a compiled
Jac program. The actual compilation is performed by JacCompiler.

For backward compatibility, JacProgram retains compile/parse methods that
delegate to JacCompiler, but these are deprecated in favor of using the
compiler directly.
"""

from __future__ import annotations

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
from jaclang.pycore.passes import Alert

if TYPE_CHECKING:
    from jaclang.compiler.type_system.type_evaluator import TypeEvaluator
    from jaclang.pycore.passes import Transform


class JacProgram:
    """JacProgram holds the state of a compiled Jac program.

    This class contains:
    - mod: The ProgramModule containing all compiled modules in mod.hub
    - errors_had: List of compilation errors
    - warnings_had: List of compilation warnings
    - type_evaluator: Optional type evaluator for type checking
    - py_raise_map: Mapping for Python exception translation

    Compilation is performed by JacCompiler, which takes a JacProgram
    as a target to store compiled modules and track errors.
    """

    def __init__(
        self,
        main_mod: uni.ProgramModule | None = None,
        bytecode_cache: BytecodeCache | None = None,
    ) -> None:
        """Initialize the JacProgram object.

        Args:
            main_mod: Optional main module to initialize with.
            bytecode_cache: Optional custom bytecode cache. If None, uses default.
        """
        self.mod: uni.ProgramModule = main_mod if main_mod else uni.ProgramModule()
        self.py_raise_map: dict[str, str] = {}
        self.errors_had: list[Alert] = []
        self.warnings_had: list[Alert] = []
        self.type_evaluator: TypeEvaluator | None = None
        self._bytecode_cache: BytecodeCache = bytecode_cache or get_bytecode_cache()

    def get_type_evaluator(self) -> TypeEvaluator:
        """Return the type evaluator, creating one if needed."""
        from jaclang.compiler.type_system.type_evaluator import TypeEvaluator

        if not self.type_evaluator:
            self.type_evaluator = TypeEvaluator(program=self)
        return self.type_evaluator

    def clear_type_system(self, clear_hub: bool = False) -> None:
        """Clear all type information from the program.

        This method resets the type evaluator and clears cached type information
        from all AST nodes. This is useful for test isolation when running multiple
        tests in the same process, as type information attached to AST nodes can
        persist in sys.modules and pollute subsequent tests.

        Args:
            clear_hub: If True, also clear all modules from mod.hub. Use with
                       caution as this removes all compiled modules.
        """
        # Clear the type evaluator (will be recreated lazily if needed)
        self.type_evaluator = None

        # Optionally clear the entire module hub (skip node traversal if clearing hub)
        if clear_hub:
            self.mod.hub.clear()
        else:
            # Clear .type attributes from all Expr nodes in all modules
            for mod in self.mod.hub.values():
                for node in mod.get_all_sub_nodes(uni.Expr, brute_force=True):
                    node.type = None

    # =========================================================================
    # Backward-compatible methods that delegate to JacCompiler
    # These methods allow existing code to continue working while we migrate
    # to using JacCompiler directly.
    # =========================================================================

    def get_bytecode(
        self, full_target: str, minimal: bool = False
    ) -> types.CodeType | None:
        """Get the bytecode for a specific module.

        This method implements a three-tier caching strategy:
        1. In-memory cache (mod.hub) - fastest, within current process
        2. Disk cache (.jac/cache/) - persists across restarts
        3. Full compilation - slowest, only when cache misses

        Args:
            full_target: The full path to the module file.
            minimal: If True, use minimal compilation (no JS/type analysis).
                     This avoids circular imports for bootstrap-critical modules.
        """
        # Tier 1: Check in-memory cache (mod.hub)
        if full_target in self.mod.hub and self.mod.hub[full_target].gen.py_bytecode:
            codeobj = self.mod.hub[full_target].gen.py_bytecode
            return marshal.loads(codeobj) if isinstance(codeobj, bytes) else None

        # Tier 2: Check disk cache (.jac/cache/)
        cache_key = CacheKey.for_source(full_target, minimal)
        cached_code = self._bytecode_cache.get(cache_key)
        if cached_code is not None:
            return cached_code

        # Tier 3: Compile and cache bytecode
        result = self.compile(file_path=full_target, minimal=minimal)
        if result.gen.py_bytecode:
            self._bytecode_cache.put(cache_key, result.gen.py_bytecode)
            return marshal.loads(result.gen.py_bytecode)
        return None

    def parse_str(
        self, source_str: str, file_path: str, cancel_token: Event | None = None
    ) -> uni.Module:
        """Parse source string into an AST module.

        Delegates to JacCompiler for the actual parsing.
        """
        from jaclang.pycore.compiler import JacCompiler

        compiler = JacCompiler(bytecode_cache=self._bytecode_cache)
        return compiler.parse_str(source_str, file_path, self, cancel_token)

    def compile(
        self,
        file_path: str,
        use_str: str | None = None,
        no_cgen: bool = False,
        type_check: bool = False,
        symtab_ir_only: bool = False,
        minimal: bool = False,
        cancel_token: Event | None = None,
    ) -> uni.Module:
        """Compile a Jac file into a module AST.

        Delegates to JacCompiler for the actual compilation.

        Args:
            file_path: Path to the Jac file to compile.
            use_str: Optional source string to use instead of reading from file.
            no_cgen: If True, skip code generation entirely.
            type_check: If True, run type checking pass.
            symtab_ir_only: If True, only build symbol table (skip semantic analysis).
            minimal: If True, use minimal compilation mode (bytecode only, no JS).
                     This avoids circular imports for bootstrap-critical modules.
            cancel_token: Optional event to cancel compilation.
        """
        from jaclang.pycore.compiler import JacCompiler

        compiler = JacCompiler(bytecode_cache=self._bytecode_cache)
        return compiler.compile(
            file_path=file_path,
            target_program=self,
            use_str=use_str,
            no_cgen=no_cgen,
            type_check=type_check,
            symtab_ir_only=symtab_ir_only,
            minimal=minimal,
            cancel_token=cancel_token,
        )

    def build(
        self, file_path: str, use_str: str | None = None, type_check: bool = False
    ) -> uni.Module:
        """Build a Jac file with import dependency resolution.

        Delegates to JacCompiler for the actual build.
        """
        from jaclang.pycore.compiler import JacCompiler

        compiler = JacCompiler(bytecode_cache=self._bytecode_cache)
        return compiler.build(file_path, self, use_str, type_check=type_check)

    def run_schedule(
        self,
        mod: uni.Module,
        passes: list[type[Transform[uni.Module, uni.Module]]],
        cancel_token: Event | None = None,
    ) -> None:
        """Run a schedule of passes on a module.

        Delegates to JacCompiler for the actual pass execution.
        """
        from jaclang.pycore.compiler import JacCompiler

        compiler = JacCompiler(bytecode_cache=self._bytecode_cache)
        compiler.run_schedule(mod, self, passes, cancel_token)

    @staticmethod
    def jac_file_formatter(file_path: str, auto_lint: bool = False) -> JacProgram:
        """Format a Jac file and return the JacProgram.

        Delegates to JacCompiler for the actual formatting.

        Args:
            file_path: Path to the Jac file to format.
            auto_lint: If True, apply auto-linting corrections before formatting.
        """
        from jaclang.pycore.compiler import JacCompiler

        return JacCompiler.jac_file_formatter(file_path, auto_lint)

    @staticmethod
    def jac_str_formatter(
        source_str: str, file_path: str, auto_lint: bool = False
    ) -> JacProgram:
        """Format a Jac string and return the JacProgram.

        Delegates to JacCompiler for the actual formatting.

        Args:
            source_str: The Jac source code string to format.
            file_path: Path to use for error messages.
            auto_lint: If True, apply auto-linting corrections before formatting.
        """
        from jaclang.pycore.compiler import JacCompiler

        return JacCompiler.jac_str_formatter(source_str, file_path, auto_lint)
