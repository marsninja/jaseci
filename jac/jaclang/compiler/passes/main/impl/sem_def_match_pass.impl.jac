"""Connect sem strings from source symbol table to declarations in target symbol table.

When source_sym_tab and target_sym_tab are the same, this connects within the same module.
When different, it connects implementations from impl_mod to declarations in the main module.

Walking each SemDef's `target: Sequence[NameAtom]` directly (rather than splitting
the string-form `sem.A.B.C` of the SemDef's symbol name) lets us bind each target
Name's `sym` attribute to the resolved Symbol. With those bindings in place, the
type checker and static analysis passes both gate on `nd.sym is None` and naturally
skip these path components — they are dotted-path navigation, not standalone
expressions or undefined references. The bindings also enable IDE features like
go-to-definition on each segment of `sem Foo.bar.baz`.
"""
impl SemDefMatchPass.connect_sems(
    source_sym_tab: UniScopeNode, target_sym_tab: UniScopeNode
) -> None {
    for sym in source_sym_tab.names_in_scope.values() {
        if not isinstance(sym.decl.name_of, uni.SemDef) {
            continue;
        }
        semdef = sym.decl.name_of;
        folded = self.fold_const_str(semdef.value);
        if folded is None {
            # The value is not a compile-time-constant string (e.g. a name
            # reference, a call, or arithmetic). Report it once, on the value.
            self.emit(E2013, node_override=semdef.value);
            continue;
        }
        target_sym = self.resolve_sem_target(semdef, target_sym_tab);
        if (target_sym is not None) {
            target_sym.decl.name_of.semstr = folded;
            target_sym.semstr = folded;
        }
    }
}

"""Constant-fold a sem value expression to its string, or None if non-constant.

Folds the shapes a sem value is allowed to take: a string literal, a
MultiString (adjacent string literals, implicitly concatenated), a
parenthesized group, and `+` concatenation of any of those. Anything else --
a name reference, a function call, arithmetic on non-strings -- is not a
compile-time constant string and yields None.
"""
impl SemDefMatchPass.fold_const_str(expr: uni.Expr) -> (str | None) {
    if isinstance(expr, uni.MultiString) {
        return expr.lit_value;
    }
    if isinstance(expr, uni.String) {
        return expr.lit_value;
    }
    # Parenthesized group: unwrap and fold the inner expression. `value` may be
    # a YieldExpr or Ability, which are not constant strings -- the isinstance
    # guard (recursion only folds Expr shapes) rejects those.
    if isinstance(expr, uni.AtomUnit) and isinstance(expr.value, uni.Expr) {
        return self.fold_const_str(expr.value);
    }
    # `+` concatenation: both operands must themselves fold to strings.
    if isinstance(expr, uni.BinaryExpr)
    and isinstance(expr.op, uni.Token)
    and expr.op.name == Tok.PLUS {
        left = self.fold_const_str(expr.left);
        right = self.fold_const_str(expr.right);
        if left is not None and right is not None {
            return left + right;
        }
    }
    return None;
}

"""Walk a SemDef's target chain (e.g., `Foo.bar.baz`) against the target
symbol table, binding each target Name's `sym` attribute to the resolved
Symbol along the way.

Returns the final resolved Symbol, or None if any segment fails to resolve.
Partial chains still bind every Name they could resolve before the failing
segment, which keeps IDE tooling useful even when the user is mid-edit.
"""
impl SemDefMatchPass.resolve_sem_target(
    semdef: uni.SemDef, target_sym_tab: UniScopeNode
) -> (Symbol | None) {
    current_sym_tab: (UniScopeNode | None) = target_sym_tab;
    sym: (uni.Symbol | None) = None;
    for part_node in semdef.target {
        if (current_sym_tab is None) {
            return None;
        }
        sym = current_sym_tab.lookup(part_node.sym_name, deep=False);
        if (sym is None) {
            return None;
        }
        # Register the segment as a use site of the resolved symbol.
        # This binds `part_node.sym` (so TypeCheckPass and StaticAnalysisPass
        # treat it as resolved) and appends the Name to `Symbol.uses` so
        # find-references / refactor tooling sees each segment of
        # `sem Foo.bar.baz` as a real reference. The `sym is None` guard
        # keeps it idempotent across pass reruns.
        if part_node.sym is None {
            sym.add_use(part_node);
        }
        current_sym_tab = sym.symbol_table;
    }
    return sym;
}

"""Connect Decls and Defs."""
impl SemDefMatchPass.transform(ir_in: uni.Module) -> uni.Module {
    self.cur_node = ir_in;
    self.connect_sems(ir_in.sym_tab, ir_in.sym_tab);
    for impl_module in ir_in.impl_mod {
        self.connect_sems(impl_module.sym_tab, ir_in.sym_tab);
    }
    return ir_in;
}
