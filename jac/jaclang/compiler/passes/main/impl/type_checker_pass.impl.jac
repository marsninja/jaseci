"""Handle the special variable reference node."""

impl TypeCheckPass.exit_special_var_ref(
    self: TypeCheckPass, nd: uni.SpecialVarRef
) -> None {
    self.evaluator.get_type_of_expression(nd);
}

"""Handle name nodes to ensure symbol resolution for all variable references."""
impl TypeCheckPass.exit_name(self: TypeCheckPass, nd: uni.Name) -> None {
    # Skip if already resolved or if part of a construct that handles its own resolution
    if nd.sym is None {
        self.evaluator.get_type_of_expression(nd);
    }
}

"""Handle the edge reference trailer node."""
impl TypeCheckPass.exit_edge_ref_trailer(
    self: TypeCheckPass, nd: uni.EdgeRefTrailer
) -> None {
    for chain in nd.chain {
        if isinstance(chain, uni.FilterCompr) {
            self.evaluator.get_type_of_expression(chain);
        }
    }
}

"""Handle the formatted value node."""
impl TypeCheckPass.exit_formatted_value(
    self: TypeCheckPass, nd: uni.FormattedValue
) -> None {
    self.evaluator.get_type_of_expression(nd.format_part);
}

"""Handle the return statement node."""
impl TypeCheckPass.exit_return_stmt(self: TypeCheckPass, nd: uni.ReturnStmt) -> None {
    returning_type = self.evaluator._convert_to_instance(self.evaluator.get_none_type());
    if nd.expr {
        returning_type = self.evaluator.get_type_of_expression(nd.expr);
    }
    if (fn := self.evaluator._get_enclosing_function(nd)) {
        # Check if return type annotation is missing.
        has_annotation = (
            isinstance(fn.signature, uni.FuncSignature)
            and fn.signature.return_type is not None
        );
        # If returning a non-None value but no annotation, require one.
        # `return None` and bare `return` don't need an annotation.
        # Skip for nested/inline functions (lambdas, IIFEs, closures).
        is_toplevel_fn = isinstance(
            fn.parent, (uni.Module, uni.Archetype, uni.Enum, uni.ImplDef)
        );
        if (
            nd.expr
            and not has_annotation
            and not isinstance(nd.expr, uni.Null)
            and is_toplevel_fn
        ) {
            self.log_error(
                "Return type annotation required when function returns a value", nd
            );
            return;
        }
        fn_type = self.evaluator.get_type_of_ability(fn);
        return_type = self.evaluator._convert_to_instance(fn_type.return_type);
        if not self.evaluator.assign_type(returning_type, return_type) {
            self.log_error(
                f"Cannot return {returning_type}, expected {fn_type.return_type}", nd
            );
        }
    }
}

"""Handle the edge operation reference node."""
impl TypeCheckPass.exit_filter_compr(self: TypeCheckPass, nd: uni.FilterCompr) -> None {
    self.evaluator.get_type_of_expression(nd);
}

"""Handle the function call node."""
impl TypeCheckPass.exit_func_call(self: TypeCheckPass, nd: uni.FuncCall) -> None {
    self.evaluator.get_type_of_expression(nd);
}

"""Handle the binary expression node."""
impl TypeCheckPass.exit_binary_expr(self: TypeCheckPass, nd: uni.BinaryExpr) -> None {
    self.evaluator.get_type_of_expression(nd);
}

"""Enter a boolean expression - set up narrowing scope for AND expressions."""
impl TypeCheckPass.enter_bool_expr(self: TypeCheckPass, nd: uni.BoolExpr) -> None {
    import from jaclang.jac0core.constant { Tokens as Tok }
    # For AND expressions, push a narrowing scope
    if nd.op.name == Tok.KW_AND {
        self.evaluator.push_narrowing_scope();
        # Pre-process conditions to add narrowings BEFORE children are evaluated
        for val in nd.values {
            self.evaluator.process_condition(val);
        }
    }
}

"""Exit a boolean expression - clean up narrowing scope."""
impl TypeCheckPass.exit_bool_expr(self: TypeCheckPass, nd: uni.BoolExpr) -> None {
    import from jaclang.jac0core.constant { Tokens as Tok }
    # Pop the narrowing scope for AND expressions
    if nd.op.name == Tok.KW_AND {
        self.evaluator.pop_narrowing_scope();
    }
}

"""Enter an if statement - set up narrowing scope for the if body."""
impl TypeCheckPass.enter_if_stmt(self: TypeCheckPass, nd: uni.IfStmt) -> None {
    # Push a narrowing scope for the if body
    self.evaluator.push_narrowing_scope();
    # Process the condition to add narrowings
    self.evaluator.process_condition(nd.condition);
}

"""Exit an if statement - clean up narrowing scope."""
impl TypeCheckPass.exit_if_stmt(self: TypeCheckPass, nd: uni.IfStmt) -> None {
    self.evaluator.pop_narrowing_scope();
}

"""Handle the atom trailer node."""
impl TypeCheckPass.exit_atom_trailer(self: TypeCheckPass, nd: uni.AtomTrailer) -> None {
    self.evaluator.get_type_of_expression(nd);
}

"""Pyright: Checker.visitAssignment(node: AssignmentNode): boolean."""
impl TypeCheckPass.exit_assignment(self: TypeCheckPass, nd: uni.Assignment) -> None {
    import from jaclang.compiler.type_system { types }
    import from jaclang.jac0core.constant { Tokens as Tok }
    if ((len(nd.target) == 1) and (nd.value is not None)) {
        target = nd.target[0];
        # For assignment targets, use the declared symbol type (not the
        # narrowed type). Narrowing reflects the *current* value; the
        # variable's declared type determines what can be assigned to it.
        if isinstance(target, uni.Name) and target.sym {
            left_type = self.evaluator.get_type_of_symbol(target.sym);
            # Cache the type on the Name node for hover info
            target.type = left_type;
        } elif isinstance(target, (uni.TupleVal, uni.ListVal)) {
            # Tuple/list unpacking: (px, py) = p; or [a, b] = lst;
            # Individual element types are inferred by _eval_unpacking_names.
            # Skip whole-expression assign_type check since the LHS container
            # type (tuple/list) is not directly comparable to the RHS iterable.
            self._eval_unpacking_names(target);
            right_type = self.evaluator.get_type_of_expression(nd.value);
            # Check that the RHS is iterable for destructuring
            if not isinstance(right_type, types.UnknownType) {
                iter_result = self.evaluator.get_type_of_magic_method_call(
                    right_type, "__iter__", [], nd.value
                );
                if iter_result is None {
                    self.log_error(f"Cannot unpack non-iterable {right_type}", nd);
                }
            }
            return;
        } else {
            left_type = self.evaluator.get_type_of_expression(target);
        }
        right_type = self.evaluator.get_type_of_expression(nd.value);
        # Check augmented assignment operator validity (+=, -=, etc.)
        if nd.aug_op and isinstance(nd.aug_op, uni.Token) {
            AUG_OP_TO_MAGIC: dict[str, str] = {
                Tok.ADD_EQ: "__iadd__",
                Tok.SUB_EQ: "__isub__",
                Tok.MUL_EQ: "__imul__",
                Tok.DIV_EQ: "__itruediv__",
                Tok.FLOOR_DIV_EQ: "__ifloordiv__",
                Tok.MOD_EQ: "__imod__",
                Tok.STAR_POW_EQ: "__ipow__",
                Tok.BW_AND_EQ: "__iand__",
                Tok.BW_OR_EQ: "__ior__",
                Tok.BW_XOR_EQ: "__ixor__",
                Tok.LSHIFT_EQ: "__ilshift__",
                Tok.RSHIFT_EQ: "__irshift__",
                Tok.MATMUL_EQ: "__imatmul__"
            };
            # Also map to the regular binary magic method as fallback
            AUG_OP_TO_BINARY: dict[str, str] = {
                Tok.ADD_EQ: "__add__",
                Tok.SUB_EQ: "__sub__",
                Tok.MUL_EQ: "__mul__",
                Tok.DIV_EQ: "__truediv__",
                Tok.FLOOR_DIV_EQ: "__floordiv__",
                Tok.MOD_EQ: "__mod__",
                Tok.STAR_POW_EQ: "__pow__",
                Tok.BW_AND_EQ: "__and__",
                Tok.BW_OR_EQ: "__or__",
                Tok.BW_XOR_EQ: "__xor__",
                Tok.LSHIFT_EQ: "__lshift__",
                Tok.RSHIFT_EQ: "__rshift__",
                Tok.MATMUL_EQ: "__matmul__"
            };
            if (
                nd.aug_op.name in AUG_OP_TO_MAGIC
                and not isinstance(left_type, types.UnknownType)
                and not isinstance(right_type, types.UnknownType)
            ) {
                imethod = AUG_OP_TO_MAGIC[nd.aug_op.name];
                method = AUG_OP_TO_BINARY[nd.aug_op.name];
                # Try in-place method first, then regular binary method
                result = self.evaluator.get_type_of_magic_method_call(
                    left_type, imethod, [nd.value], None
                );
                if result is None {
                    result = self.evaluator.get_type_of_magic_method_call(
                        left_type, method, [nd.value], None
                    );
                }
                if result is None {
                    self.log_error(
                        f"Operator {nd.aug_op.value} not supported for "
                        f"types {left_type} and {right_type}",
                        nd
                    );
                }
            }
            return;
        }
        if not self.evaluator.assign_type(right_type, left_type) {
            self.log_error(f"Cannot assign {right_type} to {left_type}");
        }
    } else {
        # Handle multi-target assignments: set type on each target for hover
        for target in nd.target {
            if isinstance(target, uni.Name) and target.sym {
                target.type = self.evaluator.get_type_of_symbol(target.sym);
            } elif isinstance(target, (uni.TupleVal, uni.ListVal)) {
                self._eval_unpacking_names(target);
            } else {
                self.evaluator.get_type_of_expression(target);
            }
        }
    }
}

"""Exit an import node."""
impl TypeCheckPass.exit_import(self: TypeCheckPass, nd: uni.Import) -> None {
    if nd.from_loc {
        self.evaluator.get_type_of_module(nd.from_loc);
        for item in nd.items {
            if isinstance(item, uni.ModuleItem) {
                self.evaluator.get_type_of_module_item(item);
            }
        }
    } else {
        for item in nd.items {
            if isinstance(item, uni.ModulePath) {
                self.evaluator.get_type_of_module(item);
            }
        }
    }
}

"""Enter an ability node."""
impl TypeCheckPass.enter_ability(self: TypeCheckPass, nd: uni.Ability) -> None {
    import from jaclang.compiler.type_system { types as jtypes }
    for decor in (nd.decorators or []) {
        ty = self.evaluator.get_type_of_expression(decor);
        if (isinstance(ty, jtypes.ClassType) and ty.is_builtin('staticmethod')) {
            nd.is_static = True;
            break;
        }
    }
}

"""Exit an ability node - ensure parameter type annotations are evaluated and check return completeness."""
impl TypeCheckPass.exit_ability(self: TypeCheckPass, nd: uni.Ability) -> None {
    import from jaclang.compiler.type_system { types }
    # For abilities with ImplDef body (stubs linked to impl files), the original declaration's
    # type annotation Name nodes are orphaned (not in the traversal tree). We need to explicitly
    # process them to enable hover/go-to-definition on the declaration file.
    if isinstance(nd.body, uni.ImplDef) {
        ability_start_line = nd.loc.first_line;
        ability_end_line = nd.loc.last_line;
        # Find orphaned Name nodes in type annotations at this ability's location
        if module := nd.find_parent_of_type(uni.Module) {
            for mod_nd in module._in_mod_nodes {
                if (
                    isinstance(mod_nd, uni.Name)
                    and mod_nd.sym is None
                    and ability_start_line <= mod_nd.loc.first_line <= ability_end_line
                    and isinstance(mod_nd.parent, uni.SubTag)
                ) {  # SubTag is the type annotation wrapper
                    self.evaluator.get_type_of_expression(mod_nd);
                }
            }
        }
        # The ImplDef body is not in the Ability's kid list, so it's not traversed by the pass.
        # We need to explicitly traverse the ImplDef body to evaluate types for hover/go-to-def.
        self.traverse(nd.body);
    }
    # Check for missing return statements on non-None return type functions
    if (
        isinstance(nd.signature, uni.FuncSignature)
        and nd.signature.return_type is not None
        and not isinstance(nd.body, uni.ImplDef)
        and isinstance(nd.body, list)
        and len(nd.body) > 0
        and not nd.is_abstract
    ) {
        # Skip @overload decorated functions (stubs with no real body)
        is_overload = False;
        for decor in (nd.decorators or []) {
            if isinstance(decor, uni.Name) and decor.value == "overload" {
                is_overload = True;
                break;
            }
        }
        # Skip generator functions (contain yield) — they don't need explicit return
        is_generator = len(nd.get_all_sub_nodes(uni.YieldExpr)) > 0;
        if not is_overload and not is_generator {
            ret_type = self.evaluator.get_type_of_expression(nd.signature.return_type);
            ret_inst = self.evaluator._convert_to_instance(ret_type);
            none_type = self.evaluator._convert_to_instance(
                self.evaluator.get_none_type()
            );
            if not self.evaluator.assign_type(none_type, ret_inst) {
                if not self._body_always_returns(nd.body) {
                    self.log_error(
                        f"Function '{nd.name_spec.sym_name}' declared return type "
                        f"{ret_type} but may implicitly return None",
                        nd
                    );
                }
            }
        }
    }
}

"""Check if a code block always returns a value on all paths."""
impl TypeCheckPass._body_always_returns(
    self: TypeCheckPass, body: list[uni.CodeBlockStmt]
) -> bool {
    for stmt in reversed(body) {
        if isinstance(stmt, uni.ReturnStmt) {
            return True;
        }
        if isinstance(stmt, uni.IfStmt) {
            if_returns = self._body_always_returns(list(stmt.body));
            else_returns = False;
            if isinstance(stmt.else_body, uni.ElseIf) {
                else_returns = self._body_always_returns(list(stmt.else_body.body));
                if not else_returns {
                    continue;
                }
                if stmt.else_body.else_body {
                    if isinstance(stmt.else_body.else_body, uni.ElseStmt) {
                        else_returns = self._body_always_returns(
                            list(stmt.else_body.else_body.body)
                        );
                    } elif isinstance(stmt.else_body.else_body, uni.ElseIf) {
                        else_returns = self._body_always_returns(
                            [stmt.else_body.else_body]
                        );
                    }
                } else {
                    else_returns = False;
                }
            } elif isinstance(stmt.else_body, uni.ElseStmt) {
                else_returns = self._body_always_returns(list(stmt.else_body.body));
            }
            if if_returns and else_returns {
                return True;
            }
        }
        if isinstance(stmt, uni.MatchStmt) {
            # Match statement always returns if all cases return.
            # This handles both explicit wildcard (case _:) and exhaustive
            # union coverage (case A() + case B() covering A|B).
            if stmt.cases {
                all_cases_return = True;
                for case in stmt.cases {
                    if not self._body_always_returns(list(case.body)) {
                        all_cases_return = False;
                        break;
                    }
                }
                if all_cases_return {
                    return True;
                }
            }
        }
        if isinstance(stmt, uni.SwitchStmt) {
            if stmt.cases {
                has_default = False;
                all_cases_return = True;
                for case in stmt.cases {
                    if case.pattern is None {
                        has_default = True;
                    }
                    if not self._body_always_returns(list(case.body)) {
                        all_cases_return = False;
                    }
                }
                if has_default and all_cases_return {
                    return True;
                }
            }
        }
        if isinstance(stmt, uni.WithStmt) {
            if self._body_always_returns(list(stmt.body)) {
                return True;
            }
        }
        if isinstance(stmt, uni.TryStmt) {
            try_returns = self._body_always_returns(list(stmt.body));
            if try_returns {
                if not stmt.excepts or len(stmt.excepts) == 0 {
                    return True;
                }
                all_excepts_return = True;
                for exc in stmt.excepts {
                    if not self._body_always_returns(list(exc.body)) {
                        all_excepts_return = False;
                        break;
                    }
                }
                if all_excepts_return {
                    return True;
                }
            }
        }
        if isinstance(stmt, uni.RaiseStmt) {
            return True;
        }
    }
    return False;
}

"""Exit a type alias node."""
impl TypeCheckPass.exit_type_alias(self: TypeCheckPass, nd: uni.TypeAlias) -> None { }

"""Exit an archetype node - traverse ImplDef body if present."""
impl TypeCheckPass.exit_archetype(self: TypeCheckPass, nd: uni.Archetype) -> None {
    self.evaluator.get_type_of_class(nd);
    if isinstance(nd.body, uni.ImplDef) {
        self.traverse(nd.body);
    }
}

"""Exit an enum node - build enum type eagerly and traverse ImplDef body if present."""
impl TypeCheckPass.exit_enum(self: TypeCheckPass, nd: uni.Enum) -> None {
    self.evaluator.get_type_of_enum(nd);
    if isinstance(nd.body, uni.ImplDef) {
        self.traverse(nd.body);
    }
}

impl TypeCheckPass._insert_builtin_symbols(self: TypeCheckPass) -> None {
    if (self.ir_in == self.evaluator.builtins_module) {
        return;
    }
    if (self.ir_in.parent_scope is not None) {
        self.log_info('Builtins module is already bound, skipping.');
        return;
    }
    self.ir_in.parent_scope = self.evaluator.builtins_module;
}

"""Add a diagnostic message to the pass."""
impl TypeCheckPass._add_diagnostic(
    self: TypeCheckPass, nd: uni.UniNode, message: str, warning: bool
) -> None {
    if warning {
        self.log_warning(message, nd);
    } else {
        self.log_error(message, nd);
    }
}

"""Initialize the checker pass."""
impl TypeCheckPass.before_pass(self: TypeCheckPass) -> None {
    self.evaluator = self.prog.get_type_evaluator();
    self.evaluator.diagnostic_callback = self._add_diagnostic;
    self._insert_builtin_symbols();
    self.evaluator._narrowing_cache = {};
}

"""Set type on function/method parameters for hover info."""
impl TypeCheckPass.exit_param_var(self: TypeCheckPass, nd: uni.ParamVar) -> None {
    if (sym := nd.sym) {
        nd.type = self.evaluator.get_type_of_symbol(sym);
    }
}

"""Set type on class fields (has vars) for hover info."""
impl TypeCheckPass.exit_has_var(self: TypeCheckPass, nd: uni.HasVar) -> None {
    if (sym := nd.sym) {
        nd.type = self.evaluator.get_type_of_symbol(sym);
    }
}

"""Set type on for loop iteration variable and check iterability."""
impl TypeCheckPass.exit_in_for_stmt(self: TypeCheckPass, nd: uni.InForStmt) -> None {
    import from jaclang.compiler.type_system { types }
    # Cache type on the iteration target (e.g., 'coord' in 'for coord in p')
    if isinstance(nd.target, uni.Name) {
        self.evaluator.get_type_of_expression(nd.target);
    } elif isinstance(nd.target, (uni.TupleVal, uni.ListVal)) {
        self._eval_unpacking_names(nd.target);
    }
    # Check that the collection is iterable
    collection_type = self.evaluator.get_type_of_expression(nd.collection);
    if not isinstance(collection_type, types.UnknownType) {
        # Enum classes are iterable via EnumMeta.__iter__ which is not
        # modeled in the type system, so skip the check for enum classes.
        is_enum = (
            isinstance(collection_type, types.ClassType)
            and collection_type.is_enum_class()
        );
        if not is_enum {
            iter_result = self.evaluator.get_type_of_magic_method_call(
                collection_type, "__iter__", [], nd.collection
            );
            if iter_result is None {
                self.log_error(
                    f"Type {collection_type} is not iterable (no __iter__ method)", nd
                );
            }
        }
    }
}

"""Type-check raise statements — ensure raised value is an exception."""
impl TypeCheckPass.exit_raise_stmt(self: TypeCheckPass, nd: uni.RaiseStmt) -> None {
    import from jaclang.compiler.type_system { types }
    if nd.cause {
        cause_type = self.evaluator.get_type_of_expression(nd.cause);
        if isinstance(cause_type, types.ClassType)
        and not isinstance(cause_type, types.UnknownType) {
            is_exception = False;
            for cls in cause_type.shared.mro {
                if isinstance(cls, types.ClassType)
                and (cls.is_builtin("BaseException") or cls.is_builtin("Exception")) {
                    is_exception = True;
                    break;
                }
            }
            if not is_exception {
                self.log_error(
                    f"Cannot raise {cause_type} (not an exception type)", nd
                );
            }
        }
    }
}

"""Type-check with statements — verify context manager protocol (__enter__ and __exit__)."""
impl TypeCheckPass.exit_with_stmt(self: TypeCheckPass, nd: uni.WithStmt) -> None {
    import from jaclang.compiler.type_system { types }
    for item in nd.exprs {
        expr_type = self.evaluator.get_type_of_expression(item.expr);
        if not isinstance(expr_type, types.UnknownType) {
            enter_result = self.evaluator.get_type_of_magic_method_call(
                expr_type, "__enter__", [], item.expr
            );
            if enter_result is None {
                self.log_error(
                    f"Type {expr_type} cannot be used in 'with' statement "
                    f"(no __enter__ method)",
                    nd
                );
            } else {
                # Check __exit__ method
                exit_result = self.evaluator.get_type_of_magic_method_call(
                    expr_type, "__exit__", [], item.expr
                );
                if exit_result is None {
                    self.log_error(
                        f"Type {expr_type} cannot be used in 'with' statement "
                        f"(no __exit__ method)",
                        nd
                    );
                }
                # Bind alias type from __enter__ return type
                if item.alias and isinstance(item.alias, uni.Name) and item.alias.sym {
                    item.alias.type = enter_result;
                }
            }
        }
    }
}

"""Type-check while statement conditions."""
impl TypeCheckPass.exit_while_stmt(self: TypeCheckPass, nd: uni.WhileStmt) -> None {
    self.evaluator.get_type_of_expression(nd.condition);
}

"""Type-check assert statement conditions and error messages."""
impl TypeCheckPass.exit_assert_stmt(self: TypeCheckPass, nd: uni.AssertStmt) -> None {
    self.evaluator.get_type_of_expression(nd.condition);
    if nd.error_msg {
        self.evaluator.get_type_of_expression(nd.error_msg);
    }
}

"""Type-check delete statement targets."""
impl TypeCheckPass.exit_delete_stmt(self: TypeCheckPass, nd: uni.DeleteStmt) -> None {
    self.evaluator.get_type_of_expression(nd.target);
}

"""Type-check visit statement targets — target must be a node type."""
impl TypeCheckPass.exit_visit_stmt(self: TypeCheckPass, nd: uni.VisitStmt) -> None {
    import from jaclang.compiler.type_system { types }
    target_type = self.evaluator.get_type_of_expression(nd.target);
    # Visit target must be a node type (or list/collection of nodes)
    if not isinstance(target_type, types.UnknownType)
    and not target_type.is_any_type() {
        is_valid_target = False;
        if isinstance(target_type, types.ClassType) {
            is_valid_target = (
                target_type.is_node_type()
                or (
                    target_type.is_builtin()
                    and target_type.shared.class_name in ("list", "tuple", "set")
                )
            );
        }
        if not is_valid_target {
            self.log_error(f"Visit target must be a node type, got {target_type}", nd);
        }
    }
}

"""Type-check report statement expressions."""
impl TypeCheckPass.exit_report_stmt(self: TypeCheckPass, nd: uni.ReportStmt) -> None {
    self.evaluator.get_type_of_expression(nd.expr);
}

"""Evaluate types for each Name in a tuple/list unpacking pattern."""
impl TypeCheckPass._eval_unpacking_names(
    self: TypeCheckPass, container: uni.Expr
) -> None {
    if isinstance(container, (uni.TupleVal, uni.ListVal)) {
        for val in container.values {
            if isinstance(val, uni.Name) {
                self.evaluator.get_type_of_expression(val);
            }
        }
    }
}
