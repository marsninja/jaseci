"""Handle the special variable reference node."""

impl TypeCheckPass.exit_special_var_ref(
    self: TypeCheckPass, <>node: uni.SpecialVarRef
) -> None {
    self.evaluator.get_type_of_expression(<>node);
}

"""Handle name nodes to ensure symbol resolution for all variable references."""
impl TypeCheckPass.exit_name(self: TypeCheckPass, <>node: uni.Name) -> None {
    # Skip if already resolved or if part of a construct that handles its own resolution
    if <>node.sym is None {
        self.evaluator.get_type_of_expression(<>node);
    }
}

"""Handle the edge reference trailer node."""
impl TypeCheckPass.exit_edge_ref_trailer(
    self: TypeCheckPass, <>node: uni.EdgeRefTrailer
) -> None {
    for chain in <>node.chain {
        if isinstance(chain, uni.FilterCompr) {
            self.evaluator.get_type_of_expression(chain);
        }
    }
}

"""Handle the formatted value node."""
impl TypeCheckPass.exit_formatted_value(
    self: TypeCheckPass, <>node: uni.FormattedValue
) -> None {
    self.evaluator.get_type_of_expression(<>node.format_part);
}

"""Handle the return statement node."""
impl TypeCheckPass.exit_return_stmt(
    self: TypeCheckPass, <>node: uni.ReturnStmt
) -> None {
    returning_type = self.evaluator._convert_to_instance(
        self.evaluator.get_none_type()
    );
    if <>node.expr {
        returning_type = self.evaluator.get_type_of_expression(<>node.expr);
    }
    if (fn := self.evaluator._get_enclosing_function(<>node)) {
        fn_type = self.evaluator.get_type_of_ability(fn);
        return_type = self.evaluator._convert_to_instance(fn_type.return_type);
        if not self.evaluator.assign_type(returning_type, return_type) {
            self.log_error(
                f"Cannot return {returning_type}, expected {fn_type.return_type}",
                <>node
            );
        }
    }
}

"""Handle the edge operation reference node."""
impl TypeCheckPass.exit_filter_compr(
    self: TypeCheckPass, <>node: uni.FilterCompr
) -> None {
    self.evaluator.get_type_of_expression(<>node);
}

"""Handle the function call node."""
impl TypeCheckPass.exit_func_call(self: TypeCheckPass, <>node: uni.FuncCall) -> None {
    self.evaluator.get_type_of_expression(<>node);
}

"""Handle the binary expression node."""
impl TypeCheckPass.exit_binary_expr(
    self: TypeCheckPass, <>node: uni.BinaryExpr
) -> None {
    self.evaluator.get_type_of_expression(<>node);
}

"""Handle the atom trailer node."""
impl TypeCheckPass.exit_atom_trailer(
    self: TypeCheckPass, <>node: uni.AtomTrailer
) -> None {
    self.evaluator.get_type_of_expression(<>node);
}

"""Pyright: Checker.visitAssignment(node: AssignmentNode): boolean."""
impl TypeCheckPass.exit_assignment(self: TypeCheckPass, <>node: uni.Assignment) -> None {
    if ((len(<>node.target) == 1) and (<>node.value is not None)) {
        left_type = self.evaluator.get_type_of_expression(<>node.target[0]);
        right_type = self.evaluator.get_type_of_expression(<>node.value);
        if not self.evaluator.assign_type(right_type, left_type) {
            self.log_error(f"Cannot assign {right_type} to {left_type}");
        }
    } else {
        ;
    }
}

"""Exit an import node."""
impl TypeCheckPass.exit_import(self: TypeCheckPass, <>node: uni.Import) -> None {
    if <>node.from_loc {
        self.evaluator.get_type_of_module(<>node.from_loc);
        for item in <>node.items {
            if isinstance(item, uni.ModuleItem) {
                self.evaluator.get_type_of_module_item(item);
            }
        }
    } else {
        for item in <>node.items {
            if isinstance(item, uni.ModulePath) {
                self.evaluator.get_type_of_module(item);
            }
        }
    }
}

"""Enter an ability node."""
impl TypeCheckPass.enter_ability(self: TypeCheckPass, <>node: uni.Ability) -> None {
    import from jaclang.compiler.type_system { types as jtypes }
    for decor in (<>node.decorators or []) {
        ty = self.evaluator.get_type_of_expression(decor);
        if (isinstance(ty, jtypes.ClassType) and ty.is_builtin('staticmethod')) {
            <>node.is_static = True;
            break;
        }
    }
}

"""Exit an ability node - ensure parameter type annotations are evaluated."""
impl TypeCheckPass.exit_ability(self: TypeCheckPass, <>node: uni.Ability) -> None {
    # Clean up any early-return narrowing contexts that were pushed.
    while self.early_return_narrowing_depth > 0 {
        if self.evaluator.narrowing_stack {
            self.evaluator.narrowing_stack.pop();
        }
        self.early_return_narrowing_depth -= 1;
    }
    # For abilities with ImplDef body (stubs linked to impl files), the original declaration's
    # type annotation Name nodes are orphaned (not in the traversal tree). We need to explicitly
    # process them to enable hover/go-to-definition on the declaration file.
    if isinstance(<>node.body, uni.ImplDef) {
        ability_start_line = <>node.loc.first_line;
        ability_end_line = <>node.loc.last_line;
        # Find orphaned Name nodes in type annotations at this ability's location
        if module := <>node.find_parent_of_type(uni.Module) {
            for nd in module._in_mod_nodes {
                if (
                    isinstance(nd, uni.Name)
                    and nd.sym is None
                    and ability_start_line <= nd.loc.first_line <= ability_end_line
                    and isinstance(nd.parent, uni.SubTag)
                ) {  # SubTag is the type annotation wrapper

                    self.evaluator.get_type_of_expression(nd);
                }
            }
        }
        # The ImplDef body is not in the Ability's kid list, so it's not traversed by the pass.
        # We need to explicitly traverse the ImplDef body to evaluate types for hover/go-to-def.
        self._traverse_impl_body(<>node.body);
    }
}

"""Traverse an ImplDef body and evaluate types for all expression nodes."""
impl TypeCheckPass._traverse_impl_body(
    self: TypeCheckPass, impl_def: uni.ImplDef
) -> None {
    # Recursively traverse all nodes in the ImplDef body and call type evaluation
    def traverse_node(node: uni.UniNode) -> None {
        if node is None {
            return;
        }

        # Call the appropriate exit handler for expression nodes
        if isinstance(node, uni.SpecialVarRef) {
            self.evaluator.get_type_of_expression(node);
        } elif isinstance(node, uni.AtomTrailer) {
            self.evaluator.get_type_of_expression(node);
        } elif isinstance(node, uni.FuncCall) {
            self.evaluator.get_type_of_expression(node);
        } elif isinstance(node, uni.BinaryExpr) {
            self.evaluator.get_type_of_expression(node);
        } elif isinstance(node, uni.Assignment) {
            # Handle assignments - evaluate both sides
            for target in node.target {
                self.evaluator.get_type_of_expression(target);
            }
            if node.value {
                self.evaluator.get_type_of_expression(node.value);
            }
        } elif isinstance(node, uni.ReturnStmt) {
            if node.expr {
                self.evaluator.get_type_of_expression(node.expr);
            }
        } elif isinstance(node, uni.Name) {
            if node.sym is None {
                self.evaluator.get_type_of_expression(node);
            }
        }

        # Recursively traverse children
        if node?.kid {
            for child in node.kid {
                if child {
                    traverse_node(child);
                }
            }
        }
    }
    # Start traversing from the ImplDef's children
    for child in impl_def.kid {
        if child {
            traverse_node(child);
        }
    }
}

"""Exit an impl def node - ensure parameter type annotations are evaluated."""
impl TypeCheckPass.exit_impl_def(self: TypeCheckPass, <>node: uni.ImplDef) -> None {
    # For impl blocks, process type annotation Name nodes to enable hover/go-to-definition.
    # Directly traverse the FuncSignature's params to find type annotations.
    if isinstance(<>node.spec, uni.FuncSignature) {
        sig = <>node.spec;
        all_params = (
            list(sig.posonly_params) + list(sig.params) + (
                [sig.varargs] if sig.varargs else []
            ) + list(sig.kwonlyargs) + ([sig.kwargs] if sig.kwargs else [])
        );
        for param in all_params {
            # Process the type annotation - access via tag directly
            if param.type_tag and isinstance(param.type_tag, uni.SubTag) {
                tag = param.type_tag.tag;
                if isinstance(tag, uni.Name) {
                    # Try to resolve the symbol from the module scope if not already resolved
                    if tag.sym is None {
                        # Try to find the symbol from all loaded modules
                        symbol: uni.Symbol | None = None;
                        # Check all modules in the program hub
                        for (path, mod) in self.prog.mod.hub.items() {
                            if symbol := mod.lookup(
                                tag.value, deep=True, incl_inner_scope=True
                            ) {
                                break;
                            }
                        }
                        if symbol {
                            symbol = self.evaluator.resolve_imported_symbols(symbol);
                            symbol.add_use(tag);
                            tag.sym = symbol;
                            if symbol.decl and symbol.decl.name_of {
                                tag.name_of = symbol.decl.name_of;
                            }
                        }
                    }
                    # Also call evaluator for full type processing
                    self.evaluator.get_type_of_expression(tag);
                }
            }
        }
        # Also process return type annotation
        if sig.return_type and isinstance(sig.return_type, uni.Name) {
            self.evaluator.get_type_of_expression(sig.return_type);
        }
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
    self: TypeCheckPass, <>node: uni.UniNode, message: str, warning: bool
) -> None {
    if warning {
        self.log_warning(message, <>node);
    } else {
        self.log_error(message, <>node);
    }
}

"""Initialize the checker pass."""
impl TypeCheckPass.before_pass(self: TypeCheckPass) -> None {
    self.evaluator = self.prog.get_type_evaluator();
    self.evaluator.diagnostic_callback = self._add_diagnostic;
    self._insert_builtin_symbols();
    self.early_return_narrowing_depth: int = 0;
}

# -------------------------------------------------------------------------
# Type narrowing: enter/exit handlers for if/elif/else
# -------------------------------------------------------------------------
"""Push TRUE-branch narrowing context when entering an if-statement."""
impl TypeCheckPass.enter_if_stmt(self: TypeCheckPass, <>node: uni.IfStmt) -> None {
    preds = self.evaluator.extract_narrowing_predicates(<>node.condition);
    ctx: dict[str, Any] = {};
    for pred in preds {
        ctx[pred[0]] = pred[1];  # symbol_name -> true_branch_type
    }
    self.evaluator.narrowing_stack.append(ctx);
    # Store predicates on the node for else/elif to compute false-branch types.
    <>node._narrowing_preds = preds;
}

"""Pop narrowing context when exiting an if-statement.

If the if-body always returns (early return) and has no else_body,
push FALSE-branch narrowing for subsequent sibling statements.
"""
impl TypeCheckPass.exit_if_stmt(self: TypeCheckPass, <>node: uni.IfStmt) -> None {
    # Pop the TRUE-branch context (if else_body consumed it via enter_else_*,
    # the stack may already be clean; guard with length check).
    if (self.evaluator.narrowing_stack and not <>node.else_body) {
        self.evaluator.narrowing_stack.pop();
    }
    # Early-return detection: if no else_body and body ends with return/raise,
    # push FALSE-branch narrowing for subsequent siblings.
    if (
        <>node.else_body is None
        and <>node.body
        and isinstance(<>node.body[-1], (uni.ReturnStmt, uni.RaiseStmt))
        and <>node?._narrowing_preds
    ) {
        preds = <>node._narrowing_preds;
        ctx: dict[str, Any] = {};
        for pred in preds {
            ctx[pred[0]] = pred[2];  # symbol_name -> false_branch_type
        }
        if ctx {
            self.evaluator.narrowing_stack.append(ctx);
            self.early_return_narrowing_depth += 1;
        }
    }
}

"""Swap from parent's TRUE-branch to ElseIf's TRUE-branch narrowing."""
impl TypeCheckPass.enter_else_if(self: TypeCheckPass, <>node: uni.ElseIf) -> None {
    # Pop parent IfStmt's TRUE-branch context.
    if self.evaluator.narrowing_stack {
        self.evaluator.narrowing_stack.pop();
    }
    # Extract this elif's own condition predicates and push its TRUE context.
    preds = self.evaluator.extract_narrowing_predicates(<>node.condition);
    ctx: dict[str, Any] = {};
    for pred in preds {
        ctx[pred[0]] = pred[1];  # elif's true_branch_type
    }
    self.evaluator.narrowing_stack.append(ctx);
    <>node._narrowing_preds = preds;
}

"""Pop ElseIf's narrowing context."""
impl TypeCheckPass.exit_else_if(self: TypeCheckPass, <>node: uni.ElseIf) -> None {
    # If ElseIf has no else_body, we need to pop its context.
    if (self.evaluator.narrowing_stack and not <>node.else_body) {
        self.evaluator.narrowing_stack.pop();
    }
}

"""Swap to FALSE-branch narrowing when entering else block."""
impl TypeCheckPass.enter_else_stmt(self: TypeCheckPass, <>node: uni.ElseStmt) -> None {
    # Pop the preceding TRUE/elif context.
    if self.evaluator.narrowing_stack {
        self.evaluator.narrowing_stack.pop();
    }
    # Walk up through IfStmt/ElseIf chain to collect all excluded types,
    # then compute what remains for the final else branch.
    ctx: dict[str, Any] = {};
    # The parent of ElseStmt is an IfStmt or ElseIf.
    parent_if = <>node.parent;
    # Collect all narrowing predicates from the if/elif chain.
    all_excluded: dict[str, list] = {};
    current = parent_if;
    while (current is not None and isinstance(current, uni.IfStmt)) {
        if current?._narrowing_preds {
            for pred in current._narrowing_preds {
                sym_name = pred[0];
                true_type = pred[1];
                if sym_name not in all_excluded {
                    all_excluded[sym_name] = [];
                }
                all_excluded[sym_name].append(true_type);
            }
        }
        # Walk up to parent IfStmt if current is an ElseIf.
        if isinstance(current, uni.ElseIf) {
            current = current.parent;
            if isinstance(current, uni.IfStmt) {
                continue;
            }
        }
        break;
    }
    # Compute remaining types by excluding all true-branch types from the original.
    for (sym_name, excluded_types) in all_excluded.items() {
        # Get the original declared type.
        orig_type = None;
        if scope := <>node.find_parent_of_type(uni.UniScopeNode) {
            import from jaclang.compiler.type_system { type_utils }
            if sym := type_utils.lookup_symtab(
                scope, sym_name, self.evaluator.builtins_module
            ) {
                orig_type = self.evaluator.get_type_of_symbol(sym);
            }
        }
        if orig_type is not None {
            remaining = orig_type;
            for excl in excluded_types {
                remaining = self.evaluator.exclude_type_from_union(remaining, excl);
            }
            ctx[sym_name] = remaining;
        }
    }
    self.evaluator.narrowing_stack.append(ctx);
}

"""Pop FALSE-branch narrowing context when exiting else block."""
impl TypeCheckPass.exit_else_stmt(self: TypeCheckPass, <>node: uni.ElseStmt) -> None {
    if self.evaluator.narrowing_stack {
        self.evaluator.narrowing_stack.pop();
    }
}
