"""Static analysis pass implementation."""

impl StaticAnalysisPass.init(
    ir_in: uni.Module, prog: Any, cancel_token: Any = None
) -> None {
    super.init(ir_in, prog, cancel_token);
}

"""Run all static analyses after the full tree traversal."""
impl StaticAnalysisPass.after_pass -> None {
    self._checked_scopes: set[int] = set();
    self._check_unused_symbols(self.ir_in);
    self._check_undefined_names(self.ir_in);
    self._check_unreachable_code(self.ir_in);
    self._check_semantic_patterns(self.ir_in);
    self._check_scope_diagnostics(self.ir_in);
    self._check_archetype_semantics(self.ir_in);
    for annex_mod in self.ir_in.impl_mod + self.ir_in.test_mod + self.ir_in.variant_mod {
        self._check_undefined_names(annex_mod);
        self._check_unreachable_code(annex_mod);
        self._check_semantic_patterns(annex_mod);
        self._check_scope_diagnostics(annex_mod);
        self._check_archetype_semantics(annex_mod);
    }
}

"""Walk all scopes and warn on symbols that are defined but never used."""
impl StaticAnalysisPass._check_unused_symbols(scope: uni.UniScopeNode) -> None {
    if id(scope) in self._checked_scopes {
        return;
    }
    self._checked_scopes.add(id(scope));

    for (name, sym) in scope.names_in_scope.items() {
        # Skip imported symbols
        if sym.imported {
            continue;
        }
        # Skip underscore-prefixed names (conventionally unused)
        if name.startswith("_") {
            continue;
        }
        # Skip structural symbol types that are not user variables
        if sym.sym_type in (
            SymbolType.MODULE,
            SymbolType.MOD_VAR,
            SymbolType.IMPL,
            SymbolType.SEM,
            SymbolType.TEST,
            SymbolType.HAS_VAR,
            SymbolType.CONSTRUCTOR,
            SymbolType.ENUM_MEMBER,
            SymbolType.ABILITY,
            SymbolType.METHOD
        ) {
            continue;
        }
        # Skip archetype and enum definitions (they are types, not variables)
        if sym.sym_type in (
            SymbolType.OBJECT_ARCH,
            SymbolType.NODE_ARCH,
            SymbolType.EDGE_ARCH,
            SymbolType.WALKER_ARCH,
            SymbolType.ENUM_ARCH
        ) {
            continue;
        }
        # Skip self/super
        if name in ("self", "super", "init", "postinit") {
            continue;
        }
        # Skip parameters of abstract abilities (no body to use them in)
        if sym.sym_type == SymbolType.VAR and isinstance(scope, uni.Ability) {
            if scope.needs_impl {
                continue;
            }
        }
        # Check unused: defined but never referenced
        if len(sym.uses) == 0 {
            self.emit(W2003, node_override=sym.decl, name=name);
        }
    }
    # Recurse into child scopes
    for kid in scope.kid_scope {
        self._check_unused_symbols(kid);
    }
}

"""Walk all Name nodes and warn if a name reference was never resolved."""
impl StaticAnalysisPass._check_undefined_names(mod: uni.Module) -> None {
    all_names = mod.get_all_sub_nodes(typ=uni.Name, brute_force=True);
    for name_nd in all_names {
        if name_nd.sym {
            continue;
        }
        # Only flag Load context (usage, not definition)
        if name_nd._py_ctx_func != ast3.Load {
            continue;
        }
        # Skip well-known builtins and special names
        import builtins;
        if name_nd.value in dir(builtins)
        or name_nd.value in ("self", "super", "almostEqual") {
            continue;
        }
        # Skip dunder names
        if name_nd.value.startswith("__") and name_nd.value.endswith("__") {
            continue;
        }
        # Skip names that are part of import statements
        if name_nd.find_parent_of_type(uni.Import) is not None {
            continue;
        }
        # Skip names that are part of module paths
        if name_nd.find_parent_of_type(uni.ModulePath) is not None {
            continue;
        }
        self.emit(W2001, node_override=name_nd, name=name_nd.value);
    }
}

"""Detect unreachable code by scanning code blocks for statements after return/break/continue."""
impl StaticAnalysisPass._check_unreachable_code(mod: uni.Module) -> None {
    # Collect all code body containers
    container_types = [
        uni.Ability,
        uni.ImplDef,
        uni.IfStmt,
        uni.ElseStmt,
        uni.ElseIf,
        uni.WhileStmt,
        uni.InForStmt,
        uni.IterForStmt
    ];
    containers: list = [];
    for typ in container_types {
        containers.extend(mod.get_all_sub_nodes(typ=typ, brute_force=True));
    }

    for container in containers {
        body = getattr(container, 'body', None);
        if not body or not isinstance(body, Sequence) {
            continue;
        }
        found_terminator = False;
        for stmt in body {
            if found_terminator {
                # Skip Semi nodes
                if isinstance(stmt, uni.Semi) {
                    continue;
                }
                self.emit(W2002, node_override=stmt);
                break;
            }
            if isinstance(stmt, (uni.ReturnStmt, uni.RaiseStmt)) {
                found_terminator = True;
            }
            if isinstance(stmt, uni.CtrlStmt) {
                found_terminator = True;
            }
        }
    }
}

"""Check semantic patterns: division by zero, None comparison, self-assignment,
f-string without placeholders, redundant boolean comparison, overly broad except,
return in finally, disengage outside walker."""
impl StaticAnalysisPass._check_semantic_patterns(mod: uni.Module) -> None {
    # W2070: division by zero
    for nd in mod.get_all_sub_nodes(typ=uni.BinaryExpr, brute_force=True) {
        if nd.op is not None and isinstance(nd.op, uni.Token) {
            if nd.op.value in ("/", "//", "%") {
                if isinstance(nd.right, uni.Int) and nd.right.value == "0" {
                    self.emit(W2070, node_override=nd);
                } elif isinstance(nd.right, uni.Float) and nd.right.value == "0.0" {
                    self.emit(W2070, node_override=nd);
                }
            }
        }
    }

    # W2058: None comparison with == or !=
    for nd in mod.get_all_sub_nodes(typ=uni.CompareExpr, brute_force=True) {
        for (i, op) in enumerate(nd.ops) {
            if op.value in ("==", "!=") {
                right = nd.rights[i] if i < len(nd.rights) else None;
                left = nd.left if i == 0 else (nd.rights[i - 1] if i > 0 else None);
                if isinstance(right, uni.Null) or isinstance(left, uni.Null) {
                    self.emit(W2058, node_override=nd);
                }
            }
        }
    }

    # W2063: self-assignment (x = x)
    for nd in mod.get_all_sub_nodes(typ=uni.Assignment, brute_force=True) {
        if nd.aug_op is not None or nd.value is None {
            continue;
        }
        if len(nd.target) == 1 {
            target = nd.target[0];
            if isinstance(target, uni.Name) and isinstance(nd.value, uni.Name) {
                if target.value == nd.value.value {
                    self.emit(W2063, node_override=nd, name=target.value);
                }
            }
        }
    }

    # W2074: f-string with no placeholders
    for nd in mod.get_all_sub_nodes(typ=uni.FString, brute_force=True) {
        has_expr = False;
        for part in nd.parts {
            if isinstance(part, uni.FormattedValue) {
                has_expr = True;
                break;
            }
        }
        if not has_expr {
            self.emit(W2074, node_override=nd);
        }
    }

    # W2075: redundant boolean comparison (x == True, x == False)
    for nd in mod.get_all_sub_nodes(typ=uni.CompareExpr, brute_force=True) {
        for (i, op) in enumerate(nd.ops) {
            if op.value in ("==", "!=", "is", "is not") {
                right = nd.rights[i] if i < len(nd.rights) else None;
                if isinstance(right, uni.Bool) {
                    self.emit(W2075, node_override=nd);
                }
            }
        }
    }

    # W1153: float equality comparison
    for nd in mod.get_all_sub_nodes(typ=uni.CompareExpr, brute_force=True) {
        for (i, op) in enumerate(nd.ops) {
            if op.value in ("==", "!=") {
                right = nd.rights[i] if i < len(nd.rights) else None;
                left = nd.left if i == 0 else (nd.rights[i - 1] if i > 0 else None);
                if isinstance(right, uni.Float) or isinstance(left, uni.Float) {
                    # Skip None comparisons (already caught by W2058)
                    if not isinstance(right, uni.Null)
                    and not isinstance(left, uni.Null) {
                        self.emit(W1153, node_override=nd);
                    }
                }
            }
        }
    }

    # E1113: instantiating abstract archetype
    for nd in mod.get_all_sub_nodes(typ=uni.FuncCall, brute_force=True) {
        if isinstance(nd.target, uni.Name) and nd.target.sym is not None {
            base_decl = nd.target.sym.decl;
            if base_decl is not None and hasattr(base_decl, 'name_of') {
                arch = base_decl.name_of
                    if isinstance(base_decl.name_of, uni.Archetype)
                    else None;
                if arch is not None and arch.decorators is not None {
                    for dec in arch.decorators {
                        if isinstance(dec, uni.Name) and dec.value == "abstract" {
                            self.emit(E1113, node_override=nd, name=nd.target.value);
                        }
                    }
                }
            }
        }
    }

    # W2052: overly broad except (catching Exception or BaseException)
    for nd in mod.get_all_sub_nodes(typ=uni.Except, brute_force=True) {
        if nd.ex_type is not None and isinstance(nd.ex_type, uni.Name) {
            if nd.ex_type.value in ("Exception", "BaseException") {
                self.emit(W2052, node_override=nd, type=nd.ex_type.value);
            }
        }
    }

    # E2055: return in finally block
    for nd in mod.get_all_sub_nodes(typ=uni.FinallyStmt, brute_force=True) {
        for stmt in nd.body {
            if isinstance(stmt, uni.ReturnStmt) {
                self.emit(E2055, node_override=stmt);
            }
        }
    }

    # E2083: disengage outside walker
    for nd in mod.get_all_sub_nodes(typ=uni.DisengageStmt, brute_force=True) {
        # Walk up to find if we're inside a walker ability
        in_walker = False;
        parent = nd.parent;
        while parent is not None {
            if isinstance(parent, uni.Archetype) {
                if parent.arch_type is not None
                and isinstance(parent.arch_type, uni.Token)
                and parent.arch_type.value == "walker" {
                    in_walker = True;
                }
                break;
            }
            parent = parent.parent;
        }
        if not in_walker {
            self.emit(E2083, node_override=nd);
        }
    }

    # W2062: dead store — variable assigned then immediately reassigned
    all_assigns = mod.get_all_sub_nodes(typ=uni.Assignment, brute_force=True);
    for nd in all_assigns {
        if nd.aug_op is not None or nd.value is None {
            continue;
        }
        if len(nd.target) != 1 or not isinstance(nd.target[0], uni.Name) {
            continue;
        }
        target_name = nd.target[0].value;
        # Check if the next sibling statement is also an assignment to the same name
        parent = nd.parent;
        if parent is None {
            continue;
        }
        body = getattr(parent, 'body', None);
        if not body or not isinstance(body, Sequence) {
            continue;
        }
        found_current = False;
        for stmt in body {
            if found_current {
                if isinstance(stmt, uni.Semi) {
                    continue;
                }
                if isinstance(stmt, uni.Assignment)
                and stmt.aug_op is None
                and len(stmt.target) == 1
                and isinstance(stmt.target[0], uni.Name)
                and stmt.target[0].value == target_name {
                    self.emit(W2062, node_override=nd, name=target_name);
                }
                break;
            }
            if stmt is nd {
                found_current = True;
            }
        }
    }

    # W2050: function may not return on all paths
    for nd in mod.get_all_sub_nodes(typ=uni.Ability, brute_force=True) {
        # Only check functions with explicit non-None return type
        if nd.signature is None or not isinstance(nd.signature, uni.FuncSignature) {
            continue;
        }
        if nd.signature.return_type is None {
            continue;
        }
        # Skip abstract abilities (no body)
        if nd.is_abstract or nd.body is None {
            continue;
        }
        # Check return type is not None
        ret_type = nd.signature.return_type;
        if isinstance(ret_type, uni.Name) and ret_type.value == "None" {
            continue;
        }
        body = nd.body;
        if not isinstance(body, Sequence) or len(body) == 0 {
            continue;
        }
        # Check if the body always returns
        if not self._body_always_returns(body) {
            func_name = nd.name_ref.value
                if nd.name_ref is not None and isinstance(nd.name_ref, uni.Name)
                else "<anonymous>";
            self.emit(W2050, node_override=nd, name=func_name);
        }
    }
}

"""Check if a body (list of statements) always returns."""
impl StaticAnalysisPass._body_always_returns(body: Sequence) -> bool {
    for stmt in reversed(list(body)) {
        if isinstance(stmt, uni.Semi) {
            continue;
        }
        if isinstance(stmt, uni.ReturnStmt) or isinstance(stmt, uni.RaiseStmt) {
            return True;
        }
        # if/else where both branches return
        if isinstance(stmt, uni.IfStmt) {
            if stmt.else_body is not None {
                if_returns = self._body_always_returns(stmt.body);
                else_returns = False;
                if isinstance(stmt.else_body, uni.ElseStmt) {
                    else_returns = self._body_always_returns(stmt.else_body.body);
                } elif isinstance(stmt.else_body, uni.ElseIf) {
                    else_returns = self._elseif_always_returns(stmt.else_body);
                }
                if if_returns and else_returns {
                    return True;
                }
            }
        }
        return False;
    }
    return False;
}

"""Check if an elif chain always returns."""
impl StaticAnalysisPass._elseif_always_returns(nd: uni.ElseIf) -> bool {
    if_returns = self._body_always_returns(nd.body);
    if not if_returns {
        return False;
    }
    if nd.else_body is None {
        return False;
    }
    if isinstance(nd.else_body, uni.ElseStmt) {
        return self._body_always_returns(nd.else_body.body);
    }
    if isinstance(nd.else_body, uni.ElseIf) {
        return self._elseif_always_returns(nd.else_body);
    }
    return False;
}

"""Check scope-level diagnostics: duplicate definitions, unused imports,
duplicate imports, variable shadowing."""
impl StaticAnalysisPass._check_scope_diagnostics(mod: uni.Module) -> None {
    # W2031: unused imports
    for nd in mod.get_all_sub_nodes(typ=uni.Import, brute_force=True) {
        if nd.items is None {
            continue;
        }
        for item in nd.items {
            if not isinstance(item, uni.ModuleItem) {
                continue;
            }
            item_name = item.alias.value
                if item.alias is not None and isinstance(item.alias, uni.Name)
                else (item.name.value if isinstance(item.name, uni.Name) else None);
            if item_name is None {
                continue;
            }
            # Check if the imported name is used via symbol table
            if isinstance(item.name, uni.Name) and item.name.sym is not None {
                if len(item.name.sym.uses) == 0 and not item_name.startswith("_") {
                    self.emit(W2031, node_override=item, name=item_name);
                }
            }
        }
    }

    # W2032: duplicate imports
    seen_imports: dict[str, uni.UniNode] = {};
    for nd in mod.get_all_sub_nodes(typ=uni.Import, brute_force=True) {
        if nd.items is None {
            continue;
        }
        for item in nd.items {
            if not isinstance(item, uni.ModuleItem) {
                continue;
            }
            item_name = item.alias.value
                if item.alias is not None and isinstance(item.alias, uni.Name)
                else (item.name.value if isinstance(item.name, uni.Name) else None);
            if item_name is None {
                continue;
            }
            from_path = "";
            if nd.from_loc is not None {
                from_path = nd.from_loc?.dot_path_str or str(nd.from_loc);
            }
            import_key = f"{from_path}::{item_name}";
            if import_key in seen_imports {
                self.emit(W2032, node_override=item, name=item_name);
            } else {
                seen_imports[import_key] = item;
            }
        }
    }

    # E2036: duplicate definitions in same scope + W2027: variable shadowing
    self._check_scope_defs(mod);
}

"""Recursively check scopes for duplicate definitions and shadowing."""
impl StaticAnalysisPass._check_scope_defs(scope: uni.UniScopeNode) -> None {
    if id(scope) in self._checked_scopes {
        return;
    }
    self._checked_scopes.add(id(scope));

    # E2036: Check for duplicate definitions
    seen_defs: dict[str, uni.UniNode] = {};
    for (name, sym) in scope.names_in_scope.items() {
        if sym.imported {
            continue;
        }
        # Only flag archetypes, abilities, and functions — not variables
        if sym.sym_type not in (
            SymbolType.OBJECT_ARCH,
            SymbolType.NODE_ARCH,
            SymbolType.EDGE_ARCH,
            SymbolType.WALKER_ARCH,
            SymbolType.ENUM_ARCH,
            SymbolType.ABILITY
        ) {
            continue;
        }
        if len(sym.defn) > 1 {
            # Multiple definitions of the same name in this scope
            for defn_node in sym.defn[1:] {
                self.emit(E2036, node_override=defn_node, name=name);
            }
        }
    }

    # W2027: variable shadowing — check if names in child scopes shadow parent
    for kid in scope.kid_scope {
        if isinstance(kid, (uni.Ability, uni.ImplDef)) {
            for (name, sym) in kid.names_in_scope.items() {
                if sym.imported or name.startswith("_") {
                    continue;
                }
                if name in ("self", "super", "init", "postinit") {
                    continue;
                }
                if sym.sym_type != SymbolType.VAR {
                    continue;
                }
                # Check if name exists in an outer scope
                outer_sym = scope.lookup(name, deep=False);
                if outer_sym is not None and not outer_sym.imported {
                    # Skip when both scopes share the same declaration
                    # (e.g. self.x = x in init hoists the param symbol
                    # into the archetype scope — same decl, not a shadow).
                    if outer_sym.decl is not sym.decl {
                        self.emit(W2027, node_override=sym.decl, name=name);
                    }
                }
            }
        }
        self._check_scope_defs(kid);
    }
}

"""Check archetype-level semantic rules: final inheritance, abstract obligations,
__eq__ without __hash__, walker visit statements."""
impl StaticAnalysisPass._check_archetype_semantics(mod: uni.Module) -> None {
    for nd in mod.get_all_sub_nodes(typ=uni.Archetype, brute_force=True) {
        # E2042: cannot inherit from final archetype
        if nd.base_classes is not None {
            for base in nd.base_classes {
                base_name: str | None = None;
                if isinstance(base, uni.Name) {
                    base_name = base.value;
                } elif isinstance(base, uni.AtomTrailer)
                and isinstance(base.right, uni.Name) {
                    base_name = base.right.value;
                }
                if base_name is not None
                and isinstance(base, uni.Name)
                and base.sym is not None {
                    # Check if the base class has @final decorator
                    base_decl = base.sym.decl;
                    if base_decl is not None {
                        base_arch = base_decl.find_parent_of_type(uni.Archetype);
                        if base_arch is None and hasattr(base_decl, 'name_of') {
                            base_arch = base_decl.name_of
                                if isinstance(
                                    base_decl.name_of, uni.Archetype
                                )
                                else None;
                        }
                        if base_arch is not None
                        and isinstance(base_arch, uni.Archetype)
                        and base_arch.decorators is not None {
                            for dec in base_arch.decorators {
                                if isinstance(dec, uni.Name) and dec.value == "final" {
                                    self.emit(E2042, node_override=nd, name=base_name);
                                }
                            }
                        }
                    }
                }
            }
        }

        # E2044: unimplemented abstract abilities
        if nd.base_classes is not None and nd.body is not None {
            # Skip if this archetype is itself abstract
            is_abstract = False;
            if nd.decorators is not None {
                for dec in nd.decorators {
                    if isinstance(dec, uni.Name) and dec.value == "abstract" {
                        is_abstract = True;
                        break;
                    }
                }
            }
            if not is_abstract {
                # Collect method names defined in this archetype
                own_methods: set[str] = set();
                for stmt in nd.body {
                    if isinstance(stmt, uni.Ability)
                    and stmt.name_ref is not None
                    and isinstance(stmt.name_ref, uni.Name) {
                        own_methods.add(stmt.name_ref.value);
                    }
                }
                # Check base classes for abstract methods
                for base in nd.base_classes {
                    if not isinstance(base, uni.Name) or base.sym is None {
                        continue;
                    }
                    base_arch_node: uni.Archetype | None = None;
                    base_decl = base.sym.decl;
                    if base_decl?.name_of
                    and isinstance(base_decl.name_of, uni.Archetype) {
                        base_arch_node = base_decl.name_of;
                    }
                    if base_arch_node is None or base_arch_node.body is None {
                        continue;
                    }
                    for stmt in base_arch_node.body {
                        if isinstance(stmt, uni.Ability)
                        and (stmt.is_abstract or stmt.body is None)
                        and stmt.name_ref is not None
                        and isinstance(stmt.name_ref, uni.Name) {
                            method_name = stmt.name_ref.value;
                            if method_name not in own_methods {
                                arch_name = nd.name.value
                                    if isinstance(nd.name, uni.Name)
                                    else str(nd.name);
                                self.emit(
                                    E2044,
                                    node_override=nd,
                                    name=arch_name,
                                    method=method_name
                                );
                            }
                        }
                    }
                }
            }
        }

        # W2047: __eq__ defined without __hash__
        if nd.body is not None {
            has_eq = False;
            has_hash = False;
            for stmt in nd.body {
                if isinstance(stmt, uni.Ability)
                and stmt.name_ref is not None
                and isinstance(stmt.name_ref, uni.Name) {
                    if stmt.name_ref.value == "__eq__" {
                        has_eq = True;
                    }
                    if stmt.name_ref.value == "__hash__" {
                        has_hash = True;
                    }
                }
            }
            if has_eq and not has_hash {
                arch_name = nd.name.value
                    if isinstance(nd.name, uni.Name)
                    else str(nd.name);
                self.emit(W2047, node_override=nd, name=arch_name);
            }
        }

        # W2085: walker has no visit statements
        if nd.arch_type is not None
        and isinstance(nd.arch_type, uni.Token)
        and nd.arch_type.value == "walker"
        and nd.body is not None {
            has_visit = False;
            for sub in nd.get_all_sub_nodes(typ=uni.VisitStmt, brute_force=True) {
                has_visit = True;
                break;
            }
            if not has_visit {
                self.emit(W2085, node_override=nd);
            }
        }

        # W2041: incompatible method override
        if nd.base_classes is not None and nd.body is not None {
            for base in nd.base_classes {
                if not isinstance(base, uni.Name) or base.sym is None {
                    continue;
                }
                base_arch_node: uni.Archetype | None = None;
                base_decl = base.sym.decl;
                if base_decl?.name_of and isinstance(base_decl.name_of, uni.Archetype) {
                    base_arch_node = base_decl.name_of;
                }
                if base_arch_node is None or base_arch_node.body is None {
                    continue;
                }
                # Build base method signatures
                base_methods: dict[str, uni.Ability] = {};
                for stmt in base_arch_node.body {
                    if isinstance(stmt, uni.Ability)
                    and stmt.name_ref is not None
                    and isinstance(stmt.name_ref, uni.Name) {
                        base_methods[stmt.name_ref.value] = stmt;
                    }
                }
                # Check overrides
                for stmt in nd.body {
                    if not isinstance(stmt, uni.Ability)
                    or stmt.name_ref is None
                    or not isinstance(stmt.name_ref, uni.Name) {
                        continue;
                    }
                    method_name = stmt.name_ref.value;
                    if method_name not in base_methods {
                        continue;
                    }
                    base_method = base_methods[method_name];
                    # Compare parameter count and types
                    if stmt.signature is not None
                    and isinstance(stmt.signature, uni.FuncSignature)
                    and base_method.signature is not None
                    and isinstance(base_method.signature, uni.FuncSignature) {
                        child_params = stmt.signature.params;
                        base_params = base_method.signature.params;
                        child_count = len(child_params) if child_params else 0;
                        base_count = len(base_params) if base_params else 0;
                        if child_count != base_count {
                            self.emit(W2041, node_override=stmt, name=method_name);
                        } elif child_count > 0 {
                            # Check parameter types using TypeBase from type checker
                            for i in range(child_count) {
                                c_type = getattr(child_params[i], 'type', None);
                                b_type = getattr(base_params[i], 'type', None);
                                if isinstance(c_type, TypeBase)
                                and isinstance(b_type, TypeBase) {
                                    if isinstance(c_type, ClassType)
                                    and isinstance(b_type, ClassType) {
                                        if c_type.shared != b_type.shared {
                                            self.emit(
                                                W2041,
                                                node_override=stmt,
                                                name=method_name
                                            );
                                            break;
                                        }
                                    } elif type(c_type) != type(b_type) {
                                        self.emit(
                                            W2041, node_override=stmt, name=method_name
                                        );
                                        break;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
