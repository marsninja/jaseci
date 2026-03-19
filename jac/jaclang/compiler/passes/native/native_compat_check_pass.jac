"""Reads gen.native_compat (set by UniTreeEnrichPass) and promotes the module
to native context when runtime conditions are also met."""
import jaclang.jac0core.unitree as uni;
import from jaclang.jac0core.passes.uni_pass { UniPass }

class NativeCompatCheckPass(UniPass) {
    def before_pass(self: NativeCompatCheckPass) -> None;
    def after_pass(self: NativeCompatCheckPass) -> None;
}
