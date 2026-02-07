"""Compilation options for the Jac compiler.""";

import from typing { Any }


# =============================================================================
# Compile Options
# =============================================================================


obj CompileOptions {
    """Options controlling Jac compilation behavior.""";

    has minimal: bool = False,
        type_check: bool = False,
        symtab_ir_only: bool = False,
        no_cgen: bool = False,
        skip_native_engine: bool = False,
        cancel_token: Any = None;
}

impl CompileOptions {
    def with_skip_native_engine(skip: bool = True) -> CompileOptions {
        return CompileOptions(
            minimal=self.minimal,
            type_check=self.type_check,
            symtab_ir_only=self.symtab_ir_only,
            no_cgen=self.no_cgen,
            skip_native_engine=skip,
            cancel_token=self.cancel_token
        );
    }
}


# Default options instance for convenience
glob DEFAULT_OPTIONS = CompileOptions();
