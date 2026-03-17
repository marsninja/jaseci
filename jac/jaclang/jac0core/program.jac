"""Jac Program module."""
import types;
import from threading { Event }
import from typing { TYPE_CHECKING }
import jaclang.jac0core.unitree as uni;
import from jaclang.jac0core.compile_options { CompileOptions }
import from jaclang.jac0core.mtp { Info }
import from jaclang.jac0core.passes { Alert }

with entry {
    if TYPE_CHECKING {
        import from jaclang.compiler.type_system.type_evaluator { TypeEvaluator }
        import from jaclang.jac0core.compiler { JacCompiler }
        import from jaclang.jac0core.passes { Transform }
    }
}

"""Holds the state of a compiled Jac program.

Uses class (not obj) because JacLangServer subclasses it and calls
JacProgram.init(self) explicitly — dataclass __init__ from obj would
conflict with that pattern.
"""
class JacProgram {
    def init(main_mod: (uni.ProgramModule | None) = None) -> None;
    def _get_compiler -> JacCompiler;
    def get_type_evaluator -> TypeEvaluator;
    def clear_type_system(clear_hub: bool = False) -> None;
    def get_bytecode(full_target: str) -> (types.CodeType | None);
    def parse_str(
        source_str: str, file_path: str, cancel_token: (Event | None) = None
    ) -> uni.Module;

    def compile(
        file_path: str,
        use_str: (str | None) = None,
        no_cgen: bool = False,
        type_check: bool = False,
        symtab_ir_only: bool = False,
        cancel_token: (Event | None) = None,
        options: (CompileOptions | None) = None
    ) -> uni.Module;

    def build(
        file_path: str, use_str: (str | None) = None, type_check: bool = False
    ) -> uni.Module;

    def run_schedule(
        mod: uni.Module,
        passes: list[type[Transform[uni.Module, uni.Module]]],
        cancel_token: (Event | None) = None
    ) -> None;

    static def jac_file_formatter(
        file_path: str, auto_lint: bool = False
    ) -> JacProgram {
        import from jaclang.jac0core.compiler { JacCompiler }
        return JacCompiler.jac_file_formatter(file_path, auto_lint);
    }

    static def jac_str_formatter(
        source_str: str, file_path: str, auto_lint: bool = False
    ) -> JacProgram {
        import from jaclang.jac0core.compiler { JacCompiler }
        return JacCompiler.jac_str_formatter(source_str, file_path, auto_lint);
    }

    static def jac_file_linter(file_path: str) -> JacProgram {
        import from jaclang.jac0core.compiler { JacCompiler }
        return JacCompiler.jac_file_linter(file_path);
    }
}
