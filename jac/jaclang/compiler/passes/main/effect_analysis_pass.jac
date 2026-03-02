"""Effect Analysis Pass."""
import jaclang.jac0core.unitree as uni;
import from jaclang.jac0core.passes { UniPass }
import from jaclang.jac0core.constant { SymbolType }
import from jaclang.jac0core.constant { Tokens as Tok }
import from typing { Any }

"""Analyze side effects in ability and module_code bodies."""
obj EffectAnalysisPass(UniPass) {
    def init(ir_in: uni.Module, prog: Any, cancel_token: Any = None) -> None;
    def _scan_effects(body_nodes: list) -> dict;
    def exit_ability(nd: uni.Ability) -> None;
    def exit_module_code(nd: uni.ModuleCode) -> None;
    def exit_archetype(nd: uni.Archetype) -> None;
}
