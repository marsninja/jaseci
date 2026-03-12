"""Type cache pass implementation."""
import jaclang.jac0core.unitree as uni;

glob _PRIMITIVES: set[str] = {"int","float","bool","str","bytes","i8","u8","i16","u16","i32","u32","i64","u64","f32","f64",},
     _COLLECTIONS: set[str] = {"list","dict","set","frozenset","tuple"};

impl TypeCachePass.init(ir_in: uni.Module, prog: Any, cancel_token: Any = None) -> None {
    super.init(ir_in, prog, cancel_token);
}

impl TypeCachePass.before_pass -> None {
    module = self.ir_in;

    # Phase 1: Resolve type names on all expressions that already have a type
    for expr_nd in self.get_all_sub_nodes(module, uni.Expr, brute_force=True) {
        if expr_nd.type is not None and expr_nd.resolved_type_name is None {
            expr_nd.resolved_type_name = self._extract_type_name(expr_nd.type);
        }
    }

    # Phase 2: Resolve type info on all symbols via scope tree
    if isinstance(module, uni.UniScopeNode) {
        self._resolve_symbol_types(module);
    }
}

"""Build a structured JacType from a type annotation AST node.

Recursively walks the annotation once and produces a JacType tree.
"""
impl TypeCachePass._build_jac_type(nd: uni.UniNode) -> uni.JacType {
    TK = uni.TypeKind;
    JT = uni.JacType;
    jt = self._build_jac_type_inner(nd);
    # Stamp jac_type on every intermediate Expr node so _resolve_jac_type's
    # fast path works even when called on sub-expressions of a type annotation.
    # Skip UNKNOWN to let the backend fallback handle unrecognized nodes.
    if isinstance(nd, uni.Expr) and jt.kind != TK.UNKNOWN {
        nd.jac_type = jt;
    }
    return jt;
}

"""Inner recursive builder — returns JacType without side effects."""
impl TypeCachePass._build_jac_type_inner(nd: uni.UniNode) -> uni.JacType {
    TK = uni.TypeKind;
    JT = uni.JacType;

    if nd is None {
        return JT(kind=TK.UNKNOWN, name="");
    }

    # Null literal: `-> None` return type annotation
    if isinstance(nd, uni.Null) {
        return JT(kind=TK.NONE, name="None");
    }

    # Simple name: int, str, MyStruct, etc.
    if isinstance(nd, (uni.Name, uni.BuiltinType)) {
        name = nd.value;
        if name == "None" {
            return JT(kind=TK.NONE, name="None");
        }
        if name in _PRIMITIVES {
            return JT(kind=TK.PRIMITIVE, name=name);
        }
        # Could be struct, enum, or unknown — mark as STRUCT (backends can refine)
        return JT(kind=TK.STRUCT, name=name);
    }

    # Union type: T | None or T1 | T2
    if isinstance(nd, uni.BinaryExpr) {
        op_val = getattr(nd.op, 'value', '');
        if op_val == "|" {
            left_jt = self._build_jac_type(nd.left);
            right_jt = self._build_jac_type(nd.right);
            # T | None → Optional
            if right_jt.kind == TK.NONE {
                left_jt.is_optional = True;
                return JT(
                    kind=TK.OPTIONAL,
                    name=left_jt.name,
                    element_type=left_jt,
                    is_optional=True
                );
            }
            if left_jt.kind == TK.NONE {
                right_jt.is_optional = True;
                return JT(
                    kind=TK.OPTIONAL,
                    name=right_jt.name,
                    element_type=right_jt,
                    is_optional=True
                );
            }
            # T1 | T2 → Union
            return JT(kind=TK.UNION, name="union", members=[left_jt, right_jt]);
        }
    }

    # Parameterized type: list[T], dict[K,V], set[T], tuple[T1,T2], Callable[...]
    if isinstance(nd, uni.AtomTrailer) {
        target = nd.target;
        right = nd.right;
        target_name: (str | None) = None;
        if isinstance(target, (uni.Name, uni.BuiltinType)) {
            target_name = target.value;
        }
        if target_name is None {
            return JT(kind=TK.UNKNOWN, name="");
        }

        # Extract type parameters from index slices
        slices: list = [];
        if isinstance(right, uni.IndexSlice) {
            slices = right.slices or [];
        }

        # list[T] / frozenset[T]
        if target_name in ("list", "frozenset") {
            elem_jt = JT(kind=TK.UNKNOWN, name="");
            if slices {
                s = slices[0];
                inner = s.start if (s?.start and s.start) else s;
                elem_jt = self._build_jac_type(inner);
            }
            return JT(kind=TK.LIST, name=target_name, element_type=elem_jt);
        }

        # set[T]
        if target_name == "set" {
            elem_jt = JT(kind=TK.UNKNOWN, name="");
            if slices {
                s = slices[0];
                inner = s.start if (s?.start and s.start) else s;
                elem_jt = self._build_jac_type(inner);
            }
            return JT(kind=TK.SET, name="set", element_type=elem_jt);
        }

        # dict[K, V]
        if target_name == "dict" {
            key_jt = JT(kind=TK.UNKNOWN, name="");
            val_jt = JT(kind=TK.UNKNOWN, name="");
            if slices {
                key_nd: (uni.UniNode | None) = None;
                val_nd: (uni.UniNode | None) = None;
                # Case 1: Single slice with TupleVal: dict[(K, V)]
                if len(slices) == 1
                and slices[0]?.start
                and isinstance(slices[0].start, uni.TupleVal) {
                    tuple_val = slices[0].start;
                    if tuple_val.values and len(tuple_val.values) >= 2 {
                        key_nd = tuple_val.values[0];
                        val_nd = tuple_val.values[1];
                    }
                    # Case 2: Two separate slices: dict[K, V]
                } elif len(slices) >= 2 {
                    key_nd = slices[0];
                    val_nd = slices[1];
                    if key_nd?.start and key_nd.start is not None {
                        key_nd = key_nd.start;
                    }
                    if val_nd?.start and val_nd.start is not None {
                        val_nd = val_nd.start;
                    }
                    # Case 3: Single slice with start/stop: dict[K:V]
                } elif len(slices) == 1 and slices[0]?.start {
                    key_nd = slices[0].start;
                    if slices[0]?.stop {
                        val_nd = slices[0].stop;
                    }
                }
                if key_nd is not None {
                    key_jt = self._build_jac_type(key_nd);
                }
                if val_nd is not None {
                    val_jt = self._build_jac_type(val_nd);
                }
            }
            return JT(kind=TK.DICT, name="dict", key_type=key_jt, value_type=val_jt);
        }

        # tuple[T1, T2, ...]
        if target_name == "tuple" {
            member_types: list[uni.JacType] = [];
            for s in slices {
                # TupleVal: tuple[(int, int)] parses as single slice with TupleVal
                if s?.start and s.start and isinstance(s.start, uni.TupleVal) {
                    for tv in s.start.values {
                        member_types.append(self._build_jac_type(tv));
                    }
                } else {
                    inner = s.start if (s?.start and s.start) else s;
                    member_types.append(self._build_jac_type(inner));
                }
            }
            return JT(kind=TK.TUPLE, name="tuple", members=member_types);
        }

        # Callable[[P1, P2], Ret] or callable[P1, P2, Ret]
        if target_name in ("Callable", "callable") {
            param_types: list[uni.JacType] = [];
            ret_jt: (uni.JacType | None) = None;
            if slices {
                # Last slice is return type, rest are params
                for (i, s) in enumerate(slices) {
                    inner = s.start if (s?.start and s.start) else s;
                    if i == len(slices) - 1 {
                        ret_jt = self._build_jac_type(inner);
                    } else {
                        param_types.append(self._build_jac_type(inner));
                    }
                }
            }
            return JT(
                kind=TK.CALLABLE,
                name="Callable",
                params=param_types,
                return_type=ret_jt
            );
        }

        # Parameterized struct: MyStruct[T] — treat as STRUCT with element_type
        if target_name not in _COLLECTIONS {
            elem_jt: (uni.JacType | None) = None;
            if slices {
                s = slices[0];
                inner = s.start if (s?.start and s.start) else s;
                elem_jt = self._build_jac_type(inner);
            }
            return JT(kind=TK.STRUCT, name=target_name, element_type=elem_jt);
        }
    }

    # FuncSignature → Callable type
    if isinstance(nd, uni.FuncSignature) {
        param_types: list[uni.JacType] = [];
        for p in nd.get_parameters() {
            if p.type_tag and p.type_tag.tag {
                param_types.append(self._build_jac_type(p.type_tag.tag));
            } else {
                param_types.append(JT(kind=TK.UNKNOWN, name=""));
            }
        }
        ret_jt: (uni.JacType | None) = None;
        if nd.return_type {
            ret_jt = self._build_jac_type(nd.return_type);
        }
        return JT(
            kind=TK.CALLABLE, name="Callable", params=param_types, return_type=ret_jt
        );
    }

    return JT(kind=TK.UNKNOWN, name="");
}

"""Resolve type name, type_node, and jac_type on every Symbol in a scope, recursively.

Walks the scope tree (kid_scope hierarchy) and follows each Symbol's
declaration chain: Symbol -> decl -> name_of -> type_tag to extract the
type annotation, making it directly accessible on the Symbol.
"""
impl TypeCachePass._resolve_symbol_types(scope: uni.UniScopeNode) -> None {
    for (_, sym) in scope.names_in_scope.items() {
        if sym.jac_type is not None {
            continue;
        }
        decl = sym.decl;
        if decl is None {
            continue;
        }
        declaring_nd = decl.name_of;
        if declaring_nd is None {
            continue;
        }
        # HasVar, ParamVar, Assignment all extend AstTypedVarNode
        if isinstance(declaring_nd, uni.AstTypedVarNode)
        and declaring_nd.type_tag
        and declaring_nd.type_tag.tag {
            tag = declaring_nd.type_tag.tag;
            sym.type_node = tag;
            sym.resolved_type_name = self._type_name_from_annotation(tag);
            jt = self._build_jac_type(tag);
            sym.jac_type = jt;
            # Also set on the annotation expr so _resolve_jac_type can use it
            if isinstance(tag, uni.Expr) {
                tag.jac_type = jt;
            }
        }
        # For 'let x: T = ...', name_of is the Name target; Assignment is its parent
        elif isinstance(declaring_nd, uni.Name)
        and declaring_nd?.parent
        and isinstance(declaring_nd.parent, uni.Assignment)
        and declaring_nd.parent.type_tag
        and declaring_nd.parent.type_tag.tag {
            tag = declaring_nd.parent.type_tag.tag;
            sym.type_node = tag;
            sym.resolved_type_name = self._type_name_from_annotation(tag);
            jt = self._build_jac_type(tag);
            sym.jac_type = jt;
            if isinstance(tag, uni.Expr) {
                tag.jac_type = jt;
            }
        }
        # Archetype declarations — the symbol IS the type
        elif isinstance(declaring_nd, uni.Archetype) {
            sym.resolved_type_name = declaring_nd.name.value
                if declaring_nd.name
                else None;
            sym.jac_type = uni.JacType(
                kind=uni.TypeKind.STRUCT,
                name=declaring_nd.name.value if declaring_nd.name else ""
            );
        }
        # Enum declarations
        elif isinstance(declaring_nd, uni.Enum) {
            sym.resolved_type_name = declaring_nd.name.value
                if declaring_nd.name
                else None;
            sym.jac_type = uni.JacType(
                kind=uni.TypeKind.ENUM,
                name=declaring_nd.name.value if declaring_nd.name else ""
            );
        }
        # Ability declarations
        elif isinstance(declaring_nd, uni.Ability) {
            sym.resolved_type_name = 'Callable';
            # Build callable type from signature if available
            sig = declaring_nd.signature;
            if sig is not None and isinstance(sig, uni.FuncSignature) {
                sym.jac_type = self._build_jac_type(sig);
                # Set jac_type on return type annotation expr
                if sig.return_type and isinstance(sig.return_type, uni.Expr) {
                    sig.return_type.jac_type = self._build_jac_type(sig.return_type);
                }
                # Set jac_type on param type annotation exprs
                for p in sig.get_parameters() {
                    if p.type_tag
                    and p.type_tag.tag
                    and isinstance(p.type_tag.tag, uni.Expr) {
                        p.type_tag.tag.jac_type = self._build_jac_type(p.type_tag.tag);
                    }
                }
            } else {
                sym.jac_type = uni.JacType(kind=uni.TypeKind.CALLABLE, name="Callable");
            }
        }
    }
    # Recurse into child scopes
    for kid in scope.kid_scope {
        self._resolve_symbol_types(kid);
    }
}

"""Extract type name string from a TypeBase object."""
impl TypeCachePass._extract_type_name(type_obj: Any) -> (str | None) {
    if type_obj is None {
        return None;
    }
    if type_obj?.shared and type_obj.shared and hasattr(type_obj.shared, 'class_name') {
        return type_obj.shared.class_name;
    }
    if type_obj?.__class__ and type_obj.__class__.__name__ == 'FunctionType' {
        return 'Callable';
    }
    name = getattr(type_obj, 'name', None);
    if isinstance(name, str) {
        return name;
    }
    return None;
}

"""Extract type name from a type annotation AST nd."""
impl TypeCachePass._type_name_from_annotation(nd: uni.UniNode) -> (str | None) {
    if isinstance(nd, (uni.Name, uni.BuiltinType)) {
        return nd.value;
    }
    if isinstance(nd, uni.AtomTrailer) {
        if isinstance(nd.target, (uni.Name, uni.BuiltinType)) {
            return nd.target.value;
        }
    }
    # Handle union types like T | None — return the non-None side
    if isinstance(nd, uni.BinaryExpr) {
        if isinstance(nd.right, uni.BuiltinType) and nd.right.value == 'None' {
            return self._type_name_from_annotation(nd.left);
        }
        if isinstance(nd.left, uni.BuiltinType) and nd.left.value == 'None' {
            return self._type_name_from_annotation(nd.right);
        }
    }
    return None;
}
