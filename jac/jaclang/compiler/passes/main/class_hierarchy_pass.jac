"""Class Hierarchy Pass."""
import jaclang.jac0core.unitree as uni;
import from jaclang.jac0core.passes { UniPass }
import from typing { Any }

"""Build class hierarchy and vtable layouts from type system."""
obj ClassHierarchyPass(UniPass) {
    def init(ir_in: uni.Module, prog: Any, cancel_token: Any = None) -> None;
    def before_pass -> None;
    def exit_archetype(nd: uni.Archetype) -> None;
    def after_pass -> None;
}
