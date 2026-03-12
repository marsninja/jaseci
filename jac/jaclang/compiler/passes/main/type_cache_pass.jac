"""Type cache pass for the Jac compiler.

Runs after TypeCheckPass and before codegen passes. Populates structured
JacType descriptors on AST nodes and symbol table entries, eliminating
the need for backends to perform inline type inference.

Per-symbol annotations populated:
  - Symbol.jac_type: JacType  (full structured type descriptor)
  - Symbol.resolved_type_name: str | None  (convenience, e.g., "int", "MyStruct")
  - Symbol.type_node: UniNode | None  (type annotation AST node from declaration)

Per-node annotations populated:
  - Expr.resolved_type_name: str | None  (e.g., "int", "MyStruct")
  - Expr.jac_type: JacType | None  (structured type from annotation)
"""
import from typing { Any }
import jaclang.jac0core.unitree as uni;
import from jaclang.jac0core.passes { UniPass }

"""Type cache pass — populates per-node and per-symbol type annotations."""
obj TypeCachePass(UniPass) {
    def init(ir_in: uni.Module, prog: Any, cancel_token: Any = None) -> None;
    def before_pass -> None;
    def _build_jac_type(nd: uni.UniNode) -> uni.JacType;
    def _build_jac_type_inner(nd: uni.UniNode) -> uni.JacType;
    def _extract_type_name(type_obj: Any) -> (str | None);
    def _type_name_from_annotation(nd: uni.UniNode) -> (str | None);
    def _resolve_symbol_types(scope: uni.UniScopeNode) -> None;
}
