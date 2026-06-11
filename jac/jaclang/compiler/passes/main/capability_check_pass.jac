"""Capability / portability authority (One Owner Per Analysis, Phase 9).

ONE home for "can this construct ride this pathway" facts:

- `module_native_compat(mod)` derives `Module.gen.native_compat` (the
  auto-promotion eligibility fact) from a declarative disqualifier table
  instead of a hand-maintained visitor scan. `CapabilityCheckPass` stamps
  it at the tail of the front-end schedule.
- `PortabilityWarnPass` (check-extras schedule) owns the JS-idiom
  portability warnings (W6001-W6004): JS globals, JS-idiomatic methods,
  JS keywords used as identifiers, and JS property access. Warnings fire
  in ALL contexts (server, client, native) because Jac idioms are the
  preferred style everywhere - the ES backend translates Jac idioms to
  their JS equivalents.

Both shells consume the same declarative tables below; growing either
axis (a new disqualifier, a new JS-ism) is a table edit, not a new scan.
"""
import jaclang.jac0core.unitree as uni;
import from jaclang.jac0core.passes.transform { Transform }
import from jaclang.jac0core.diagnostics { W6001, W6002, W6003, W6004 }

# Statement / expression forms whose PRESENCE disqualifies a module from
# native auto-promotion (no native lowering exists for them).
glob NATIVE_DISQUALIFIER_NODES: tuple = (
         uni.VisitStmt,
         uni.DisengageStmt,
         uni.ReportStmt,
         uni.YieldExpr,
         uni.EdgeOpRef,
         uni.DisconnectOp,
         uni.TypedCtxBlock,
         uni.LambdaExpr,
         uni.PyInlineCode,
         uni.ClientBlock,
         uni.ServerBlock,

     );

"""Whether a module is eligible for native auto-promotion: it must have a
`with entry` block and contain none of the disqualifying constructs (no
OSP archetypes, no async or event abilities, none of the node forms in
NATIVE_DISQUALIFIER_NODES)."""
def module_native_compat(mod: uni.Module) -> bool;

"""Stamps `Module.gen.native_compat` from the declarative capability
table. Scheduled once at the tail of the front-end schedule (the slot the
deleted UniTreeEnrichPass occupied)."""
obj CapabilityCheckPass(Transform[uni.Module, uni.Module]) {
    has ir_in: uni.Module,
        prog: any,
        cancel_token: any = None;

    def postinit -> None;
    def transform(ir_in: uni.Module) -> uni.Module;
}

"""Portability warnings (W6001-W6004) over the analyzed tree. Scheduled
in the check-extras schedule (`jac check`); diagnostic-only."""
obj PortabilityWarnPass(Transform[uni.Module, uni.Module]) {
    has ir_in: uni.Module,
        prog: any,
        cancel_token: any = None;

    def postinit -> None;
    def transform(ir_in: uni.Module) -> uni.Module;
    def _check_js_globals(mod: uni.Module) -> None;
    def _check_js_methods(mod: uni.Module) -> None;
    def _check_js_keywords(mod: uni.Module) -> None;
    def _check_js_properties(mod: uni.Module) -> None;
}
