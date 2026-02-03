# Declaration parsing for the Jac recursive descent parser.
#
# Handles archetypes, abilities, enums, imports, impls, sem-defs,
# global vars, has-stmts, function signatures, and event clauses.
#
# All functions take `p` (the parser instance) as first argument.
# Type is `any` to avoid circular imports with parser.jac.
import from jaclang.pycore.unitree {
    UniNode,
    Token as UniToken,
    Name as UniName,
    String as UniString,
    Source as UniSource,
    Expr,
    NameAtom,
    AtomExpr,
    CodeBlockStmt,
    ArchBlockStmt,
    EnumBlockStmt,
    Archetype as UniArchetype,
    Enum as UniEnum,
    Ability as UniAbility,
    FuncSignature as UniFuncSignature,
    EventSignature as UniEventSignature,
    ParamVar as UniParamVar,
    ParamKind,
    ArchHas as UniArchHas,
    HasVar as UniHasVar,
    Import as UniImport,
    ModulePath as UniModulePath,
    ModuleItem as UniModuleItem,
    ImplDef as UniImplDef,
    SemDef as UniSemDef,
    GlobalVars as UniGlobalVars,
    Assignment as UniAssignment,
    SubTag as UniSubTag,
    ModuleCode as UniModuleCode,
    PyInlineCode as UniPyInlineCode
}

import from jaclang.pycore.constant { Tokens as Tok, SymbolType }

import from jaclang.compiler.rd_parser.lexer { EOF_NAME }

import from jaclang.compiler.rd_parser.ast_builder {
    is_eof_token,
    is_name_token,
    is_special_ref_token,
    ARCH_TYPE_TOKENS
}

import from jaclang.compiler.rd_parser.parser_exprs {
    parse_expression,
    parse_atomic_chain,
    parse_pipe
}

import from jaclang.compiler.rd_parser.parser_stmts {
    parse_statement,
    parse_code_block,
    parse_code_block_with_kids
}

# ── Access Tag ─────────────────────────────────────────────────────────
"""Parse access_tag: COLON ( KW_PROT | KW_PUB | KW_PRIV )."""
def parse_access_tag(p: any) -> any {
    if not p.check(Tok.COLON.value) {
        return None;
    }
    colon = p.advance();
    access_names: list = [Tok.KW_PUB.value, Tok.KW_PROT.value, Tok.KW_PRIV.value];
    if p.peek().name in access_names {
        access_tok = p.advance();
    } else {
        access_tok = p.expect(Tok.KW_PUB.value);
    }
    nd = UniSubTag(tag=access_tok, kid=[colon, access_tok]);
    p.register_node(nd);
    return nd;
}

# ── Type Tag ───────────────────────────────────────────────────────────
"""Parse type_tag: COLON pipe."""
def parse_type_tag(p: any) -> any {
    colon = p.expect(Tok.COLON.value);
    type_expr = parse_pipe(p);
    nd = UniSubTag(tag=type_expr, kid=[colon, type_expr]);
    p.register_node(nd);
    return nd;
}

# ── Inherited Archs ───────────────────────────────────────────────────
"""Parse inherited_archs: LPAREN (atomic_chain COMMA)* atomic_chain RPAREN.
    Returns (bases_list, kids_list)."""
def _parse_inherited_archs(p: any) -> tuple {
    lparen = p.expect(Tok.LPAREN.value);
    bases: list = [];
    kids: list = [lparen];
    if not p.check(Tok.RPAREN.value) {
        base = parse_atomic_chain(p);
        bases.append(base);
        kids.append(base);
        while p.check(Tok.COMMA.value) {
            comma = p.advance();
            kids.append(comma);
            if p.check(Tok.RPAREN.value) {
                break;
            }
            base = parse_atomic_chain(p);
            bases.append(base);
            kids.append(base);
        }
    }
    rparen = p.expect(Tok.RPAREN.value);
    kids.append(rparen);
    return (bases, kids);
}

# ── Dotted Name ────────────────────────────────────────────────────────
"""Parse dotted_name: named_ref (DOT named_ref)*.
    Returns (names_list, kids_list)."""
def _parse_dotted_name(p: any) -> tuple {
    names: list = [];
    kids: list = [];
    name = p.parse_named_ref();
    names.append(name);
    kids.append(name);
    while p.check(Tok.DOT.value) {
        dot = p.advance();
        kids.append(dot);
        name = p.parse_named_ref();
        names.append(name);
        kids.append(name);
    }
    return (names, kids);
}

# ── Import Statement ──────────────────────────────────────────────────
"""Parse import_stmt (three forms):
    - KW_IMPORT KW_FROM from_path LBRACE import_items RBRACE
    - KW_IMPORT import_path (COMMA import_path)* SEMI
    - KW_INCLUDE import_path SEMI
    """
def parse_import_stmt(p: any) -> any {
    # Form 3: include
    if p.check(Tok.KW_INCLUDE.value) {
        include_tok = p.advance();
        path = _parse_import_path(p);
        semi = p.expect(Tok.SEMI.value);
        kids: list = [include_tok, path, semi];
        nd = UniImport(from_loc=None, items=[path], is_absorb=True, kid=kids);
        p.register_node(nd);
        return nd;
    }

    import_tok = p.expect(Tok.KW_IMPORT.value);

    # Form 1: from-import
    if p.check(Tok.KW_FROM.value) {
        from_tok = p.advance();
        from_path = _parse_from_path(p);
        lbrace = p.expect(Tok.LBRACE.value);
        items = _parse_import_items(p);
        rbrace = p.expect(Tok.RBRACE.value);
        kids: list = [import_tok, from_tok, from_path, lbrace];
        for item in items {
            kids.append(item);
        }
        kids.append(rbrace);
        nd = UniImport(from_loc=from_path, items=items, is_absorb=False, kid=kids);
        p.register_node(nd);
        return nd;
    }

    # Form 2: direct import
    path = _parse_import_path(p);
    paths: list = [path];
    kids: list = [import_tok, path];
    while p.check(Tok.COMMA.value) {
        comma = p.advance();
        kids.append(comma);
        path = _parse_import_path(p);
        paths.append(path);
        kids.append(path);
    }
    semi = p.expect(Tok.SEMI.value);
    kids.append(semi);
    nd = UniImport(from_loc=None, items=paths, is_absorb=False, kid=kids);
    p.register_node(nd);
    return nd;
}

"""Parse from_path: (DOT | ELLIPSIS)* import_path | (DOT | ELLIPSIS)+."""
def _parse_from_path(p: any) -> any {
    level = 0;
    kids: list = [];
    while p.check(Tok.DOT.value) or p.check(Tok.ELLIPSIS.value) {
        tok = p.advance();
        kids.append(tok);
        if tok.name == Tok.ELLIPSIS.value {
            level = level + 3;
        } else {
            level = level + 1;
        }
    }
    # Check if there's an actual path after the dots
    path_names: list = [];
    if is_name_token(p.peek()) or p.check(Tok.STRING.value) {
        result = _parse_import_path_inner(p);
        path_names = result[0];
        kids.extend(result[1]);
        alias = result[2];
    } else {
        alias = None;
    }
    nd = UniModulePath(
        path=path_names if len(path_names) > 0 else None,
        level=level,
        alias=alias,
        kid=kids
    );
    p.register_node(nd);
    return nd;
}

"""Parse import_path: (dotted_name | STRING) (KW_AS NAME)?."""
def _parse_import_path(p: any) -> any {
    result = _parse_import_path_inner(p);
    path_names = result[0];
    kids = result[1];
    alias = result[2];
    nd = UniModulePath(path=path_names, level=0, alias=alias, kid=kids);
    p.register_node(nd);
    return nd;
}

"""Inner helper returning (path_names, kids, alias)."""
def _parse_import_path_inner(p: any) -> tuple {
    path_names: list = [];
    kids: list = [];

    if p.check(Tok.STRING.value) {
        str_tok = p.advance();
        path_names.append(str_tok);
        kids.append(str_tok);
    } else {
        name = p.parse_named_ref();
        path_names.append(name);
        kids.append(name);
        while p.check(Tok.DOT.value) {
            dot = p.advance();
            kids.append(dot);
            name = p.parse_named_ref();
            path_names.append(name);
            kids.append(name);
        }
    }

    alias = None;
    if p.check(Tok.KW_AS.value) {
        as_tok = p.advance();
        kids.append(as_tok);
        alias = p.parse_named_ref();
        kids.append(alias);
    }

    return (path_names, kids, alias);
}

"""Parse import_items: (import_item COMMA)* import_item COMMA?."""
def _parse_import_items(p: any) -> list {
    items: list = [];
    if p.check(Tok.RBRACE.value) {
        return items;
    }
    item = _parse_import_item(p);
    items.append(item);
    while p.check(Tok.COMMA.value) {
        p.advance();
        if p.check(Tok.RBRACE.value) {
            break;
        }
        item = _parse_import_item(p);
        items.append(item);
    }
    return items;
}

"""Parse import_item: (KW_DEFAULT | STAR_MUL | named_ref) (KW_AS NAME)?."""
def _parse_import_item(p: any) -> any {
    kids: list = [];

    if p.check(Tok.KW_DEFAULT.value) {
        name = p.advance();
        kids.append(name);
    } elif p.check(Tok.STAR_MUL.value) {
        name = p.advance();
        kids.append(name);
    } else {
        name = p.parse_named_ref();
        kids.append(name);
    }

    alias = None;
    if p.check(Tok.KW_AS.value) {
        as_tok = p.advance();
        kids.append(as_tok);
        alias = p.parse_named_ref();
        kids.append(alias);
    }

    nd = UniModuleItem(name=name, alias=alias, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── Archetype Declaration ─────────────────────────────────────────────
"""Parse archetype: decorators? KW_ASYNC? archetype_decl."""
def parse_archetype(p: any, decorators: list = []) -> any {
    kids: list = [];
    for d in decorators {
        kids.append(d);
    }

    is_async = False;
    if p.check(Tok.KW_ASYNC.value) {
        async_tok = p.advance();
        kids.append(async_tok);
        is_async = True;
    }

    # arch_type token
    arch_type_tok = p.advance();
    kids.append(arch_type_tok);

    # Optional access tag
    access = None;
    if p.check(Tok.COLON.value) {
        access = parse_access_tag(p);
        if access is not None {
            kids.append(access);
        }
    }

    # Name
    name = p.parse_named_ref();
    kids.append(name);

    # Optional inherited_archs
    base_classes: list = [];
    if p.check(Tok.LPAREN.value) {
        inh_result = _parse_inherited_archs(p);
        base_classes = inh_result[0];
        kids.extend(inh_result[1]);
    }

    # Body: member_block or SEMI
    body = None;
    if p.check(Tok.LBRACE.value) {
        body_result = _parse_member_block(p);
        body = body_result[0];
        kids.extend(body_result[1]);
    } elif p.check(Tok.SEMI.value) {
        semi = p.advance();
        kids.append(semi);
        body = None;
    } else {
        p.log_error("Expected '{' or ';' after archetype declaration", p.peek());
    }

    nd = UniArchetype(
        name=name,
        arch_type=arch_type_tok,
        access=access,
        base_classes=base_classes,
        body=body,
        kid=kids,
        decorators=decorators if len(decorators) > 0 else None
    );
    p.register_node(nd);
    if is_async {
        nd.is_async = True;
    }
    return nd;
}

"""Parse member_block: LBRACE member_stmt* RBRACE.
    Returns (stmts_list, kids_list)."""
def _parse_member_block(p: any) -> tuple {
    lbrace = p.expect(Tok.LBRACE.value);
    stmts: list = [];
    kids: list = [lbrace];

    while not p.at_end() and not p.check(Tok.RBRACE.value) {
        # Optional docstring before member
        doc = None;
        if p.check(Tok.STRING.value) {
            doc = p.advance();
            kids.append(doc);
        }

        stmt = _parse_member_stmt(p);
        if stmt is not None {
            if doc is not None and stmt?.doc {
                stmt.doc = doc;
            }
            stmts.append(stmt);
            kids.append(stmt);
        } else {
            if not p.at_end() and not p.check(Tok.RBRACE.value) {
                p.advance();
            }
        }
    }

    rbrace = p.expect(Tok.RBRACE.value);
    kids.append(rbrace);
    return (stmts, kids);
}

"""Parse member_stmt: py_code_block | ability | archetype | impl_def | has_stmt | free_code."""
def _parse_member_stmt(p: any) -> any {
    tok = p.peek();

    if tok.name == Tok.PYNLINE.value {
        return p.parse_py_code_block();
    }
    if tok.name == Tok.DECOR_OP.value {
        decorators = p.parse_decorators();
        tok = p.peek();
        if tok.name == Tok.KW_ASYNC.value {
            peek1 = p.peek(1);
            if peek1.name in ARCH_TYPE_TOKENS {
                return parse_archetype(p, decorators=decorators);
            }
            return parse_ability(p, decorators=decorators);
        }
        if tok.name in ARCH_TYPE_TOKENS {
            return parse_archetype(p, decorators=decorators);
        }
        if tok.name == Tok.KW_ENUM.value {
            return parse_enum_def(p, decorators=decorators);
        }
        if tok.name == Tok.KW_STATIC.value {
            # static with decorator is always ability (static def/can); static has doesn't take decorators
            return parse_ability(p, decorators=decorators);
        }
        if tok.name in [Tok.KW_DEF.value, Tok.KW_CAN.value, Tok.KW_OVERRIDE.value] {
            return parse_ability(p, decorators=decorators);
        }
        p.log_error("Expected declaration after decorator", tok);
        return None;
    }
    if tok.name == Tok.KW_ASYNC.value {
        peek1 = p.peek(1);
        if peek1.name in ARCH_TYPE_TOKENS {
            return parse_archetype(p);
        }
        return parse_ability(p);
    }
    if tok.name in ARCH_TYPE_TOKENS {
        return parse_archetype(p);
    }
    if tok.name == Tok.KW_ENUM.value {
        return parse_enum_def(p);
    }
    # static can start either ability (static def/can) or has_stmt (static has)
    if tok.name == Tok.KW_STATIC.value {
        peek1 = p.peek(1);
        if peek1.name == Tok.KW_HAS.value {
            return parse_has_stmt(p);
        }
        return parse_ability(p);
    }
    if tok.name in [Tok.KW_DEF.value, Tok.KW_CAN.value, Tok.KW_OVERRIDE.value] {
        return parse_ability(p);
    }
    if tok.name == Tok.KW_IMPL.value {
        return parse_impl_def(p);
    }
    if tok.name == Tok.KW_HAS.value {
        return parse_has_stmt(p);
    }
    if tok.name == Tok.KW_WITH.value {
        peek1 = p.peek(1);
        if peek1.name == Tok.KW_ENTRY.value {
            return p.parse_free_code();
        }
    }
    return None;
}

# ── Enum Declaration ──────────────────────────────────────────────────
"""Parse enum: decorators? enum_decl.
    enum_decl: KW_ENUM access_tag? NAME inherited_archs? (enum_block | SEMI)."""
def parse_enum_def(p: any, decorators: list = []) -> any {
    kids: list = [];
    for d in decorators {
        kids.append(d);
    }

    enum_tok = p.expect(Tok.KW_ENUM.value);
    kids.append(enum_tok);

    # Optional access tag
    access = None;
    if p.check(Tok.COLON.value) {
        access = parse_access_tag(p);
        if access is not None {
            kids.append(access);
        }
    }

    # Name
    name = p.parse_named_ref();
    kids.append(name);

    # Optional inherited_archs (with colon for enums: NAME : base1, base2)
    base_classes: list = [];
    if p.check(Tok.LPAREN.value) {
        inh_result = _parse_inherited_archs(p);
        base_classes = inh_result[0];
        kids.extend(inh_result[1]);
    }

    # Body: enum_block or SEMI
    body = None;
    if p.check(Tok.LBRACE.value) {
        body_result = _parse_enum_block(p);
        body = body_result[0];
        kids.extend(body_result[1]);
    } elif p.check(Tok.SEMI.value) {
        semi = p.advance();
        kids.append(semi);
        body = None;
    } else {
        p.log_error("Expected '{' or ';' after enum declaration", p.peek());
    }

    nd = UniEnum(
        name=name,
        access=access,
        base_classes=base_classes,
        body=body,
        kid=kids,
        decorators=decorators if len(decorators) > 0 else None
    );
    p.register_node(nd);
    return nd;
}

"""Parse enum_block: LBRACE assignment_list (py_code_block | free_code)* RBRACE.
    Returns (stmts_list, kids_list)."""
def _parse_enum_block(p: any) -> tuple {
    lbrace = p.expect(Tok.LBRACE.value);
    stmts: list = [];
    kids: list = [lbrace];

    # Parse assignment_list
    assignments = _parse_assignment_list(p);
    for a in assignments {
        if isinstance(a, UniAssignment) {
            a.is_enum_stmt = True;
        }
        stmts.append(a);
        kids.append(a);
    }

    # Optional trailing comma
    if p.check(Tok.COMMA.value) {
        comma = p.advance();
        kids.append(comma);
    }

    # Optional py_code_block or free_code entries
    while not p.at_end() and not p.check(Tok.RBRACE.value) {
        if p.check(Tok.PYNLINE.value) {
            stmt = p.parse_py_code_block();
            stmt.is_enum_stmt = True;
            stmts.append(stmt);
            kids.append(stmt);
        } elif p.check(Tok.KW_WITH.value) {
            stmt = p.parse_free_code();
            stmt.is_enum_stmt = True;
            stmts.append(stmt);
            kids.append(stmt);
        } else {
            break;
        }
    }

    rbrace = p.expect(Tok.RBRACE.value);
    kids.append(rbrace);
    return (stmts, kids);
}

"""Parse assignment_list: (assignment | named_ref) (COMMA (assignment | named_ref))* COMMA?."""
def _parse_assignment_list(p: any) -> list {
    items: list = [];
    if p.check(Tok.RBRACE.value) or p.check(Tok.SEMI.value) {
        return items;
    }
    item = _parse_assignment_or_name(p);
    items.append(item);
    while p.check(Tok.COMMA.value) {
        peek_after = p.peek(1);
        # Stop if next is RBRACE or if this is trailing comma before py_code_block/free_code
        if peek_after.name == Tok.RBRACE.value
        or peek_after.name == Tok.PYNLINE.value
        or peek_after.name == Tok.KW_WITH.value {
            break;
        }
        p.advance();
        item = _parse_assignment_or_name(p);
        items.append(item);
    }
    return items;
}

"""Parse assignment or named_ref for global_var / enum lists.
    Always returns an Assignment node - bare names are wrapped for enum/global_var compatibility."""
def _parse_assignment_or_name(p: any) -> any {
    expr = parse_expression(p);
    if p.check(Tok.EQ.value) {
        eq_tok = p.advance();
        value = parse_expression(p);
        kids: list = [expr, eq_tok, value];
        nd = UniAssignment(target=[expr], value=value, type_tag=None, kid=kids);
        p.register_node(nd);
        return nd;
    }
    if p.check(Tok.COLON.value) {
        type_tag = parse_type_tag(p);
        value = None;
        if p.check(Tok.EQ.value) {
            eq_tok = p.advance();
            value = parse_expression(p);
            kids: list = [expr, type_tag, eq_tok, value];
        } else {
            kids: list = [expr, type_tag];
        }
        nd = UniAssignment(target=[expr], value=value, type_tag=type_tag, kid=kids);
        p.register_node(nd);
        return nd;
    }
    # Wrap bare name in Assignment node for enum/global_var compatibility
    nd = UniAssignment(target=[expr], value=None, type_tag=None, kid=[expr]);
    p.register_node(nd);
    return nd;
}

# ── Ability / Function Declaration ────────────────────────────────────
"""Parse ability: decorators? KW_ASYNC? (ability_decl | function_decl)."""
def parse_ability(p: any, decorators: list = []) -> any {
    kids: list = [];
    for d in decorators {
        kids.append(d);
    }

    is_async = False;
    if p.check(Tok.KW_ASYNC.value) {
        async_tok = p.advance();
        kids.append(async_tok);
        is_async = True;
    }

    # Determine if this is ability_decl (can) or function_decl (def)
    is_override = False;
    is_static = False;

    if p.check(Tok.KW_OVERRIDE.value) {
        override_tok = p.advance();
        kids.append(override_tok);
        is_override = True;
    }
    if p.check(Tok.KW_STATIC.value) {
        static_tok = p.advance();
        kids.append(static_tok);
        is_static = True;
    }

    if p.check(Tok.KW_CAN.value) {
        return _parse_ability_decl(
            p, kids, is_async, is_override, is_static, decorators
        );
    }
    if p.check(Tok.KW_DEF.value) {
        return _parse_function_decl(
            p, kids, is_async, is_override, is_static, decorators
        );
    }

    p.log_error("Expected 'can' or 'def' in ability declaration", p.peek());
    return None;
}

"""Parse ability_decl: KW_CAN access_tag? named_ref? event_clause (block_tail | KW_ABSTRACT? SEMI)."""
def _parse_ability_decl(
    p: any,
    kids: list,
    is_async: bool,
    is_override: bool,
    is_static: bool,
    decorators: list
) -> any {
    can_tok = p.expect(Tok.KW_CAN.value);
    kids.append(can_tok);

    # Optional access tag
    access = None;
    if p.check(Tok.COLON.value) {
        access = parse_access_tag(p);
        if access is not None {
            kids.append(access);
        }
    }

    # Optional name (can be omitted for event handlers)
    name_ref = None;
    if is_name_token(p.peek()) {
        name_ref = p.parse_named_ref();
        kids.append(name_ref);
    }

    # Event clause
    signature = parse_event_clause(p);
    kids.append(signature);

    # Block tail or abstract/semi
    body = None;
    is_abstract = False;
    if p.check(Tok.LBRACE.value) {
        block_result = parse_code_block_with_kids(p);
        body = block_result[0];
        kids.extend(block_result[1]);
    } elif p.check(Tok.KW_BY.value) {
        by_tok = p.advance();
        kids.append(by_tok);
        body = parse_expression(p);
        kids.append(body);
        semi = p.expect(Tok.SEMI.value);
        kids.append(semi);
    } else {
        if p.check(Tok.KW_ABSTRACT.value) {
            abstract_tok = p.advance();
            kids.append(abstract_tok);
            is_abstract = True;
        }
        semi = p.expect(Tok.SEMI.value);
        kids.append(semi);
    }

    if isinstance(body, list) {
        body_stmts = [
            s
            for s in body
            if isinstance(s, CodeBlockStmt)
        ];
    } else {
        body_stmts = body;
    }

    nd = UniAbility(
        name_ref=name_ref,
        is_async=is_async,
        is_override=is_override,
        is_static=is_static,
        is_abstract=is_abstract,
        access=access,
        signature=signature,
        body=body_stmts,
        kid=kids,
        decorators=decorators if len(decorators) > 0 else None
    );
    p.register_node(nd);
    return nd;
}

"""Parse function_decl: KW_DEF access_tag? named_ref func_decl? (block_tail | KW_ABSTRACT? SEMI)."""
def _parse_function_decl(
    p: any,
    kids: list,
    is_async: bool,
    is_override: bool,
    is_static: bool,
    decorators: list
) -> any {
    def_tok = p.expect(Tok.KW_DEF.value);
    kids.append(def_tok);

    # Optional access tag
    access = None;
    if p.check(Tok.COLON.value) {
        access = parse_access_tag(p);
        if access is not None {
            kids.append(access);
        }
    }

    # Name
    name_ref = p.parse_named_ref();
    kids.append(name_ref);

    # Optional func_decl (signature)
    signature = None;
    if p.check(Tok.LPAREN.value) or p.check(Tok.RETURN_HINT.value) {
        signature = parse_func_signature(p);
        kids.append(signature);
    }

    # Block tail or abstract/semi
    body = None;
    is_abstract = False;
    if p.check(Tok.LBRACE.value) {
        block_result = parse_code_block_with_kids(p);
        body = block_result[0];
        kids.extend(block_result[1]);
    } elif p.check(Tok.KW_BY.value) {
        by_tok = p.advance();
        kids.append(by_tok);
        body = parse_expression(p);
        kids.append(body);
        semi = p.expect(Tok.SEMI.value);
        kids.append(semi);
    } else {
        if p.check(Tok.KW_ABSTRACT.value) {
            abstract_tok = p.advance();
            kids.append(abstract_tok);
            is_abstract = True;
        }
        semi = p.expect(Tok.SEMI.value);
        kids.append(semi);
    }

    if isinstance(body, list) {
        body_stmts = [
            s
            for s in body
            if isinstance(s, CodeBlockStmt)
        ];
    } else {
        body_stmts = body;
    }

    nd = UniAbility(
        name_ref=name_ref,
        is_async=is_async,
        is_override=is_override,
        is_static=is_static,
        is_abstract=is_abstract,
        access=access,
        signature=signature,
        body=body_stmts,
        kid=kids,
        decorators=decorators if len(decorators) > 0 else None
    );
    p.register_node(nd);
    return nd;
}

# ── Event Clause ──────────────────────────────────────────────────────
"""Parse event_clause: KW_WITH expression? (KW_EXIT | KW_ENTRY)."""
def parse_event_clause(p: any) -> any {
    kids: list = [];
    with_tok = p.expect(Tok.KW_WITH.value);
    kids.append(with_tok);

    # Optional type expression
    arch_tag_info = None;
    if not p.check(Tok.KW_EXIT.value) and not p.check(Tok.KW_ENTRY.value) {
        arch_tag_info = parse_expression(p);
        kids.append(arch_tag_info);
    }

    # Exit or Entry
    if p.check(Tok.KW_EXIT.value) {
        event_tok = p.advance();
    } else {
        event_tok = p.expect(Tok.KW_ENTRY.value);
    }
    kids.append(event_tok);

    nd = UniEventSignature(event=event_tok, arch_tag_info=arch_tag_info, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── Function Signature ────────────────────────────────────────────────
"""Parse func_decl: (LPAREN func_decl_params? RPAREN) (RETURN_HINT pipe)?
                      | (RETURN_HINT pipe)."""
def parse_func_signature(p: any) -> any {
    # Return-only form
    if p.check(Tok.RETURN_HINT.value) {
        return_hint = p.advance();
        return_type = parse_pipe(p);
        kids: list = [return_hint];
        if return_type is not None {
            kids.append(return_type);
        }
        nd = UniFuncSignature(
            posonly_params=[],
            params=[],
            varargs=None,
            kwonlyargs=[],
            kwargs=None,
            return_type=return_type,
            kid=kids
        );
        p.register_node(nd);
        return nd;
    }

    # Full form
    lparen = p.expect(Tok.LPAREN.value);
    all_params: list = [];
    all_kids: list = [lparen];

    if not p.check(Tok.RPAREN.value) {
        param_result = _parse_func_params(p);
        all_params = param_result[0];
        all_kids.extend(param_result[1]);
    }

    rparen = p.expect(Tok.RPAREN.value);
    all_kids.append(rparen);

    # Optional return type
    return_type = None;
    if p.check(Tok.RETURN_HINT.value) {
        return_hint = p.advance();
        all_kids.append(return_hint);
        return_type = parse_pipe(p);
        if return_type is not None {
            all_kids.append(return_type);
        }
    }

    # Categorize parameters
    categories = _parse_parameter_categories(all_params);
    posonly = categories[0];
    params = categories[1];
    varargs = categories[2];
    kwonly = categories[3];
    kwargs = categories[4];

    nd = UniFuncSignature(
        posonly_params=posonly,
        params=params,
        varargs=varargs,
        kwonlyargs=kwonly,
        kwargs=kwargs,
        return_type=return_type,
        kid=all_kids
    );
    p.register_node(nd);
    return nd;
}

"""Parse func_decl_params: (param_var COMMA)* param_var COMMA?.
    Returns (params_list, kids_list)."""
def _parse_func_params(p: any) -> tuple {
    params: list = [];
    kids: list = [];

    param = _parse_param_var(p);
    params.append(param);
    kids.append(param);

    while p.check(Tok.COMMA.value) {
        comma = p.advance();
        kids.append(comma);
        if p.check(Tok.RPAREN.value) {
            break;
        }
        param = _parse_param_var(p);
        params.append(param);
        kids.append(param);
    }

    return (params, kids);
}

"""Parse param_var: (STAR_POW | STAR_MUL)? named_ref type_tag (EQ expression)?
                      | DIV
                      | STAR_MUL (bare, as separator)."""
def _parse_param_var(p: any) -> any {
    # Bare DIV separator
    if p.check(Tok.DIV.value) {
        return p.advance();
    }

    # Bare STAR_MUL separator (no name follows)
    if p.check(Tok.STAR_MUL.value) {
        peek1 = p.peek(1);
        if peek1.name == Tok.COMMA.value or peek1.name == Tok.RPAREN.value {
            return p.advance();
        }
    }

    # Full parameter
    kids: list = [];
    unpack = None;
    if p.check(Tok.STAR_MUL.value) or p.check(Tok.STAR_POW.value) {
        unpack = p.advance();
        kids.append(unpack);
    }

    name = p.parse_named_ref();
    kids.append(name);

    # Type tag
    type_tag = parse_type_tag(p);
    kids.append(type_tag);

    # Optional default value
    value = None;
    if p.check(Tok.EQ.value) {
        eq = p.advance();
        kids.append(eq);
        value = parse_expression(p);
        kids.append(value);
    }

    nd = UniParamVar(
        name=name, unpack=unpack, type_tag=type_tag, value=value, kid=kids
    );
    p.register_node(nd);
    return nd;
}

"""Categorize params into posonly, regular, varargs, kwonly, kwargs.
    Returns (posonly, params, varargs, kwonly, kwargs)."""
def _parse_parameter_categories(all_params: list) -> tuple {
    posonly: list = [];
    params: list = [];
    varargs = None;
    kwonly: list = [];
    kwargs = None;

    # First pass: check if there's a DIV separator
    has_div = False;
    for param in all_params {
        if isinstance(param, UniToken) and param.name == Tok.DIV.value {
            has_div = True;
            break;
        }
    }

    cur_state = "posonly" if has_div else "positional";

    for cur_nd in all_params {
        # State transitions on separator tokens
        if isinstance(cur_nd, UniToken) {
            if cur_nd.name == Tok.DIV.value {
                cur_state = "positional";
                continue;
            }
            if cur_nd.name == Tok.STAR_MUL.value {
                cur_state = "keyword_only";
                continue;
            }
        }
        if not isinstance(cur_nd, UniParamVar) {
            continue;
        }
        # Assign based on state
        if cur_state == "positional" {
            cur_nd.param_kind = ParamKind.NORMAL;
            params.append(cur_nd);
        } elif cur_state == "posonly" {
            cur_nd.param_kind = ParamKind.POSONLY;
            posonly.append(cur_nd);
        } elif cur_state == "keyword_only" {
            if cur_nd.unpack is not None and cur_nd.unpack.name == Tok.STAR_POW.value {
                cur_nd.param_kind = ParamKind.KWARG;
                kwargs = cur_nd;
            } else {
                cur_nd.param_kind = ParamKind.KWONLY;
                kwonly.append(cur_nd);
            }
        } else {
            # Check for *args and **kwargs
            if cur_nd.unpack is not None {
                if cur_nd.unpack.name == Tok.STAR_MUL.value {
                    cur_nd.param_kind = ParamKind.VARARG;
                    varargs = cur_nd;
                    cur_state = "keyword_only";
                } elif cur_nd.unpack.name == Tok.STAR_POW.value {
                    cur_nd.param_kind = ParamKind.KWARG;
                    kwargs = cur_nd;
                }
            } else {
                cur_nd.param_kind = ParamKind.NORMAL;
                params.append(cur_nd);
            }
        }
    }

    return (posonly, params, varargs, kwonly, kwargs);
}

# ── Has Statement ─────────────────────────────────────────────────────
"""Parse has_stmt: KW_STATIC? KW_HAS access_tag? has_assign_list SEMI."""
def parse_has_stmt(p: any) -> any {
    kids: list = [];
    is_static = False;

    if p.check(Tok.KW_STATIC.value) {
        static_tok = p.advance();
        kids.append(static_tok);
        is_static = True;
    }

    has_tok = p.expect(Tok.KW_HAS.value);
    kids.append(has_tok);

    # Optional access tag
    access = None;
    if p.check(Tok.COLON.value) {
        access = parse_access_tag(p);
        if access is not None {
            kids.append(access);
        }
    }

    # has_assign_list: (has_assign_list COMMA)? typed_has_clause
    vars_list = _parse_has_assign_list(p);
    for v in vars_list {
        kids.append(v);
    }

    semi = p.expect(Tok.SEMI.value);
    kids.append(semi);

    nd = UniArchHas(
        is_static=is_static, access=access, vars=vars_list, is_frozen=False, kid=kids
    );
    p.register_node(nd);
    return nd;
}

"""Parse has_assign_list: (has_assign_list COMMA)? typed_has_clause."""
def _parse_has_assign_list(p: any) -> list {
    vars_list: list = [];
    var = _parse_typed_has_clause(p);
    vars_list.append(var);
    while p.check(Tok.COMMA.value) {
        p.advance();
        var = _parse_typed_has_clause(p);
        vars_list.append(var);
    }
    return vars_list;
}

"""Parse typed_has_clause: named_ref type_tag (EQ expression | KW_BY KW_POST_INIT)?."""
def _parse_typed_has_clause(p: any) -> any {
    kids: list = [];
    name = p.parse_named_ref();
    kids.append(name);

    type_tag = parse_type_tag(p);
    kids.append(type_tag);

    value = None;
    defer = False;
    if p.check(Tok.EQ.value) {
        eq = p.advance();
        kids.append(eq);
        value = parse_expression(p);
        kids.append(value);
    } elif p.check(Tok.KW_BY.value) {
        by = p.advance();
        kids.append(by);
        post_init = p.expect(Tok.KW_POST_INIT.value);
        kids.append(post_init);
        defer = True;
    }

    nd = UniHasVar(name=name, type_tag=type_tag, value=value, defer=defer, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── Global Variable ───────────────────────────────────────────────────
"""Parse global_var: KW_GLOBAL access_tag? assignment_list SEMI."""
def parse_global_var(p: any) -> any {
    global_tok = p.expect(Tok.KW_GLOBAL.value);
    kids: list = [global_tok];

    # Optional access tag
    access = None;
    if p.check(Tok.COLON.value) {
        access = parse_access_tag(p);
        if access is not None {
            kids.append(access);
        }
    }

    # assignment_list
    assignments = _parse_assignment_list(p);
    for a in assignments {
        kids.append(a);
    }

    semi = p.expect(Tok.SEMI.value);
    kids.append(semi);

    nd = UniGlobalVars(
        access=access,
        assignments=[
            a
            for a in assignments
            if isinstance(a, UniAssignment)
        ],
        is_frozen=False,
        kid=kids
    );
    p.register_node(nd);
    return nd;
}

# ── Implementation Definition ─────────────────────────────────────────
"""Parse impl_def: decorators? KW_IMPL dotted_name impl_spec? impl_tail."""
def parse_impl_def(p: any, decorators: list = []) -> any {
    kids: list = [];
    for d in decorators {
        kids.append(d);
    }

    impl_tok = p.expect(Tok.KW_IMPL.value);
    kids.append(impl_tok);

    # dotted_name -> target
    dotted = _parse_dotted_name(p);
    target = dotted[0];
    kids.extend(dotted[1]);

    # Optional impl_spec: inherited_archs | func_decl | event_clause
    spec = None;
    if p.check(Tok.LPAREN.value) {
        # Disambiguate func_decl vs inherited_archs.
        # func_decl: LPAREN func_decl_params? RPAREN (RETURN_HINT expr)?
        # inherited_archs: LPAREN (expression (COMMA expression)*)? RPAREN
        # Heuristic: if LPAREN is followed by name COLON or */** or RPAREN RETURN_HINT,
        # it's func_decl; otherwise inherited_archs.
        is_func_sig = False;
        peek1 = p.peek(1);
        if peek1.name == Tok.RPAREN.value {
            # Empty parens — check for -> after
            peek2 = p.peek(2);
            if peek2.name == Tok.RETURN_HINT.value {
                is_func_sig = True;
            }
        } elif peek1.name in [Tok.STAR_MUL.value, Tok.STAR_POW.value] {
            # *args or **kwargs → func_decl
            is_func_sig = True;
        } elif is_name_token(peek1) {
            peek2 = p.peek(2);
            if peek2.name == Tok.COLON.value {
                # name: type → func_decl parameter
                is_func_sig = True;
            }
        }
        if is_func_sig {
            spec = parse_func_signature(p);
            kids.append(spec);
        } else {
            inh_result = _parse_inherited_archs(p);
            spec = inh_result[0];
            kids.extend(inh_result[1]);
        }
    } elif p.check(Tok.RETURN_HINT.value) {
        spec = parse_func_signature(p);
        kids.append(spec);
    } elif p.check(Tok.KW_WITH.value) {
        peek1 = p.peek(1);
        if peek1.name in [Tok.KW_ENTRY.value, Tok.KW_EXIT.value]
        or (peek1.name != Tok.KW_ENTRY.value and peek1.name != Tok.KW_EXIT.value) {
            spec = parse_event_clause(p);
            kids.append(spec);
        }
    }

    # impl_tail: enum_block | block_tail
    body = None;
    if p.check(Tok.LBRACE.value) {
        # Could be enum_block or code_block - peek ahead to decide
        # For now, try code_block (more common)
        block_result = parse_code_block_with_kids(p);
        body = block_result[0];
        kids.extend(block_result[1]);
    } elif p.check(Tok.KW_BY.value) {
        by_tok = p.advance();
        kids.append(by_tok);
        body = parse_expression(p);
        kids.append(body);
        semi = p.expect(Tok.SEMI.value);
        kids.append(semi);
    }

    if isinstance(body, list) {
        body_stmts = body;
    } else {
        body_stmts = body;
    }

    nd = UniImplDef(
        decorators=decorators if len(decorators) > 0 else None,
        target=target,
        spec=spec,
        body=body_stmts,
        kid=kids
    );
    p.register_node(nd);
    return nd;
}

# ── Semantic Definition ───────────────────────────────────────────────
"""Parse sem_def: KW_SEM dotted_name (EQ | KW_IS) STRING SEMI."""
def parse_sem_def(p: any) -> any {
    sem_tok = p.expect(Tok.KW_SEM.value);
    kids: list = [sem_tok];

    # dotted_name
    dotted = _parse_dotted_name(p);
    target = dotted[0];
    kids.extend(dotted[1]);

    # EQ or KW_IS
    if p.check(Tok.KW_IS.value) {
        is_tok = p.advance();
        kids.append(is_tok);
    } else {
        eq_tok = p.expect(Tok.EQ.value);
        kids.append(eq_tok);
    }

    # STRING value
    value = p.expect(Tok.STRING.value);
    kids.append(value);

    # SEMI
    semi = p.expect(Tok.SEMI.value);
    kids.append(semi);

    nd = UniSemDef(target=target, value=value, kid=kids);
    p.register_node(nd);
    return nd;
}
