# Match/switch pattern parsing for the Jac recursive descent parser.
#
# Handles match_stmt, switch_stmt, and all pattern types.
#
# All functions take `p` (the parser instance) as first argument.
import from jaclang.pycore.unitree {
    UniNode,
    Token as UniToken,
    Name as UniName,
    Expr,
    NameAtom,
    AtomExpr,
    CodeBlockStmt,
    MatchPattern,
    MatchStmt as UniMatchStmt,
    MatchCase as UniMatchCase,
    SwitchStmt as UniSwitchStmt,
    SwitchCase as UniSwitchCase,
    MatchOr as UniMatchOr,
    MatchAs as UniMatchAs,
    MatchWild as UniMatchWild,
    MatchValue as UniMatchValue,
    MatchSingleton as UniMatchSingleton,
    MatchSequence as UniMatchSequence,
    MatchMapping as UniMatchMapping,
    MatchKVPair as UniMatchKVPair,
    MatchStar as UniMatchStar,
    MatchArch as UniMatchArch,
    AtomTrailer as UniAtomTrailer
}

import from jaclang.pycore.constant { Tokens as Tok }

import from jaclang.compiler.rd_parser.ast_builder { is_name_token }

import from jaclang.compiler.rd_parser.parser_exprs { parse_expression }

import from jaclang.compiler.rd_parser.parser_stmts { parse_statement }

# ── Match Statement ───────────────────────────────────────────────────
"""Parse match_stmt: KW_MATCH expression LBRACE match_case_block+ RBRACE."""
def parse_match_stmt(p: any) -> any {
    match_tok = p.expect(Tok.KW_MATCH.value);
    target = parse_expression(p);
    lbrace = p.expect(Tok.LBRACE.value);
    kids: list = [match_tok, target, lbrace];
    cases: list = [];

    while p.check(Tok.KW_CASE.value) {
        case_nd = _parse_match_case_block(p);
        cases.append(case_nd);
        kids.append(case_nd);
    }

    rbrace = p.expect(Tok.RBRACE.value);
    kids.append(rbrace);

    nd = UniMatchStmt(target=target, cases=cases, kid=kids);
    p.register_node(nd);
    return nd;
}

"""Parse match_case_block: KW_CASE pattern_seq (KW_IF expression)? COLON statement+."""
def _parse_match_case_block(p: any) -> any {
    case_tok = p.expect(Tok.KW_CASE.value);
    pattern = _parse_pattern_seq(p);
    kids: list = [case_tok, pattern];

    # Optional guard
    guard = None;
    if p.check(Tok.KW_IF.value) {
        if_tok = p.advance();
        guard = parse_expression(p);
        kids.append(if_tok);
        kids.append(guard);
    }

    colon = p.expect(Tok.COLON.value);
    kids.append(colon);

    # One or more statements
    stmts: list = [];
    while (
        not p.at_end()
        and not p.check(Tok.KW_CASE.value)
        and not p.check(Tok.RBRACE.value)
        and not p.check(Tok.KW_DEFAULT.value)
    ) {
        stmt = parse_statement(p);
        if stmt is not None {
            stmts.append(stmt);
            kids.append(stmt);
        } else {
            break;
        }
    }

    nd = UniMatchCase(pattern=pattern, guard=guard, body=stmts, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── Switch Statement ──────────────────────────────────────────────────
"""Parse switch_stmt: KW_SWITCH expression LBRACE switch_case_block+ RBRACE."""
def parse_switch_stmt(p: any) -> any {
    switch_tok = p.expect(Tok.KW_SWITCH.value);
    target = parse_expression(p);
    lbrace = p.expect(Tok.LBRACE.value);
    kids: list = [switch_tok, target, lbrace];
    cases: list = [];

    while p.check(Tok.KW_CASE.value) or p.check(Tok.KW_DEFAULT.value) {
        case_nd = _parse_switch_case_block(p);
        cases.append(case_nd);
        kids.append(case_nd);
    }

    rbrace = p.expect(Tok.RBRACE.value);
    kids.append(rbrace);

    nd = UniSwitchStmt(target=target, cases=cases, kid=kids);
    p.register_node(nd);
    return nd;
}

"""Parse switch_case_block: (KW_CASE pattern_seq | KW_DEFAULT) COLON statement*."""
def _parse_switch_case_block(p: any) -> any {
    kids: list = [];
    pattern = None;

    if p.check(Tok.KW_CASE.value) {
        case_tok = p.advance();
        kids.append(case_tok);
        pattern = _parse_pattern_seq(p);
        kids.append(pattern);
    } else {
        default_tok = p.expect(Tok.KW_DEFAULT.value);
        kids.append(default_tok);
    }

    colon = p.expect(Tok.COLON.value);
    kids.append(colon);

    # Zero or more statements
    stmts: list = [];
    while (
        not p.at_end()
        and not p.check(Tok.KW_CASE.value)
        and not p.check(Tok.RBRACE.value)
        and not p.check(Tok.KW_DEFAULT.value)
    ) {
        stmt = parse_statement(p);
        if stmt is not None {
            stmts.append(stmt);
            kids.append(stmt);
        } else {
            break;
        }
    }

    nd = UniSwitchCase(pattern=pattern, body=stmts, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── Pattern Sequence ──────────────────────────────────────────────────
"""Parse pattern_seq: or_pattern | as_pattern."""
def _parse_pattern_seq(p: any) -> any {
    pattern = _parse_or_pattern(p);

    # Check for as_pattern: or_pattern KW_AS NAME
    if p.check(Tok.KW_AS.value) {
        as_tok = p.advance();
        name = p.parse_named_ref();
        kids: list = [pattern, as_tok, name];
        nd = UniMatchAs(name=name, pattern=pattern, kid=kids);
        p.register_node(nd);
        return nd;
    }

    return pattern;
}

"""Parse or_pattern: (pattern BW_OR)* pattern."""
def _parse_or_pattern(p: any) -> any {
    pattern = _parse_pattern(p);
    patterns: list = [pattern];
    kids: list = [pattern];

    while p.check(Tok.BW_OR.value) {
        or_tok = p.advance();
        kids.append(or_tok);
        next_pattern = _parse_pattern(p);
        patterns.append(next_pattern);
        kids.append(next_pattern);
    }

    if len(patterns) == 1 {
        return patterns[0];
    }

    nd = UniMatchOr(patterns=patterns, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── Pattern Dispatch ──────────────────────────────────────────────────
"""Parse pattern: literal | singleton | capture | sequence | mapping | attr | class."""
def _parse_pattern(p: any) -> any {
    tok = p.peek();

    # Singleton patterns: True, False, None
    if tok.name == Tok.NULL.value {
        val = p.advance();
        nd = UniMatchSingleton(value=val, kid=[val]);
        p.register_node(nd);
        return nd;
    }
    if tok.name == Tok.BOOL.value {
        val = p.advance();
        nd = UniMatchSingleton(value=val, kid=[val]);
        p.register_node(nd);
        return nd;
    }

    # Literal patterns: INT, FLOAT, STRING, negative numbers
    if tok.name == Tok.INT.value or tok.name == Tok.FLOAT.value {
        val = p.advance();
        nd = UniMatchValue(value=val, kid=[val]);
        p.register_node(nd);
        return nd;
    }
    if tok.name == Tok.STRING.value {
        val = p.advance();
        nd = UniMatchValue(value=val, kid=[val]);
        p.register_node(nd);
        return nd;
    }
    if tok.name == Tok.MINUS.value {
        minus = p.advance();
        num = p.advance();
        kids: list = [minus, num];
        nd = UniMatchValue(value=num, kid=kids);
        p.register_node(nd);
        return nd;
    }

    # Sequence pattern: [...]
    if tok.name == Tok.LSQUARE.value {
        return _parse_sequence_pattern(p, Tok.LSQUARE.value, Tok.RSQUARE.value);
    }

    # Sequence pattern with parens: (...)
    if tok.name == Tok.LPAREN.value {
        return _parse_sequence_pattern(p, Tok.LPAREN.value, Tok.RPAREN.value);
    }

    # Mapping pattern: {...}
    if tok.name == Tok.LBRACE.value {
        return _parse_mapping_pattern(p);
    }

    # Star patterns in list context: *name
    if tok.name == Tok.STAR_MUL.value {
        star = p.advance();
        name = p.parse_named_ref();
        kids: list = [star, name];
        nd = UniMatchStar(name=name, is_list=True, kid=kids);
        p.register_node(nd);
        return nd;
    }

    # Capture, attr, or class pattern: starts with NAME
    if is_name_token(tok) {
        return _parse_name_pattern(p);
    }

    p.log_error("Expected pattern", tok);
    return None;
}

"""Parse NAME-based patterns: capture, attr, or class."""
def _parse_name_pattern(p: any) -> any {
    # Parse the first name
    name = p.parse_named_ref();

    # Check for dotted name: NAME (DOT NAME)+
    if p.check(Tok.DOT.value) {
        # attr_pattern or class_pattern
        trailer = name;
        kids: list = [name];
        while p.check(Tok.DOT.value) {
            dot = p.advance();
            kids.append(dot);
            right = p.parse_named_ref();
            kids.append(right);
            trailer = UniAtomTrailer(
                target=trailer,
                right=right,
                is_attr=True,
                is_null_ok=False,
                kid=[trailer, dot, right]
            );
            p.register_node(trailer);
        }
        # Check for class pattern with LPAREN
        if p.check(Tok.LPAREN.value) {
            return _parse_class_pattern_args(p, trailer);
        }
        # Attr pattern
        nd = UniMatchValue(value=trailer, kid=[trailer]);
        p.register_node(nd);
        return nd;
    }

    # Check for class pattern: NAME LPAREN
    if p.check(Tok.LPAREN.value) {
        return _parse_class_pattern_args(p, name);
    }

    # Wildcard: _
    if name.value == "_" {
        nd = UniMatchWild(kid=[name]);
        p.register_node(nd);
        return nd;
    }

    # Capture pattern: NAME
    nd = UniMatchAs(name=name, pattern=None, kid=[name]);
    p.register_node(nd);
    return nd;
}

"""Parse class pattern arguments: LPAREN (pattern_list | kw_pattern_list | both)? RPAREN."""
def _parse_class_pattern_args(p: any, name: any) -> any {
    lparen = p.expect(Tok.LPAREN.value);
    kids: list = [name, lparen];
    arg_patterns: list = [];
    kw_patterns: list = [];

    if not p.check(Tok.RPAREN.value) {
        # Try parsing patterns
        first = _parse_pattern_or_kw(p);
        if isinstance(first, UniMatchKVPair) {
            kw_patterns.append(first);
            kids.append(first);
            while p.check(Tok.COMMA.value) {
                comma = p.advance();
                kids.append(comma);
                if p.check(Tok.RPAREN.value) {
                    break;
                }
                kw = _parse_kw_pattern(p);
                kw_patterns.append(kw);
                kids.append(kw);
            }
        } else {
            arg_patterns.append(first);
            kids.append(first);
            while p.check(Tok.COMMA.value) {
                comma = p.advance();
                kids.append(comma);
                if p.check(Tok.RPAREN.value) {
                    break;
                }
                next_item = _parse_pattern_or_kw(p);
                if isinstance(next_item, UniMatchKVPair) {
                    kw_patterns.append(next_item);
                    kids.append(next_item);
                    while p.check(Tok.COMMA.value) {
                        comma2 = p.advance();
                        kids.append(comma2);
                        if p.check(Tok.RPAREN.value) {
                            break;
                        }
                        kw = _parse_kw_pattern(p);
                        kw_patterns.append(kw);
                        kids.append(kw);
                    }
                    break;
                }
                arg_patterns.append(next_item);
                kids.append(next_item);
            }
        }
    }

    rparen = p.expect(Tok.RPAREN.value);
    kids.append(rparen);

    nd = UniMatchArch(
        name=name,
        arg_patterns=arg_patterns if len(arg_patterns) > 0 else None,
        kw_patterns=kw_patterns if len(kw_patterns) > 0 else None,
        kid=kids
    );
    p.register_node(nd);
    return nd;
}

"""Parse either a positional pattern or a keyword pattern.
    Keyword pattern: named_ref EQ pattern_seq."""
def _parse_pattern_or_kw(p: any) -> any {
    # If we see NAME EQ, it's a keyword pattern
    if is_name_token(p.peek()) {
        peek1 = p.peek(1);
        if peek1.name == Tok.EQ.value {
            return _parse_kw_pattern(p);
        }
    }
    return _parse_pattern_seq(p);
}

"""Parse kw_pattern: named_ref EQ pattern_seq."""
def _parse_kw_pattern(p: any) -> any {
    name = p.parse_named_ref();
    eq = p.expect(Tok.EQ.value);
    value = _parse_pattern_seq(p);
    kids: list = [name, eq, value];
    nd = UniMatchKVPair(key=name, value=value, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── Sequence Pattern ──────────────────────────────────────────────────
"""Parse sequence_pattern: LSQUARE/LPAREN list_inner_pattern (COMMA list_inner_pattern)* RSQUARE/RPAREN."""
def _parse_sequence_pattern(p: any, open_tok: str, close_tok: str) -> any {
    opener = p.expect(open_tok);
    kids: list = [opener];
    patterns: list = [];

    if not p.check(close_tok) {
        inner = _parse_list_inner_pattern(p);
        patterns.append(inner);
        kids.append(inner);
        while p.check(Tok.COMMA.value) {
            comma = p.advance();
            kids.append(comma);
            if p.check(close_tok) {
                break;
            }
            inner = _parse_list_inner_pattern(p);
            patterns.append(inner);
            kids.append(inner);
        }
    }

    closer = p.expect(close_tok);
    kids.append(closer);

    nd = UniMatchSequence(values=patterns, kid=kids);
    p.register_node(nd);
    return nd;
}

"""Parse list_inner_pattern: pattern_seq | STAR_MUL NAME."""
def _parse_list_inner_pattern(p: any) -> any {
    if p.check(Tok.STAR_MUL.value) {
        star = p.advance();
        name = p.parse_named_ref();
        kids: list = [star, name];
        nd = UniMatchStar(name=name, is_list=True, kid=kids);
        p.register_node(nd);
        return nd;
    }
    return _parse_pattern_seq(p);
}

# ── Mapping Pattern ───────────────────────────────────────────────────
"""Parse mapping_pattern: LBRACE (dict_inner_pattern (COMMA dict_inner_pattern)*)? RBRACE."""
def _parse_mapping_pattern(p: any) -> any {
    lbrace = p.expect(Tok.LBRACE.value);
    kids: list = [lbrace];
    patterns: list = [];

    if not p.check(Tok.RBRACE.value) {
        inner = _parse_dict_inner_pattern(p);
        patterns.append(inner);
        kids.append(inner);
        while p.check(Tok.COMMA.value) {
            comma = p.advance();
            kids.append(comma);
            if p.check(Tok.RBRACE.value) {
                break;
            }
            inner = _parse_dict_inner_pattern(p);
            patterns.append(inner);
            kids.append(inner);
        }
    }

    rbrace = p.expect(Tok.RBRACE.value);
    kids.append(rbrace);

    nd = UniMatchMapping(values=patterns, kid=kids);
    p.register_node(nd);
    return nd;
}

"""Parse dict_inner_pattern: literal_pattern COLON pattern_seq | STAR_POW NAME."""
def _parse_dict_inner_pattern(p: any) -> any {
    if p.check(Tok.STAR_POW.value) {
        star = p.advance();
        name = p.parse_named_ref();
        kids: list = [star, name];
        nd = UniMatchStar(name=name, is_list=False, kid=kids);
        p.register_node(nd);
        return nd;
    }
    key = _parse_pattern(p);
    colon = p.expect(Tok.COLON.value);
    value = _parse_pattern_seq(p);
    kids: list = [key, colon, value];
    nd = UniMatchKVPair(key=key, value=value, kid=kids);
    p.register_node(nd);
    return nd;
}
