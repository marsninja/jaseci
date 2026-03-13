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
import from jaclang.jac0core.diagnostics {
    E1100,
    W1102,
    W1104,
    E1110,
    E1111,
    E1113,
    E1120,
    E1130,
    E1140,
    W1153,
    E1160,
    W1161,
    W1172,
    E1180,
    E1182,
    W2001,
    W2002,
    W2003,
    E2020,
    W2025,
    W2027,
    E2029,
    E2030,
    W2031,
    W2032,
    E2034,
    E2036,
    W2041,
    E2042,
    E2044,
    W2047,
    W2050,
    W2052,
    W2058,
    W2062,
    W2063,
    W2070,
    W2074,
    W2075,
    E2055,
    E2080,
    E2083,
    W2085,
    E4001,
    W4004,
    W4005
}

"""Static analysis pass for JacLang."""
obj StaticAnalysisPass(UniPass) {
    def init(ir_in: uni.Module, prog: Any, cancel_token: Any = None) -> None;
    def after_pass -> None;
    def _check_unused_symbols(scope: uni.UniScopeNode) -> None;
    def _check_undefined_names(mod: uni.Module) -> None;
    def _check_unreachable_code(mod: uni.Module) -> None;
    def _check_semantic_patterns(mod: uni.Module) -> None;
    def _check_scope_patterns(mod: uni.Module) -> None;
    def _check_archetype_patterns(mod: uni.Module) -> None;
    def _check_walker_patterns(mod: uni.Module) -> None;
    def _check_type_patterns(mod: uni.Module) -> None;
}
