"""Native compatibility promotion pass.

Reads the pre-computed gen.native_compat flag (set by UniTreeEnrichPass) and
applies runtime conditions to decide whether to promote the module.

AST analysis (which constructs disqualify native compilation) lives exclusively
in UniTreeEnrichPass so the analysis runs once, is cached in the JIR, and is
not repeated at codegen time.
"""
import jaclang.jac0core.unitree as uni;
import from jaclang.jac0core.passes.uni_pass { UniPass }

"""Promote a .jac module to native context when all conditions are met.

    Conditions checked here (runtime, not pre-computable by UniTreeEnrichPass):
      1. The program explicitly requested auto-promotion (_auto_promote_native).
      2. This module is the target file (_auto_promote_target).
      3. The module is not already .na.jac / .impl.jac / .test.jac.

    Condition checked by UniTreeEnrichPass (stored on gen.native_compat):
      4. No disqualifying AST constructs (walkers, edges, async, etc.).
      5. Has a 'with entry {}' block.
    """
class NativeCompatCheckPass(UniPass) {
    def before_pass(self: NativeCompatCheckPass) -> None;
    def after_pass(self: NativeCompatCheckPass) -> None;
}
