"""UniTree IR Enrichment Pass.

Runs after TypeCheckPass and StaticAnalysisPass. Pre-computes backend-neutral
analysis results and stores them on AST nodes so codegen passes are pure
code generation with no re-derivation of type information.

Populates:
  - Expr.backend_type_tag: str | None
      Backend-neutral type tag derived from Expr.type (TypeBase).
      Uses JAC_TYPE_REGISTRY names ("int", "float", "bool", "str", etc.)
      for primitive types. Collection tags use Jac names ("list[int]",
      "dict[str:float]"). None when the type cannot be pre-computed
      (user-defined archetypes, generics, unresolved types).

  - Name.js_decl_kind: str | None
      JavaScript declaration kind hint for the ES backend.
      "let"   — this Name is the declaration site of its symbol.
      "param" — this Name is a function parameter.
      None    — reference only; no JS declaration needed.

  - Module.gen.native_compat: bool
      True when the module has no native-incompatible constructs
      (walker/edge/node archetypes, async, visit/disengage/report,
      yield, lambdas, inline Python, client/server blocks) AND has
      a 'with entry {}' block. Used by NativeCompatCheckPass.

Module-level helper (also importable for unit testing):
  _typebase_to_tag(t: Any) -> str | None
"""
import jaclang.jac0core.unitree as uni;
import from jaclang.jac0core.passes { UniPass }

"""Convert a TypeBase instance to a backend-neutral type tag string.

    Returns a string key compatible with NaIRGenPass.type_map, or None when
    the type cannot be represented as a simple tag (fallback to legacy derivation).

    Tag vocabulary:
      Primitives : "int", "float", "bool", "str", "bytes",
                   "i8", "u8", "i16", "u16", "i32", "u32",
                   "i64", "u64", "f32", "f64"
      Void       : "void"  (NoneType / NeverType)
      Collections: "list[<elem>]", "dict[<key>:<val>]", "set[<elem>]"
      None       : unresolvable / fallback to backend re-derivation
    """
def _typebase_to_tag(t: Any) -> (str | None);

"""Pre-compute backend hints on every Expr and Name node."""
obj UniTreeEnrichPass(UniPass) {
    def init(ir_in: uni.Module, prog: Any, cancel_token: (Any | None) = None) -> None;
    def before_pass -> None;
    # Expr enrichment
    def enter_expr(nd: uni.Expr) -> None;
    # Name enrichment (Name is also an Expr, so enter_name runs after enter_expr)
    def enter_name(nd: uni.Name) -> None;
    # native_compat: disqualifying construct detectors
    def enter_archetype(nd: uni.Archetype) -> None;
    def enter_ability(nd: uni.Ability) -> None;
    def enter_visit_stmt(nd: uni.VisitStmt) -> None;
    def enter_disengage_stmt(nd: uni.DisengageStmt) -> None;
    def enter_report_stmt(nd: uni.ReportStmt) -> None;
    def enter_yield_expr(nd: uni.YieldExpr) -> None;
    def enter_edge_op_ref(nd: uni.EdgeOpRef) -> None;
    def enter_disconnect_op(nd: uni.DisconnectOp) -> None;
    def enter_typed_ctx_block(nd: uni.TypedCtxBlock) -> None;
    def enter_lambda_expr(nd: uni.LambdaExpr) -> None;
    def enter_py_inline_code(nd: uni.PyInlineCode) -> None;
    def enter_client_block(nd: uni.ClientBlock) -> None;
    def enter_server_block(nd: uni.ServerBlock) -> None;
    def enter_module_code(nd: uni.ModuleCode) -> None;
    # Set native_compat on the module after full walk
    def exit_module(nd: uni.Module) -> None;
}
