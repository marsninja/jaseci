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
    self._check_scope_patterns(self.ir_in);
    self._check_archetype_patterns(self.ir_in);
    self._check_walker_patterns(self.ir_in);
    self._check_type_patterns(self.ir_in);
    for annex_mod in self.ir_in.impl_mod + self.ir_in.test_mod + self.ir_in.variant_mod {
        self._check_undefined_names(annex_mod);
        self._check_unreachable_code(annex_mod);
        self._check_semantic_patterns(annex_mod);
        self._check_scope_patterns(annex_mod);
        self._check_archetype_patterns(annex_mod);
        self._check_walker_patterns(annex_mod);
        self._check_type_patterns(annex_mod);
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

    # W1104: condition is always true/false (literal True/False)
    for nd in mod.get_all_sub_nodes(typ=uni.IfStmt, brute_force=True) {
        if isinstance(nd.condition, uni.Bool) {
            val = "true" if nd.condition.value == "True" else "false";
            self.emit(W1104, node_override=nd.condition, value=val);
        }
    }
    for nd in mod.get_all_sub_nodes(typ=uni.WhileStmt, brute_force=True) {
        if isinstance(nd.condition, uni.Bool) and nd.condition.value == "False" {
            self.emit(W1104, node_override=nd.condition, value="false");
        }
    }

    # W1161: unreachable match case after wildcard
    for nd in mod.get_all_sub_nodes(typ=uni.MatchStmt, brute_force=True) {
        found_wildcard = False;
        for case_nd in nd.cases {
            if found_wildcard {
                self.emit(W1161, node_override=case_nd);
                break;
            }
            # Check if case pattern is wildcard (_)
            if case_nd.pattern is not None {
                if isinstance(case_nd.pattern, uni.Name)
                and case_nd.pattern.value == "_" {
                    found_wildcard = True;
                } elif isinstance(case_nd.pattern, uni.MatchWild) {
                    found_wildcard = True;
                }
            }
        }
    }

    # E1160: non-exhaustive match on enum
    for nd in mod.get_all_sub_nodes(typ=uni.MatchStmt, brute_force=True) {
        if nd.target is None or len(nd.cases) == 0 {
            continue;
        }
        # Detect enum type from the match case patterns (MatchValue with AtomTrailer)
        enum_node: (uni.Enum | None) = None;
        matched: set[str] = set();
        has_wildcard = False;
        for case_nd in nd.cases {
            if case_nd.pattern is None {
                continue;
            }
            if isinstance(case_nd.pattern, uni.MatchWild) {
                has_wildcard = True;
                continue;
            }
            if isinstance(case_nd.pattern, uni.Name) and case_nd.pattern.value == "_" {
                has_wildcard = True;
                continue;
            }
            # MatchValue wraps an AtomTrailer like Direction.NORTH
            pat_val = None;
            if isinstance(case_nd.pattern, uni.MatchValue)
            and hasattr(case_nd.pattern, 'value') {
                pat_val = case_nd.pattern.value;
            } elif isinstance(case_nd.pattern, uni.AtomTrailer) {
                pat_val = case_nd.pattern;
            }
            if pat_val is not None and isinstance(pat_val, uni.AtomTrailer) {
                if isinstance(pat_val.right, uni.Name) {
                    matched.add(pat_val.right.value);
                }
                # Resolve enum type from the target (e.g. Direction)
                if enum_node is None
                and pat_val?.target
                and isinstance(pat_val.target, uni.Name)
                and pat_val.target.sym is not None {
                    decl = pat_val.target.sym.decl;
                    if isinstance(decl, uni.Name)
                    and isinstance(decl.parent, uni.Enum) {
                        enum_node = decl.parent;
                    }
                }
            }
        }
        if has_wildcard or enum_node is None or enum_node.body is None {
            continue;
        }
        # Collect all enum members
        enum_members: set[str] = set();
        for member in enum_node.body {
            if isinstance(member, uni.Assignment) {
                for t in member.target {
                    if isinstance(t, uni.Name) {
                        enum_members.add(t.value);
                    }
                }
            } elif isinstance(member, uni.Name) {
                enum_members.add(member.value);
            }
        }
        missing = enum_members - matched;
        if len(missing) > 0 {
            self.emit(E1160, node_override=nd, missing=", ".join(sorted(missing)));
        }
    }

    # W1153: float equality comparison
    for nd in mod.get_all_sub_nodes(typ=uni.CompareExpr, brute_force=True) {
        for (i, op) in enumerate(nd.ops) {
            if op.value in ("==", "!=") {
                right = nd.rights[i] if i < len(nd.rights) else None;
                left = nd.left if i == 0 else (nd.rights[i - 1] if i > 0 else None);
                if isinstance(right, uni.Float) or isinstance(left, uni.Float) {
                    self.emit(W1153, node_override=nd);
                    break;
                }
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
}

"""Check scope-level patterns: unused imports, duplicate imports, shadowing,
use before def, duplicate definitions, self/super outside method."""
impl StaticAnalysisPass._check_scope_patterns(mod: uni.Module) -> None {
    # W2031/W4004: unused imports
    for nd in mod.get_all_sub_nodes(typ=uni.Import, brute_force=True) {
        if nd.items is None {
            continue;
        }
        for item in nd.items {
            if isinstance(item, uni.ModuleItem) {
                item_name = item.alias.value
                    if item.alias is not None
                    else (item.name.value if isinstance(item.name, uni.Name) else None);
                if item_name is None or item_name == "*" {
                    continue;
                }
                # Check the name node's symbol for uses
                name_node = item.alias if item.alias is not None else item.name;
                if isinstance(name_node, uni.Name) and name_node.sym is not None {
                    # uses includes the import itself; >1 means actual usage
                    if len(name_node.sym.uses) <= 1 {
                        self.emit(W2031, node_override=item, name=item_name);
                    }
                }
            }
        }
    }

    # W2032/W4005: duplicate imports
    seen_imports: dict[str, uni.UniNode] = {};
    for nd in mod.get_all_sub_nodes(typ=uni.Import, brute_force=True) {
        if nd.items is None {
            continue;
        }
        for item in nd.items {
            if isinstance(item, uni.ModuleItem) {
                item_name = item.alias.value
                    if item.alias is not None
                    else (item.name.value if isinstance(item.name, uni.Name) else None);
                if item_name is not None {
                    if item_name in seen_imports {
                        self.emit(W2032, node_override=item, name=item_name);
                    } else {
                        seen_imports[item_name] = item;
                    }
                }
            }
        }
    }

    # W2025: wildcard import
    for nd in mod.get_all_sub_nodes(typ=uni.Import, brute_force=True) {
        if nd.items is not None {
            for item in nd.items {
                if isinstance(item, uni.ModuleItem)
                and isinstance(item.name, uni.Name)
                and item.name.value == "*" {
                    self.emit(W2025, node_override=nd);
                }
            }
        }
    }

    # E2029/E2030: self/super used outside archetype method
    for nd in mod.get_all_sub_nodes(typ=uni.SpecialVarRef, brute_force=True) {
        if nd.value not in ("self", "super") {
            continue;
        }
        # Walk up to find if we're in an archetype method
        in_method = False;
        parent = nd.parent;
        while parent is not None {
            if isinstance(parent, uni.Archetype) {
                in_method = True;
                break;
            }
            if isinstance(parent, uni.ImplDef) {
                # Check if impl is for an archetype method
                if parent.decl_link is not None
                and isinstance(parent.decl_link, uni.Ability)
                and parent.decl_link.method_owner is not None {
                    in_method = True;
                }
                break;
            }
            if isinstance(parent, uni.Module) {
                break;
            }
            parent = parent.parent;
        }
        if not in_method {
            if nd.value == "self" {
                self.emit(E2029, node_override=nd);
            } else {
                self.emit(E2030, node_override=nd);
            }
        }
    }

    # E2020: use before definition (simple version - check in same scope)
    for nd in mod.get_all_sub_nodes(typ=uni.ModuleCode, brute_force=True) {
        if nd.body is None {
            continue;
        }
        defined: set[str] = set();
        flagged: set[str] = set();
        # Collect all names defined in this block (not from imports/outer scope)
        all_defined_names: set[str] = set();
        for stmt in nd.body {
            if isinstance(stmt, uni.Assignment) {
                for t in stmt.target {
                    if isinstance(t, uni.Name) {
                        all_defined_names.add(t.value);
                    }
                }
            }
        }
        for stmt in nd.body {
            # Check Name references used before their definition
            names_in_stmt = stmt.get_all_sub_nodes(typ=uni.Name, brute_force=True);
            for name_nd in names_in_stmt {
                # Skip assignment targets
                if isinstance(stmt, uni.Assignment) and name_nd in stmt.target {
                    continue;
                }
                # Skip builtins and imports
                import builtins;
                if name_nd.value in dir(builtins) {
                    continue;
                }
                if name_nd._py_ctx_func == ast3.Load
                and name_nd.value not in defined
                and name_nd.value in all_defined_names
                and name_nd.value not in flagged {
                    self.emit(E2020, node_override=name_nd, name=name_nd.value);
                    flagged.add(name_nd.value);
                }
            }
            # Track definitions
            if isinstance(stmt, uni.Assignment) {
                for t in stmt.target {
                    if isinstance(t, uni.Name) {
                        defined.add(t.value);
                    }
                }
            }
        }
    }

    # E2036: duplicate definitions in same scope
    for scope in mod.get_all_sub_nodes(typ=uni.Module, brute_force=True) + [mod] {
        if not hasattr(scope, 'body') or scope.body is None {
            continue;
        }
        seen_defs: dict[str, uni.UniNode] = {};
        for stmt in scope.body {
            def_name: str | None = None;
            if isinstance(stmt, uni.Ability) and stmt.name_ref is not None {
                def_name = stmt.name_ref.value
                    if isinstance(stmt.name_ref, uni.Name)
                    else None;
            } elif isinstance(stmt, uni.Archetype) {
                def_name = stmt.name.value if isinstance(stmt.name, uni.Name) else None;
            }
            if def_name is not None {
                if def_name in seen_defs {
                    self.emit(E2036, node_override=stmt, name=def_name);
                } else {
                    seen_defs[def_name] = stmt;
                }
            }
        }
    }

    # W2027: variable shadows outer scope
    for nd in mod.get_all_sub_nodes(typ=uni.Ability, brute_force=True) {
        if not hasattr(nd, 'names_in_scope') {
            continue;
        }
        for (name, sym) in nd.names_in_scope.items() {
            if name.startswith("_") or name in ("self", "super") {
                continue;
            }
            # Skip method parameters — they commonly shadow archetype attributes
            if sym.sym_type == SymbolType.VAR and isinstance(nd.parent, uni.Archetype) {
                continue;
            }
            # Check parent scopes for same name (skip immediate archetype parent)
            parent_scope = nd.parent;
            while parent_scope is not None {
                if parent_scope?.names_in_scope
                and name in parent_scope.names_in_scope {
                    parent_sym = parent_scope.names_in_scope[name];
                    if parent_sym.imported {
                        break;
                    }
                    # Skip shadowing of has-vars in archetypes (common pattern)
                    if isinstance(parent_scope, uni.Archetype)
                    and parent_sym.sym_type in (SymbolType.HAS_VAR, SymbolType.VAR) {
                        break;
                    }
                    # Only warn for module-level variable shadowing
                    if isinstance(parent_scope, uni.Module) {
                        self.emit(W2027, node_override=sym.decl, name=name);
                    }
                    break;
                }
                parent_scope = getattr(parent_scope, 'parent', None);
            }
        }
    }

    # W2062: dead store (variable assigned then immediately reassigned)
    for nd in mod.get_all_sub_nodes(typ=uni.ModuleCode, brute_force=True) {
        if nd.body is None {
            continue;
        }
        body_list = list(nd.body);
        for (i, stmt) in enumerate(body_list) {
            if not isinstance(stmt, uni.Assignment) or stmt.aug_op is not None {
                continue;
            }
            for t in stmt.target {
                if not isinstance(t, uni.Name) {
                    continue;
                }
                var_name = t.value;
                # Look at next non-semi statement
                for j in range(i + 1, len(body_list)) {
                    next_stmt = body_list[j];
                    if isinstance(next_stmt, uni.Semi) {
                        continue;
                    }
                    if isinstance(next_stmt, uni.Assignment)
                    and next_stmt.aug_op is None {
                        for nt in next_stmt.target {
                            if isinstance(nt, uni.Name) and nt.value == var_name {
                                # Check if var_name is NOT used in the value of next assignment
                                used_in_value = False;
                                if next_stmt.value is not None {
                                    for vn in next_stmt.value.get_all_sub_nodes(
                                        typ=uni.Name, brute_force=True
                                    ) {
                                        if vn.value == var_name {
                                            used_in_value = True;
                                            break;
                                        }
                                    }
                                }
                                if not used_in_value {
                                    self.emit(W2062, node_override=stmt, name=var_name);
                                }
                            }
                        }
                    }
                    break;
                }
            }
        }
    }
}

"""Check archetype patterns: inherit from final, __eq__ without __hash__,
missing return, unimplemented abstract, incompatible override."""
impl StaticAnalysisPass._check_archetype_patterns(mod: uni.Module) -> None {
    for nd in mod.get_all_sub_nodes(typ=uni.Archetype, brute_force=True) {
        # E2042: inherit from final archetype
        if nd.base_classes is not None {
            for base in nd.base_classes {
                base_name: str | None = None;
                if isinstance(base, uni.Name) {
                    base_name = base.value;
                } elif isinstance(base, uni.AtomTrailer)
                and isinstance(base.right, uni.Name) {
                    base_name = base.right.value;
                }
                if base_name is not None and base.sym is not None {
                    base_decl = base.sym.decl;
                    # sym.decl is the Name node; Archetype is its parent
                    arch_node = base_decl.parent
                        if not isinstance(base_decl, uni.Archetype)
                        else base_decl;
                    if isinstance(arch_node, uni.Archetype)
                    and arch_node.decorators is not None {
                        for dec in arch_node.decorators {
                            if isinstance(dec, uni.Name) and dec.value == "final" {
                                self.emit(E2042, node_override=nd, name=base_name);
                            }
                        }
                    }
                }
            }
        }

        # W2047: __eq__ defined without __hash__
        if nd.body is not None and isinstance(nd.body, list) {
            has_eq = False;
            has_hash = False;
            for stmt in nd.body {
                if isinstance(stmt, uni.Ability) and stmt.name_ref is not None {
                    mname = stmt.name_ref.value
                        if isinstance(stmt.name_ref, uni.Name)
                        else "";
                    if mname == "__eq__" {
                        has_eq = True;
                    }
                    if mname == "__hash__" {
                        has_hash = True;
                    }
                }
            }
            if has_eq and not has_hash {
                self.emit(W2047, node_override=nd);
            }
        }

        # E2044: unimplemented abstract methods
        if nd.base_classes is not None
        and nd.body is not None
        and isinstance(nd.body, list) {
            # Collect methods defined in this archetype
            own_methods: set[str] = set();
            for stmt in nd.body {
                if isinstance(stmt, uni.Ability) and stmt.name_ref is not None {
                    mname = stmt.name_ref.value
                        if isinstance(stmt.name_ref, uni.Name)
                        else "";
                    own_methods.add(mname);
                }
            }
            # Helper: check if archetype has @abstract decorator
            def _has_abstract_decorator(arch: uni.Archetype) -> bool {
                if arch.decorators is not None {
                    for dec in arch.decorators {
                        if isinstance(dec, uni.Name) and dec.value == "abstract" {
                            return True;
                        }
                    }
                }
                return False;
            }
            # Skip if this archetype itself is abstract
            if not _has_abstract_decorator(nd) {
                # Check each base for abstract (bodyless) methods
                for base in nd.base_classes {
                    if base.sym is not None {
                        base_decl = base.sym.decl;
                        arch_node = base_decl.parent
                            if not isinstance(base_decl, uni.Archetype)
                            else base_decl;
                        if isinstance(arch_node, uni.Archetype)
                        and _has_abstract_decorator(arch_node)
                        and arch_node.body is not None
                        and isinstance(arch_node.body, list) {
                            for bstmt in arch_node.body {
                                if isinstance(bstmt, uni.Ability)
                                and bstmt.needs_impl
                                and bstmt.name_ref is not None {
                                    bname = bstmt.name_ref.value
                                        if isinstance(bstmt.name_ref, uni.Name)
                                        else "";
                                    if bname not in own_methods {
                                        self.emit(
                                            E2044,
                                            node_override=nd,
                                            method=bname,
                                            arch=nd.name.value
                                        );
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        # W2041: incompatible method override
        if nd.base_classes is not None
        and nd.body is not None
        and isinstance(nd.body, list) {
            for stmt in nd.body {
                if not isinstance(stmt, uni.Ability) or stmt.name_ref is None {
                    continue;
                }
                mname = stmt.name_ref.value
                    if isinstance(stmt.name_ref, uni.Name)
                    else "";
                if mname.startswith("_") {
                    continue;
                }
                # Find same method in base classes
                for base in nd.base_classes {
                    if base.sym is None {
                        continue;
                    }
                    base_decl = base.sym.decl;
                    arch_node = base_decl.parent
                        if not isinstance(base_decl, uni.Archetype)
                        else base_decl;
                    if not isinstance(arch_node, uni.Archetype)
                    or arch_node.body is None
                    or not isinstance(arch_node.body, list) {
                        continue;
                    }
                    for bstmt in arch_node.body {
                        if isinstance(bstmt, uni.Ability)
                        and bstmt.name_ref is not None {
                            bname = bstmt.name_ref.value
                                if isinstance(bstmt.name_ref, uni.Name)
                                else "";
                            if bname == mname {
                                # Compare parameter count
                                if stmt.signature is not None
                                and bstmt.signature is not None
                                and isinstance(stmt.signature, uni.FuncSignature)
                                and isinstance(bstmt.signature, uni.FuncSignature) {
                                    own_params = stmt.signature.params
                                        if stmt.signature.params is not None
                                        else [];
                                    base_params = bstmt.signature.params
                                        if bstmt.signature.params is not None
                                        else [];
                                    if len(own_params) != len(base_params) {
                                        self.emit(
                                            W2041, node_override=stmt, name=mname
                                        );
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    # W2050: missing return statement
    for nd in mod.get_all_sub_nodes(typ=uni.Ability, brute_force=True) {
        if nd.signature is None or not isinstance(nd.signature, uni.FuncSignature) {
            continue;
        }
        # Check if function has a return type annotation that's not None
        if nd.signature.return_type is None {
            continue;
        }
        ret_type = nd.signature.return_type;
        if isinstance(ret_type, uni.BuiltinType) and ret_type.value == "None" {
            continue;
        }
        # Check if body exists and ends with a return
        if nd.body is None or not isinstance(nd.body, list) or len(nd.body) == 0 {
            continue;
        }
        if nd.is_abstract or nd.needs_impl {
            continue;
        }
        # Check if last non-semi statement is a return
        last_stmt = None;
        for stmt in reversed(nd.body) {
            if not isinstance(stmt, uni.Semi) {
                last_stmt = stmt;
                break;
            }
        }
        if last_stmt is None {
            continue;
        }
        if isinstance(last_stmt, uni.ReturnStmt) {
            continue;
        }
        # If last statement is if/else, check both branches return
        if isinstance(last_stmt, uni.IfStmt) {
            if last_stmt.else_body is not None {
                # Has else - might be ok if both branches return
                continue;
            }
        }
        # Function with return type doesn't end with return
        fname = nd.name_ref.value
            if nd.name_ref is not None and isinstance(nd.name_ref, uni.Name)
            else "?";
        self.emit(W2050, node_override=nd, name=fname);
    }
}

"""Check walker-specific patterns: no visit statements, unhandled node types."""
impl StaticAnalysisPass._check_walker_patterns(mod: uni.Module) -> None {
    for nd in mod.get_all_sub_nodes(typ=uni.Archetype, brute_force=True) {
        if nd.arch_type is None
        or not isinstance(nd.arch_type, uni.Token)
        or nd.arch_type.value != "walker" {
            continue;
        }

        # W2085: walker has no visit statements
        has_visit = False;
        for visit_nd in nd.get_all_sub_nodes(typ=uni.VisitStmt, brute_force=True) {
            has_visit = True;
            break;
        }
        if not has_visit
        and nd.body is not None
        and isinstance(nd.body, list)
        and len(nd.body) > 0 {
            walker_name = nd.name.value if isinstance(nd.name, uni.Name) else "?";
            self.emit(W2085, node_override=nd, name=walker_name);
        }

        # E2080: walker visits node types but has no ability for them
        # Collect visit abilities (can X with NodeType entry)
        handled_types: set[str] = set();
        if nd.body is not None and isinstance(nd.body, list) {
            for stmt in nd.body {
                if isinstance(stmt, uni.Ability)
                and stmt.signature is not None
                and isinstance(stmt.signature, uni.EventSignature) {
                    if stmt.signature.event is not None
                    and isinstance(stmt.signature.event, uni.Name) {
                        handled_types.add(stmt.signature.event.value);
                    } elif stmt.signature.event is not None
                    and isinstance(stmt.signature.event, uni.SpecialVarRef) {
                        handled_types.add(stmt.signature.event.value);
                    }
                }
            }
        }
        # E2080: Check if walker has visit stmts but no ability for visited types.
        # Simplified: check if visit targets reference node types that have no
        # corresponding event ability in the walker.
        if nd.body is not None and isinstance(nd.body, list) {
            for stmt in nd.body {
                if isinstance(stmt, uni.Ability) and stmt.body is not None {
                    for visit_nd in stmt.get_all_sub_nodes(
                        typ=uni.VisitStmt, brute_force=True
                    ) {
                        # Check visit target for edge references (-->)
                        if visit_nd.target is not None and len(handled_types) > 0 {
                            # We have event handlers — check if all visited nodes are handled
                            # This is a simplified check: flag only if walker has specific
                            # event handlers but visits nodes not in the handled set
                            visited_types: set[str] = set();
                            for vn in visit_nd.get_all_sub_nodes(
                                typ=uni.Name, brute_force=True
                            ) {
                                if vn.sym is not None {
                                    decl = vn.sym.decl;
                                    if isinstance(decl, uni.Name)
                                    and isinstance(decl.parent, uni.Archetype) {
                                        if decl.parent.arch_type is not None
                                        and isinstance(
                                            decl.parent.arch_type, uni.Token
                                        )
                                        and decl.parent.arch_type.value == "node" {
                                            visited_types.add(vn.value);
                                        }
                                    }
                                }
                            }
                            for vt in visited_types {
                                if vt not in handled_types {
                                    self.emit(
                                        E2080, node_override=visit_nd, node_type=vt
                                    );
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

"""Check type-level patterns: instantiate abstract, enum member access,
generic type params, unhashable dict keys, private access."""
impl StaticAnalysisPass._check_type_patterns(mod: uni.Module) -> None {
    # E1113: instantiate abstract archetype
    for nd in mod.get_all_sub_nodes(typ=uni.FuncCall, brute_force=True) {
        if isinstance(nd.target, uni.Name) and nd.target.sym is not None {
            decl = nd.target.sym.decl;
            if isinstance(decl, uni.Name) and isinstance(decl.parent, uni.Archetype) {
                arch = decl.parent;
                # Check for @abstract decorator
                if arch.decorators is not None {
                    for dec in arch.decorators {
                        if isinstance(dec, uni.Name) and dec.value == "abstract" {
                            self.emit(E1113, node_override=nd, name=nd.target.value);
                            break;
                        }
                    }
                }
            }
        }
    }

    # E1140: enum member access - accessing non-existent member
    for nd in mod.get_all_sub_nodes(typ=uni.AtomTrailer, brute_force=True) {
        if not nd.is_attr or not isinstance(nd.right, uni.Name) {
            continue;
        }
        # Check if target is an enum
        if nd?.target
        and isinstance(nd.target, uni.Name)
        and nd.target.sym is not None {
            decl = nd.target.sym.decl;
            if isinstance(decl, uni.Name) and isinstance(decl.parent, uni.Enum) {
                enum_node = decl.parent;
                member_name = nd.right.value;
                # Collect enum members
                enum_members: set[str] = set();
                if enum_node.body is not None and isinstance(enum_node.body, list) {
                    for member in enum_node.body {
                        if isinstance(member, uni.Assignment) {
                            for t in member.target {
                                if isinstance(t, uni.Name) {
                                    enum_members.add(t.value);
                                }
                            }
                        } elif isinstance(member, uni.Name) {
                            enum_members.add(member.value);
                        }
                    }
                }
                # Skip dunder attrs and common enum methods
                if not member_name.startswith("_")
                and member_name not in enum_members {
                    self.emit(
                        E1140,
                        node_override=nd,
                        member=member_name,
                        enum=nd.target.value
                    );
                }
            }
        }
    }

    # E1110: generic type used without type parameters
    generic_types = {"list","dict","set","frozenset","tuple"};
    for nd in mod.get_all_sub_nodes(typ=uni.HasVar, brute_force=True) {
        if nd.type_tag is not None and isinstance(nd.type_tag, uni.SubTag) {
            type_expr = nd.type_tag.tag;
            if isinstance(type_expr, uni.BuiltinType)
            and type_expr.value in generic_types {
                self.emit(E1110, node_override=type_expr, name=type_expr.value);
            }
        }
    }

    # E2034: private member access from outside the archetype
    for nd in mod.get_all_sub_nodes(typ=uni.AtomTrailer, brute_force=True) {
        if not nd.is_attr or not isinstance(nd.right, uni.Name) {
            continue;
        }
        member_name = nd.right.value;
        if not member_name.startswith("_") or member_name.startswith("__") {
            continue;
        }
        # Check if this access is from outside the owning archetype
        if nd?.target
        and isinstance(nd.target, uni.Name)
        and nd.target.value != "self" {
            # Accessing _private on something other than self
            parent_arch = nd.find_parent_of_type(uni.Archetype);
            if parent_arch is None {
                # Not inside any archetype — definitely external access
                self.emit(E2034, node_override=nd, name=member_name);
            }
        }
    }
}
