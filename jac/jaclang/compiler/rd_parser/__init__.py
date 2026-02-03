"""Handwritten recursive descent parser for Jac, written in Jac.

Provides JacRDParser as a drop-in alternative to JacParser,
selectable via the JAC_RD_PARSER=1 environment variable.
"""

import logging
import os
from threading import Event
from typing import TYPE_CHECKING

import jaclang.pycore.unitree as uni
from jaclang.pycore.constant import CodeContext
from jaclang.pycore.passes.transform import Transform

if TYPE_CHECKING:
    from jaclang.pycore.program import JacProgram

logger = logging.getLogger(__name__)


class JacRDParser(Transform[uni.Source, uni.Module]):
    """Drop-in alternative to JacParser using handwritten recursive descent.

    This parser is written in Jac and compiled to Python. It produces the
    same AST (uni.Module) as the Lark-based JacParser, enabling A/B
    validation during development.

    Usage:
        Set environment variable JAC_RD_PARSER=1 to use this parser
        instead of the default Lark-based parser.
    """

    def __init__(
        self,
        root_ir: uni.Source,
        prog: "JacProgram",
        cancel_token: Event | None = None,
    ) -> None:
        """Initialize the RD parser."""
        self.mod_path: str = root_ir.loc.mod_path
        self.node_list: list[uni.UniNode] = []
        self._node_ids: set[int] = set()

        if cancel_token and cancel_token.is_set():
            return

        Transform.__init__(self, ir_in=root_ir, prog=prog, cancel_token=cancel_token)

    def transform(self, ir_in: uni.Source) -> uni.Module:
        """Transform source into AST Module using the RD parser."""
        try:
            # Import the Jac-compiled parser core
            from jaclang.compiler.rd_parser.parser import JacRDParserCore

            core = JacRDParserCore(
                source=ir_in.value,
                orig_src=ir_in,
                mod_path=self.mod_path,
            )
            mod = core.parse_module()

            # Transfer comments from lexer
            if hasattr(core, "lexer") and hasattr(core.lexer, "comments"):
                ir_in.comments = core.lexer.comments

            # Transfer node tracking
            if hasattr(core, "node_list"):
                self.node_list = core.node_list

            # Check for parse errors
            if not isinstance(mod, uni.Module):
                mod = uni.Module.make_stub(inject_src=ir_in)
                mod.has_syntax_errors = True
                self.log_error("Parser did not produce a Module", node_override=ir_in)
                return mod

            if hasattr(core, "errors_had") and core.errors_had:
                mod.has_syntax_errors = True
                for err in core.errors_had:
                    self.errors_had.append(err)
                    self.prog.errors_had.append(err)

            # Apply context coercion for .cl.jac, .sv.jac, .na.jac files
            self._apply_context_coercion(ir_in, mod)

            self.ir_out = mod
            return mod

        except Exception as e:
            logger.error("RD parser error in %s: %s", self.mod_path, e, exc_info=True)
            mod = uni.Module.make_stub(inject_src=ir_in)
            mod.has_syntax_errors = True
            self.log_error(f"Internal parser error: {e}", node_override=ir_in)
            return mod

    def _apply_context_coercion(self, ir_in: uni.Source, mod: uni.Module) -> None:
        """Apply .cl.jac / .sv.jac / .na.jac context coercion."""
        file_path = ir_in.loc.mod_path if ir_in.loc else ""

        if file_path.endswith(".cl.jac"):
            self._coerce_context(mod, CodeContext.CLIENT, uni.ClientBlock)
        elif file_path.endswith(".sv.jac"):
            self._coerce_context(mod, CodeContext.SERVER, uni.ServerBlock)
        elif file_path.endswith(".na.jac"):
            self._coerce_context(mod, CodeContext.NATIVE, uni.NativeBlock)

    @staticmethod
    def _coerce_context(
        module: uni.Module,
        default_context: CodeContext,
        unwrap_block_type: type,
    ) -> None:
        """Coerce module statements to a default context.

        Unwraps blocks of the given type and marks all top-level
        statements with the default context.
        """
        elements: list[uni.ElementStmt] = []
        for stmt in module.body:
            if isinstance(stmt, unwrap_block_type) and hasattr(stmt, "body"):
                elements.extend(stmt.body)  # type: ignore[union-attr]
            elif isinstance(stmt, uni.ElementStmt):
                elements.append(stmt)

        for elem in elements:
            # Skip blocks that are explicitly a different context
            if isinstance(elem, (uni.ClientBlock, uni.ServerBlock, uni.NativeBlock)):
                continue
            if isinstance(elem, uni.ContextAwareNode):
                elem.code_context = default_context.value  # type: ignore[assignment]
                # Propagate to inner body if ModuleCode
                if isinstance(elem, uni.ModuleCode) and elem.body:
                    for inner in elem.body:
                        if isinstance(inner, uni.ContextAwareNode):
                            inner.code_context = default_context.value  # type: ignore[assignment]

        module.body = elements


def is_rd_parser_enabled() -> bool:
    """Check if the RD parser is enabled via environment variable."""
    return os.environ.get("JAC_RD_PARSER", "0") == "1"
