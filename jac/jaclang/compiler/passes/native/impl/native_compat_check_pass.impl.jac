"""Implementation of NativeCompatCheckPass.

Reads the pre-computed gen.native_compat flag (set by UniTreeEnrichPass) and
applies runtime conditions to decide whether to promote the module.
"""

"""Check runtime conditions for auto-promotion."""
impl NativeCompatCheckPass.before_pass(self: NativeCompatCheckPass) -> None {
    self._runtime_ok: bool = False;
    # Only run when auto_promote_native is explicitly requested on the program
    if not getattr(self.prog, '_auto_promote_native', False) {
        return;
    }
    # Only promote the main entry file, not imported dependencies
    mod_path = self.ir_in.loc.mod_path if self.ir_in.loc else "";
    main_target = getattr(self.prog, '_auto_promote_target', "");
    if mod_path != main_target {
        return;
    }
    # Skip files that are already native or are annex/test modules
    if (
        mod_path.endswith('.na.jac')
        or mod_path.endswith('.impl.jac')
        or mod_path.endswith('.test.jac')
    ) {
        return;
    }
    self._runtime_ok = True;
}

"""Promote the module if both runtime conditions and AST pre-check pass."""
impl NativeCompatCheckPass.after_pass(self: NativeCompatCheckPass) -> None {
    if self._runtime_ok and self.ir_in.gen.native_compat {
        import from jaclang.jac0core.compiler { _coerce_native_module }
        _coerce_native_module(self.ir_in);
        # native_compat already True from UniTreeEnrichPass; keep it set.
    }
}
