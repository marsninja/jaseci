"""Jac Semantic Analysis Pass."""
import ast as ast3;
import re;
import from collections.abc { Sequence }
import jaclang.jac0core.unitree as uni;
import from jaclang.jac0core.constant { Tokens as Tok }
import from jaclang.jac0core.passes.uni_pass { UniPass }
"""Jac Semantic Analysis Pass."""
class SemanticAnalysisPass(UniPass) {
    def enter_archetype(self: SemanticAnalysisPass, nd: uni.Archetype) -> None;
    """Check a single archetype for issues with attributes and methods."""
    def _check_archetype(self: SemanticAnalysisPass, nd: uni.Archetype) -> None;

    def _update_ctx(self: SemanticAnalysisPass, nd: uni.UniNode) -> None;
    def enter_has_var(self: SemanticAnalysisPass, nd: uni.HasVar) -> None;
    def enter_param_var(self: SemanticAnalysisPass, nd: uni.ParamVar) -> None;
    def enter_assignment(self: SemanticAnalysisPass, nd: uni.Assignment) -> None;
    def enter_in_for_stmt(self: SemanticAnalysisPass, nd: uni.InForStmt) -> None;
    def enter_expr_as_item(self: SemanticAnalysisPass, nd: uni.ExprAsItem) -> None;
    def enter_inner_compr(self: SemanticAnalysisPass, nd: uni.InnerCompr) -> None;
    """Mark final element in trailer chain as a Store context."""
    def _change_atom_trailer_ctx(
        self: SemanticAnalysisPass, nd: uni.AtomTrailer
    ) -> None;

    """Warn about missing return type annotations."""
    def enter_ability(self: SemanticAnalysisPass, nd: uni.Ability) -> None;

    """Warn about wrong type names and missing f-string prefix."""
    def exit_string(self: SemanticAnalysisPass, nd: uni.String) -> None;

    """Warn about wrong type names like 'string' instead of 'str'."""
    def enter_sub_tag(self: SemanticAnalysisPass, nd: uni.SubTag) -> None;

    """Warn when await is used outside an async function."""
    def enter_await_expr(self: SemanticAnalysisPass, nd: uni.AwaitExpr) -> None;

    """Warn when function returns JsxElement without cl prefix."""
    def exit_ability(self: SemanticAnalysisPass, nd: uni.Ability) -> None;

    """Warn about string literals in event handler attributes."""
    def exit_jsx_normal_attribute(
        self: SemanticAnalysisPass, nd: uni.JsxNormalAttribute
    ) -> None;
}
