"""Semantic Definition Matching Pass for the Jac compiler.

This pass connects semantic string definitions (SemDefs) in the AST to their corresponding
declarations. It:

1. Establishes links between semantic string definitions in the main module and their declarations
2. Handles dotted name resolution for nested symbols
3. Issues warnings for unmatched semantic definitions

This pass is essential for Jac's semantic annotation system, allowing developers to define
semantics in one file and link them to their corresponding declarations in another.
"""
import jaclang.jac0core.unitree as uni;
import from jaclang.jac0core.passes.transform { Transform }
import from jaclang.jac0core.unitree { Symbol, UniScopeNode }
import from jaclang.jac0core.constant { Tokens as Tok }
import from jaclang.jac0core.diagnostics { E2013 }
"""Jac Semantic definition match pass."""
obj SemDefMatchPass(Transform[uni.Module, uni.Module]) {
    def transform(ir_in: uni.Module) -> uni.Module;
    def resolve_sem_target(
        semdef: uni.SemDef, target_sym_tab: UniScopeNode
    ) -> (Symbol | None);

    def connect_sems(
        source_sym_tab: UniScopeNode, target_sym_tab: UniScopeNode
    ) -> None;

    # Constant-fold a sem value expression to its string, or None when it is not
    # a compile-time-constant string. Folds string literals, MultiString
    # (implicit concatenation), parenthesized groups, and `+` over string
    # operands; everything else is non-constant.
    def fold_const_str(expr: uni.Expr) -> (str | None);
}
