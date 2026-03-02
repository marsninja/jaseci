"""Type Annotation Pass implementation."""
import jaclang.jac0core.unitree as uni;
import from jaclang.jac0core.passes { UniPass }
import from typing { Any }

glob PRIMITIVE_NAMES: set = {"int","float","str","bool","bytes","None"};

impl TypeAnnotationPass.init(
    ir_in: uni.Module, prog: Any, cancel_token: Any = None
) -> None {
    super.init(ir_in, prog, cancel_token);
}

impl TypeAnnotationPass.before_pass -> None {
    # Read existing type evaluator without creating one — avoids
    # loading type stubs into the program hub as a side effect.
    self.te = getattr(self.prog, 'type_evaluator', None);
}

"""Convert a TypeBase object to a (type_name, category, elem_type) triple.

Uses type().__name__ checks instead of isinstance to avoid importing from
jaclang.compiler.type_system.types, which would trigger cascading compilation
of internal modules during user code compilation.
"""
impl TypeAnnotationPass._type_base_to_triple(tb: Any) -> tuple {
    if tb is None {
        return ("unknown", "unknown", None);
    }
    tb_cls = type(tb).__name__;
    if tb_cls == "UnionType" {
        names: list = [];
        non_none_triple: tuple = ("unknown", "unknown", None);
        for member in tb.types {
            mt = self._type_base_to_triple(member);
            names.append(mt[0]);
            if mt[0] != "None" {
                non_none_triple = mt;
            }
        }
        type_name = "|".join(names);
        return (type_name, "union", non_none_triple[2]);
    }
    if tb_cls == "EnumMemberType" {
        return (str(tb), "enum", None);
    }
    if tb_cls == "FunctionType" {
        return ("callable", "callable", None);
    }
    if tb_cls == "ClassType" {
        cname = tb.shared.class_name if tb.shared else str(tb);
        if cname in PRIMITIVE_NAMES {
            return (cname, "primitive", None);
        }
        # Check for generic builtins: list, dict, set, tuple
        type_args = tb.private.type_args
            if (tb.private and tb.private.type_args)
            else None;
        if cname == "list" {
            if type_args and len(type_args) > 0 {
                elem_triple = self._type_base_to_triple(type_args[0]);
                return ("list[" + elem_triple[0] + "]", "list", elem_triple[0]);
            }
            return ("list", "list", None);
        }
        if cname == "dict" {
            if type_args and len(type_args) >= 2 {
                key_triple = self._type_base_to_triple(type_args[0]);
                val_triple = self._type_base_to_triple(type_args[1]);
                elem_spec = key_triple[0] + ":" + val_triple[0];
                return (
                    "dict[" + key_triple[0] + "," + val_triple[0] + "]",
                    "dict",
                    elem_spec
                );
            }
            return ("dict", "dict", None);
        }
        if cname == "set" {
            if type_args and len(type_args) > 0 {
                elem_triple = self._type_base_to_triple(type_args[0]);
                return ("set[" + elem_triple[0] + "]", "set", elem_triple[0]);
            }
            return ("set", "set", None);
        }
        if cname == "tuple" {
            if type_args and len(type_args) > 0 {
                elem_names = [self._type_base_to_triple(a)[0] for a in type_args];
                return (
                    "tuple[" + ",".join(elem_names) + "]",
                    "tuple",
                    ",".join(elem_names)
                );
            }
            return ("tuple", "tuple", None);
        }
        # Check for node/edge/walker/object archetypes
        if tb?.is_node_type and tb.is_node_type() {
            return (cname, "node", None);
        }
        if tb?.is_edge_type and tb.is_edge_type() {
            return (cname, "edge", None);
        }
        if tb?.is_enum_class and tb.is_enum_class() {
            return (cname, "enum", None);
        }
        # Generic struct/object
        return (cname, "struct", None);
    }
    # Fallback for unknown type categories
    return (str(tb), "unknown", None);
}

"""Resolve a type annotation AST node to a (type_name, category, elem_type) triple."""
impl TypeAnnotationPass._resolve_type_annotation(
    type_expr: (uni.UniNode | None)
) -> tuple {
    if type_expr is None {
        return ("unknown", "unknown", None);
    }
    # Primary: use type checker result on the node
    if isinstance(type_expr, uni.Expr) and type_expr.type is not None {
        return self._type_base_to_triple(type_expr.type);
    }
    # Secondary: invoke the type evaluator
    if self.te is not None and isinstance(type_expr, uni.Expr) {
        try {
            tb = self.te.get_type_of_expression(type_expr);
            if tb is not None {
                return self._type_base_to_triple(tb);
            }
        } except Exception {
            ;
        }
    }
    # Tertiary: extract type name directly from AST structure
    return self._resolve_from_ast(type_expr);
}

"""Resolve a type name from AST structure without the type system."""
impl TypeAnnotationPass._resolve_from_ast(type_expr: uni.UniNode) -> tuple {
    # Name node → its value
    if isinstance(type_expr, uni.Name) {
        name = type_expr.value;
        if name in PRIMITIVE_NAMES {
            return (name, "primitive", None);
        }
        return (name, "struct", None);
    }
    # BinaryExpr with | → union (e.g., int|None)
    if isinstance(type_expr, uni.BinaryExpr) {
        op_val = getattr(type_expr.op, 'value', '');
        if op_val == "|" {
            left_t = self._resolve_from_ast(type_expr.left);
            right_t = self._resolve_from_ast(type_expr.right);
            uname = left_t[0] + "|" + right_t[0];
            non_none = left_t if left_t[0] != "None" else right_t;
            return (uname, "union", non_none[2]);
        }
    }
    # AtomTrailer for generic types: list[T], dict[K,V], set[T], tuple[...]
    if isinstance(type_expr, uni.AtomTrailer) and not type_expr.is_attr {
        target_name: (str | None) = None;
        if isinstance(type_expr.target, uni.Name) {
            target_name = type_expr.target.value;
        } elif hasattr(type_expr.target, 'value')
        and isinstance(getattr(type_expr.target, 'value', None), str) {
            target_name = type_expr.target.value;
        }
        if target_name is not None and type_expr?.right and type_expr.right?.slices {
            slices = type_expr.right.slices or [];
            if target_name == "list" and slices {
                elem = slices[0];
                if elem?.start and elem.start is not None {
                    elem = elem.start;
                }
                et = self._resolve_from_ast(elem);
                return ("list[" + et[0] + "]", "list", et[0]);
            }
            if target_name == "dict" {
                key_node: (object | None) = None;
                val_node: (object | None) = None;
                if len(slices) == 1
                and slices[0]?.start
                and isinstance(slices[0].start, uni.TupleVal) {
                    tv = slices[0].start;
                    if tv.values and len(tv.values) >= 2 {
                        key_node = tv.values[0];
                        val_node = tv.values[1];
                    }
                } elif len(slices) >= 2 {
                    key_node = slices[0];
                    val_node = slices[1];
                    if key_node?.start and key_node.start is not None {
                        key_node = key_node.start;
                    }
                    if val_node?.start and val_node.start is not None {
                        val_node = val_node.start;
                    }
                }
                if key_node is not None and val_node is not None {
                    kt = self._resolve_from_ast(key_node);
                    vt = self._resolve_from_ast(val_node);
                    return (
                        "dict[" + kt[0] + "," + vt[0] + "]",
                        "dict",
                        kt[0] + ":" + vt[0]
                    );
                }
            }
            if target_name == "set" and slices {
                elem = slices[0];
                if elem?.start and elem.start is not None {
                    elem = elem.start;
                }
                et = self._resolve_from_ast(elem);
                return ("set[" + et[0] + "]", "set", et[0]);
            }
            if target_name == "tuple" and slices {
                parts: list = [];
                for s in slices {
                    if s?.start and isinstance(s.start, uni.TupleVal) {
                        for tv in s.start.values {
                            t = self._resolve_from_ast(tv);
                            parts.append(t[0]);
                        }
                    } elif s?.start and s.start is not None {
                        t = self._resolve_from_ast(s.start);
                        parts.append(t[0]);
                    } else {
                        t = self._resolve_from_ast(s);
                        parts.append(t[0]);
                    }
                }
                return ("tuple[" + ",".join(parts) + "]", "tuple", ",".join(parts));
            }
        }
    }
    # BuiltinType or other node with .value
    if hasattr(type_expr, 'value')
    and isinstance(getattr(type_expr, 'value', None), str) {
        name = type_expr.value;
        if name in PRIMITIVE_NAMES {
            return (name, "primitive", None);
        }
        return (name, "struct", None);
    }
    return ("unknown", "unknown", None);
}

"""Annotate parameter variable type."""
impl TypeAnnotationPass.exit_param_var(nd: uni.ParamVar) -> None {
    if nd.type_tag and nd.type_tag.tag {
        (tname, tcat, telem) = self._resolve_type_annotation(nd.type_tag.tag);
        nd.type_tag.tag.gen.resolved_type = tname;
        nd.type_tag.tag.gen.resolved_type_category = tcat;
        nd.type_tag.tag.gen.resolved_elem_type = telem;
    }
}

"""Annotate has-variable (archetype field) type."""
impl TypeAnnotationPass.exit_has_var(nd: uni.HasVar) -> None {
    if nd.type_tag and nd.type_tag.tag {
        (tname, tcat, telem) = self._resolve_type_annotation(nd.type_tag.tag);
        nd.type_tag.tag.gen.resolved_type = tname;
        nd.type_tag.tag.gen.resolved_type_category = tcat;
        nd.type_tag.tag.gen.resolved_elem_type = telem;
    }
}

"""Annotate function return type."""
impl TypeAnnotationPass.exit_func_signature(nd: uni.FuncSignature) -> None {
    if nd.return_type {
        (tname, tcat, telem) = self._resolve_type_annotation(nd.return_type);
        nd.return_type.gen.resolved_type = tname;
        nd.return_type.gen.resolved_type_category = tcat;
        nd.return_type.gen.resolved_elem_type = telem;
    }
}

"""Annotate assignment target type."""
impl TypeAnnotationPass.exit_assignment(nd: uni.Assignment) -> None {
    if nd.type_tag and nd.type_tag.tag {
        (tname, tcat, telem) = self._resolve_type_annotation(nd.type_tag.tag);
        nd.type_tag.tag.gen.resolved_type = tname;
        nd.type_tag.tag.gen.resolved_type_category = tcat;
        nd.type_tag.tag.gen.resolved_elem_type = telem;
    }
}

"""Annotate for-loop iterator element type."""
impl TypeAnnotationPass.exit_in_for_stmt(nd: uni.InForStmt) -> None {
    # Resolve collection type to infer element type
    if nd.collection {
        (tname, tcat, telem) = self._resolve_type_annotation(nd.collection);
        nd.collection.gen.resolved_type = tname;
        nd.collection.gen.resolved_type_category = tcat;
        nd.collection.gen.resolved_elem_type = telem;
    }
}

"""Annotate list comprehension element type."""
impl TypeAnnotationPass.exit_list_compr(nd: uni.ListCompr) -> None {
    if isinstance(nd, uni.Expr) and nd.type is not None {
        (tname, tcat, telem) = self._type_base_to_triple(nd.type);
        nd.gen.resolved_type = tname;
        nd.gen.resolved_type_category = tcat;
        nd.gen.resolved_elem_type = telem;
    }
}

"""Annotate set comprehension element type."""
impl TypeAnnotationPass.exit_set_compr(nd: uni.SetCompr) -> None {
    if isinstance(nd, uni.Expr) and nd.type is not None {
        (tname, tcat, telem) = self._type_base_to_triple(nd.type);
        nd.gen.resolved_type = tname;
        nd.gen.resolved_type_category = tcat;
        nd.gen.resolved_elem_type = telem;
    }
}
