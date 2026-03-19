"""Implementation of UniTreeEnrichPass and _typebase_to_tag()."""
import from typing { TYPE_CHECKING }

with entry {
    if TYPE_CHECKING {
        import from jaclang.compiler.type_system.types {
            TypeBase,
            ClassType,
            NeverType,
            UnknownType,
            AnyType,
            TypeVarType,
            FunctionType,
            ModuleType,
            UnionType,
            OverloadedType,
            EnumMemberType
        }
    }
}

"""Convert a TypeBase to a backend-neutral type tag string.

    Uses JAC_TYPE_REGISTRY names for primitives so the tag maps directly to
    NaIRGenPass.type_map keys. Returns None for types that backends must
    re-derive (user archetypes, generics, unresolved types).
    """
impl _typebase_to_tag(t: Any) -> (str | None) {
    # Guard: no type info available
    if t is None {
        return None;
    }
    # Lazy import JAC_TYPE_REGISTRY for bootstrap safety
    try {
        import from jaclang.compiler.type_registry { JAC_TYPE_REGISTRY }
        _prim_names = {
            e.name
            for e in JAC_TYPE_REGISTRY._entries.values()
            if e.na_type_spec is not None
        };
    } except ImportError {
        # Bootstrap: type_registry not yet compiled
        _prim_names = {"int","float","bool","str","i8","u8","i16","u16","i32","u32","i64","u64","f32","f64"};
    }
    try {
        import from jaclang.compiler.type_system.types {
            ClassType as _ClassType,
            NeverType as _NeverType
        }
        if isinstance(t, _ClassType) {
            if not t.shared {
                return None;
            }
            class_name = t.shared.class_name;
            # Primitive scalars: map directly to type_map keys
            if class_name in _prim_names {
                return class_name;
            }
            # NoneType class (Python None type → void in native)
            if class_name in ("NoneType", "None") {
                return "void";
            }
            # Parameterized collections: build "list[elem]", "dict[k:v]", "set[elem]"
            type_args = (t.private.type_args if t.private else None) or [];
            if class_name == "list" and len(type_args) == 1 {
                elem_tag = _typebase_to_tag(type_args[0]);
                if elem_tag and elem_tag in _prim_names {
                    return f"list[{elem_tag}]";
                }
                return None;
            }
            if class_name == "dict" and len(type_args) >= 2 {
                k_tag = _typebase_to_tag(type_args[0]);
                v_tag = _typebase_to_tag(type_args[1]);
                if k_tag and v_tag and k_tag in _prim_names and v_tag in _prim_names {
                    return f"dict[{k_tag}:{v_tag}]";
                }
                return None;
            }
            if class_name == "set" and len(type_args) == 1 {
                elem_tag = _typebase_to_tag(type_args[0]);
                if elem_tag and elem_tag in _prim_names {
                    return f"set[{elem_tag}]";
                }
                return None;
            }
            # Unparameterized collection or user-defined type: cannot pre-compute
            return None;
        }
        if isinstance(t, _NeverType) {
            return "void";
        }
    } except (ImportError, Exception) {
        return None;
    }
    # All other TypeBase subclasses (Unknown, Any, TypeVar, Function, Module,
    # Union, Overloaded, EnumMember) → None: backends use their own derivation.
    return None;
}


"""Initialize pass state and delegate to UniPass.init."""
impl UniTreeEnrichPass.init(
    ir_in: uni.Module, prog: Any, cancel_token: (Any | None) = None
) -> None {
    super.init(ir_in, prog, cancel_token);
}


"""Initialize state for the native_compat pre-check."""
impl UniTreeEnrichPass.before_pass -> None {
    self._native_has_disqualifier: bool = False;
    self._native_has_entry: bool = False;
}


"""Set backend_type_tag on every Expr from its pre-computed TypeBase."""
impl UniTreeEnrichPass.enter_expr(nd: uni.Expr) -> None {
    if getattr(nd, 'backend_type_tag', None) is None and nd.type is not None {
        nd.backend_type_tag = _typebase_to_tag(nd.type);
    }
}


"""Set js_decl_kind on Name nodes for the ES backend.

    "let"   — this Name node IS the declaration site of its symbol.
    "param" — this Name is a function parameter.
    None    — reference only; no JS declaration needed at this site.
    """
impl UniTreeEnrichPass.enter_name(nd: uni.Name) -> None {
    if getattr(nd, 'js_decl_kind', None) is not None {
        return;  # already set (shouldn't happen, but be safe)

    }
    # Check if this Name is the definition site of its symbol.
    # After SemanticAnalysisPass, name_of points to the declaration node
    # for usages; for declarations, name_of is self.
    if nd.name_of is nd {
        # Check if it's a function parameter (parent chain)
        parent = nd.parent;
        try {
            if isinstance(parent, uni.ParamVar) {
                nd.js_decl_kind = "param";
                return;
            }
        } except Exception {
            pass;
        }
        nd.js_decl_kind = "let";
    }
    # else: nd.name_of is not nd → reference, js_decl_kind stays None
}


# ─── native_compat disqualifying construct detectors ──────────
impl UniTreeEnrichPass.enter_archetype(nd: uni.Archetype) -> None {
    if not self._native_has_disqualifier {
        arch_val = nd.arch_type.value if nd.arch_type else "";
        if arch_val in ("node", "edge", "walker") {
            self._native_has_disqualifier = True;
        }
    }
}

impl UniTreeEnrichPass.enter_ability(nd: uni.Ability) -> None {
    if not self._native_has_disqualifier {
        if nd.is_async or isinstance(nd.signature, uni.EventSignature) {
            self._native_has_disqualifier = True;
        }
    }
}

impl UniTreeEnrichPass.enter_visit_stmt(nd: uni.VisitStmt) -> None {
    self._native_has_disqualifier = True;
}

impl UniTreeEnrichPass.enter_disengage_stmt(nd: uni.DisengageStmt) -> None {
    self._native_has_disqualifier = True;
}

impl UniTreeEnrichPass.enter_report_stmt(nd: uni.ReportStmt) -> None {
    self._native_has_disqualifier = True;
}

impl UniTreeEnrichPass.enter_yield_expr(nd: uni.YieldExpr) -> None {
    self._native_has_disqualifier = True;
}

impl UniTreeEnrichPass.enter_edge_op_ref(nd: uni.EdgeOpRef) -> None {
    self._native_has_disqualifier = True;
}

impl UniTreeEnrichPass.enter_disconnect_op(nd: uni.DisconnectOp) -> None {
    self._native_has_disqualifier = True;
}

impl UniTreeEnrichPass.enter_typed_ctx_block(nd: uni.TypedCtxBlock) -> None {
    self._native_has_disqualifier = True;
}

impl UniTreeEnrichPass.enter_lambda_expr(nd: uni.LambdaExpr) -> None {
    self._native_has_disqualifier = True;
}

impl UniTreeEnrichPass.enter_py_inline_code(nd: uni.PyInlineCode) -> None {
    self._native_has_disqualifier = True;
}

impl UniTreeEnrichPass.enter_client_block(nd: uni.ClientBlock) -> None {
    self._native_has_disqualifier = True;
}

impl UniTreeEnrichPass.enter_server_block(nd: uni.ServerBlock) -> None {
    self._native_has_disqualifier = True;
}

"""Track whether a 'with entry {}' block is present."""
impl UniTreeEnrichPass.enter_module_code(nd: uni.ModuleCode) -> None {
    for k in nd.kid {
        if isinstance(k, uni.Token) and k.value == "entry" {
            self._native_has_entry = True;
            break;
        }
    }
}

"""After the full walk, set gen.native_compat on the module."""
impl UniTreeEnrichPass.exit_module(nd: uni.Module) -> None {
    # A module is native-compatible if it has no disqualifying constructs
    # AND has an entry block. .na.jac files are explicitly native already
    # and don't need the flag (NativeCompatCheckPass skips them).
    nd.gen.native_compat = (
        not self._native_has_disqualifier and self._native_has_entry
    );
}
