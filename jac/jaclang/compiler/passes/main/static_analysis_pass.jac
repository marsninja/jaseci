"""Static analysis pass for the Jac compiler.

This pass detects:
1. Unused variables - symbols defined but never referenced
2. Undefined variables - name references that failed to resolve
3. Unreachable code - statements with no incoming control flow edges
"""
import ast as ast3;
import from collections.abc { Sequence }
import jaclang.jac0core.unitree as uni;
import from jaclang.jac0core.passes { UniPass }
import from jaclang.jac0core.constant { SymbolType }
import from jaclang.compiler.type_system.types { ClassType, TypeBase }
import from jaclang.jac0core.diagnostics {
    W1153,
    W2001,
    W2002,
    W2003,
    W2027,
    W2031,
    W2032,
    W2041,
    W2047,
    W2050,
    W2052,
    W2058,
    W2062,
    W2063,
    W2070,
    W2074,
    W2075,
    W2085,
    E1113,
    E2036,
    E2042,
    E2044,
    E2055,
    E2083
}

"""Static analysis pass for JacLang."""
obj StaticAnalysisPass(UniPass) {
    def init(ir_in: uni.Module, prog: Any, cancel_token: Any = None) -> None;
    def after_pass -> None;
    def _check_unused_symbols(scope: uni.UniScopeNode) -> None;
    def _check_undefined_names(mod: uni.Module) -> None;
    def _check_unreachable_code(mod: uni.Module) -> None;
    def _check_semantic_patterns(mod: uni.Module) -> None;
    def _check_scope_diagnostics(mod: uni.Module) -> None;
    def _check_archetype_semantics(mod: uni.Module) -> None;
    def _body_always_returns(body: Sequence) -> bool;
    def _elseif_always_returns(nd: uni.ElseIf) -> bool;
    def _check_scope_defs(scope: uni.UniScopeNode) -> None;
}
