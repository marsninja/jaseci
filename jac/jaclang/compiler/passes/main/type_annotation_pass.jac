"""Type Annotation Pass."""
import jaclang.jac0core.unitree as uni;
import from jaclang.jac0core.passes { UniPass }
import from typing { Any }

"""Materialize resolved type annotations onto AST node gen fields."""
obj TypeAnnotationPass(UniPass) {
    def init(ir_in: uni.Module, prog: Any, cancel_token: Any = None) -> None;
    def before_pass -> None;
    def _resolve_type_annotation(type_expr: (uni.UniNode | None)) -> tuple;
    def _type_base_to_triple(tb: Any) -> tuple;
    def exit_param_var(nd: uni.ParamVar) -> None;
    def exit_has_var(nd: uni.HasVar) -> None;
    def exit_func_signature(nd: uni.FuncSignature) -> None;
    def exit_assignment(nd: uni.Assignment) -> None;
    def exit_in_for_stmt(nd: uni.InForStmt) -> None;
    def _resolve_from_ast(type_expr: uni.UniNode) -> tuple;
    def exit_list_compr(nd: uni.ListCompr) -> None;
    def exit_set_compr(nd: uni.SetCompr) -> None;
}
