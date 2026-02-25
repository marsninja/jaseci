"""Implementation for semantic_analysis_pass constructs."""

impl SemanticAnalysisPass.enter_archetype(
    self: SemanticAnalysisPass, nd: uni.Archetype
) -> None {
    def inform_from_walker(nd: uni.UniNode) -> None {
        for i in nd.get_all_sub_nodes(uni.VisitStmt) + nd.get_all_sub_nodes(
            uni.DisengageStmt
        ) + nd.get_all_sub_nodes(uni.ReportStmt) + nd.get_all_sub_nodes(uni.EdgeOpRef) + nd.get_all_sub_nodes(
            uni.EventSignature
        ) + nd.get_all_sub_nodes(uni.TypedCtxBlock) {
            i.from_walker = True;
        }
    }
    if (nd.arch_type.name == Tok.KW_WALKER) {
        inform_from_walker(nd);
        for i in self.get_all_sub_nodes(nd, uni.Ability) {
            if isinstance(i.body, uni.ImplDef) {
                inform_from_walker(i.body);
            }
        }
    }
    self._check_archetype(nd);
}

"""Check a single archetype for issues with attributes and methods."""
impl SemanticAnalysisPass._check_archetype(
    self: SemanticAnalysisPass, nd: uni.Archetype
) -> None {
    # Warn about 'has' inside 'class' (doesn't auto-generate constructor like obj)
    if (nd.arch_type.name == Tok.KW_CLASS) and isinstance(nd.body, Sequence) {
        for stmnt in nd.body {
            if isinstance(stmnt, uni.ArchHas) {
                self.log_warning(
                    "'has' inside 'class' does not auto-generate a constructor. "
                    "Use 'obj' instead for auto-generated constructors, or define __init__.",
                    node_override=stmnt
                );
                break;  # One warning per class is enough
            }
        }
    }
    if ((nd.arch_type.name != Tok.KW_CLASS) and isinstance(nd.body, Sequence)) {
        found_default_init = False;
        for stmnt in nd.body {
            if not isinstance(stmnt, uni.ArchHas) {
                continue;
            }
            for var in stmnt.vars {
                if ((var.value is not None) or var.defer) {
                    found_default_init = True;
                } elif found_default_init {
                    self.log_error(
                        f"Non default attribute '{var.name.value}' follows default attribute",
                        node_override=var.name
                    );
                    break;
                }
            }
        }
        post_init_vars: list = [];
        postinit_method: (uni.Ability | None) = None;
        for item in nd.body {
            if isinstance(item, uni.ArchHas) {
                for var in item.vars {
                    if var.defer {
                        post_init_vars.append(var);
                    }
                }
            } elif isinstance(item, uni.Ability) {
                if item.is_abstract {
                    continue;
                }
                if (
                    isinstance(item.name_ref, uni.SpecialVarRef)
                    and (item.name_ref.name == Tok.KW_POST_INIT)
                ) {
                    postinit_method = item;
                }
            }
        }
        if ((len(post_init_vars) != 0) and (postinit_method is None)) {
            self.log_error(
                'Missing "postinit" method required by un initialized attribute(s).',
                node_override=post_init_vars[0].name_spec
            );
        }
    }
}

impl SemanticAnalysisPass._update_ctx(
    self: SemanticAnalysisPass, nd: uni.UniNode
) -> None {
    if isinstance(nd, uni.AtomTrailer) {
        self._change_atom_trailer_ctx(nd);
    } elif isinstance(nd, uni.AstSymbolNode) {
        nd.sym_tab.update_py_ctx_for_def(nd);
    } else {
        self.log_error(f"Invalid target for context update: {type(nd).__name__}");
    }
}

impl SemanticAnalysisPass.enter_has_var(
    self: SemanticAnalysisPass, nd: uni.HasVar
) -> None {
    if isinstance(nd.parent, uni.ArchHas) {
        nd.sym_tab.update_py_ctx_for_def(nd);
    } else {
        self.ice('HasVar should be under ArchHas');
    }
}

impl SemanticAnalysisPass.enter_param_var(
    self: SemanticAnalysisPass, nd: uni.ParamVar
) -> None {
    nd.sym_tab.update_py_ctx_for_def(nd);
}

impl SemanticAnalysisPass.enter_assignment(
    self: SemanticAnalysisPass, nd: uni.Assignment
) -> None {
    for target in nd.target {
        self._update_ctx(target);
    }
}

impl SemanticAnalysisPass.enter_in_for_stmt(
    self: SemanticAnalysisPass, nd: uni.InForStmt
) -> None {
    self._update_ctx(nd.target);
}

impl SemanticAnalysisPass.enter_expr_as_item(
    self: SemanticAnalysisPass, nd: uni.ExprAsItem
) -> None {
    if nd.alias {
        self._update_ctx(nd.alias);
    }
}

impl SemanticAnalysisPass.enter_inner_compr(
    self: SemanticAnalysisPass, nd: uni.InnerCompr
) -> None {
    self._update_ctx(nd.target);
}

"""Mark final element in trailer chain as a Store context."""
impl SemanticAnalysisPass._change_atom_trailer_ctx(
    self: SemanticAnalysisPass, nd: uni.AtomTrailer
) -> None {
    last = nd.right;
    if isinstance(last, uni.AtomExpr) {
        last.name_spec.py_ctx_func = ast3.Store;
        if isinstance(last.name_spec, uni.AstSymbolNode) {
            last.name_spec.py_ctx_func = ast3.Store;
        }
    }
}

"""Warn about missing return type annotations on functions."""
impl SemanticAnalysisPass.enter_ability(
    self: SemanticAnalysisPass, nd: uni.Ability
) -> None {
    if (
        isinstance(nd.signature, uni.FuncSignature)
        and nd.signature.return_type is None
        and nd.body is not None
        and not nd.is_abstract
    ) {
        # Skip __init__, postinit, and other special methods
        if isinstance(nd.name_ref, uni.SpecialVarRef) {
            return;
        }
        self.log_warning(
            "Function has no return type annotation. Consider adding '-> Type'.",
            node_override=nd.name_ref or nd
        );
    }
}

"""Warn about potential missing f-string prefix."""
impl SemanticAnalysisPass.exit_string(
    self: SemanticAnalysisPass, nd: uni.String
) -> None {
    val = nd.value;
    # Skip f-strings (already have interpolation)
    if val.startswith("f'") or val.startswith('f"') {
        return;
    }
    # Check for {identifier} patterns that suggest missing f-string prefix
    if re.search(r'\{[a-zA-Z_]\w*\}', val) {
        # Extract first matched name for the message
        m = re.search(r'\{([a-zA-Z_]\w*)\}', val);
        if m {
            var_name = m.group(1);
            self.log_warning(
                f"String contains '{{{var_name}}}' but is not an f-string. Did you mean to add an 'f' prefix?",
                node_override=nd
            );
        }
    }
}

"""Warn when await is used outside an async function."""
impl SemanticAnalysisPass.enter_await_expr(
    self: SemanticAnalysisPass, nd: uni.AwaitExpr
) -> None {
    parent_ability = nd.find_parent_of_type(uni.Ability);
    if parent_ability is not None and not parent_ability.is_async {
        self.log_warning(
            "'await' used outside an 'async' function. Add 'async' keyword: async def ... or async can ...",
            node_override=nd
        );
    }
}

"""Warn when a function returns JsxElement but is missing the 'cl' prefix."""
impl SemanticAnalysisPass.exit_ability(
    self: SemanticAnalysisPass, nd: uni.Ability
) -> None {
    if (
        isinstance(nd.signature, uni.FuncSignature)
        and nd.signature.return_type is not None
        and nd.body is not None
    ) {
        # Check if return type mentions JsxElement
        ret_type = nd.signature.return_type;
        ret_str = getattr(ret_type, 'sym_name', None)
        or str(getattr(ret_type, 'value', ''));
        if ret_str == "JsxElement" and nd.code_context != uni.CodeContext.CLIENT {
            self.log_warning(
                "Function returns 'JsxElement' but is not marked as client code. Add 'cl' prefix: cl def:pub ...",
                node_override=nd.name_ref or nd
            );
        }
    }
}

"""Warn about string literals passed to event handler JSX attributes."""
impl SemanticAnalysisPass.exit_jsx_normal_attribute(
    self: SemanticAnalysisPass, nd: uni.JsxNormalAttribute
) -> None {
    # Check if attribute name starts with 'on' (event handler pattern)
    attr_name = getattr(nd.name, 'value', "");
    if (
        attr_name.startswith("on")
        and len(attr_name) > 2
        and nd.value is not None
        and isinstance(nd.value, uni.String)
    ) {
        self.log_warning(
            f"Event handler '{attr_name}' received a string literal. Use a JSX expression instead: {attr_name}={{...}}",
            node_override=nd
        );
    }
}

"""Warn about wrong type names like 'string' instead of 'str'."""
impl SemanticAnalysisPass.enter_sub_tag(
    self: SemanticAnalysisPass, nd: uni.SubTag
) -> None {
    # Only check type annotation SubTags
    if not isinstance(nd.tag, uni.Expr) {
        return;
    }
    type_map: dict = {
        "string": "str",
        "String": "str",
        "integer": "int",
        "Integer": "int",
        "boolean": "bool",
        "Boolean": "bool",
        "double": "float",
        "Double": "float",
        "float64": "float",
        "int64": "int",
        "char": "str"
    };
    # Check if the type expression is a simple name that matches a wrong type
    if isinstance(nd.tag, uni.AtomExpr) {
        type_name = getattr(nd.tag, 'sym_name', None)
        or str(getattr(nd.tag, 'value', ''));
        if type_name in type_map {
            correct = type_map[type_name];
            self.log_warning(
                f"'{type_name}' is not a built-in type. Did you mean '{correct}'?",
                node_override=nd.tag
            );
        }
    }
}
