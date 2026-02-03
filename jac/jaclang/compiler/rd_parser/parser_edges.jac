# Edge and spatial parsing for the Jac recursive descent parser.
#
# Handles edge_ref_chain, edge_op_ref, connect_op, disconnect_op,
# filter_compr, assign_compr, and filter_compare_list.
#
# All functions take `p` (the parser instance) as first argument.
import from jaclang.pycore.unitree {
    UniNode,
    Token as UniToken,
    Name as UniName,
    Expr,
    NameAtom,
    CompareExpr as UniCompareExpr,
    EdgeRefTrailer as UniEdgeRefTrailer,
    EdgeOpRef as UniEdgeOpRef,
    ConnectOp as UniConnectOp,
    DisconnectOp as UniDisconnectOp,
    FilterCompr as UniFilterCompr,
    AssignCompr as UniAssignCompr,
    KWPair as UniKWPair
}

import from jaclang.pycore.constant { Tokens as Tok, EdgeDir }

import from jaclang.compiler.rd_parser.ast_builder {
    EDGE_OP_TOKENS,
    CONNECT_OP_TOKENS,
    COMPARISON_OPS
}

import from jaclang.compiler.rd_parser.parser_exprs {
    parse_expression,
    parse_atomic_chain
}

# ── Edge Reference Chain ──────────────────────────────────────────────
"""Parse edge_ref_chain:
    LSQUARE KW_ASYNC? (KW_NODE|KW_EDGE)? expression? (edge_op_ref (filter_compr|expression)?)+ RSQUARE."""
def parse_edge_ref_chain(p: any) -> any {
    lsquare = p.expect(Tok.LSQUARE.value);
    kids: list = [lsquare];
    chain: list = [];

    # Optional async
    is_async = False;
    if p.check(Tok.KW_ASYNC.value) {
        async_tok = p.advance();
        kids.append(async_tok);
        is_async = True;
    }

    # Optional node/edge qualifier
    edges_only = False;
    if p.check(Tok.KW_EDGE.value) {
        edge_tok = p.advance();
        kids.append(edge_tok);
        edges_only = True;
    } elif p.check(Tok.KW_NODE.value) {
        node_tok = p.advance();
        kids.append(node_tok);
    }

    # Optional starting expression (before first edge_op_ref)
    if not _is_edge_op_start(p) and not p.check(Tok.RSQUARE.value) {
        expr = parse_expression(p);
        chain.append(expr);
        kids.append(expr);
    }

    # One or more: edge_op_ref (filter_compr | expression)?
    while _is_edge_op_start(p) {
        edge_op = _parse_edge_op_ref(p);
        chain.append(edge_op);
        kids.append(edge_op);

        # Optional filter_compr or expression after edge_op_ref
        if not p.check(Tok.RSQUARE.value) and not _is_edge_op_start(p) {
            if p.check(Tok.LPAREN.value) {
                # Could be filter_compr or just a parenthesized expression
                peek1 = p.peek(1);
                if peek1.name == Tok.NULL_OK.value or peek1.name == Tok.TYPE_OP.value {
                    filt = _parse_filter_compr_standalone(p);
                    chain.append(filt);
                    kids.append(filt);
                } else {
                    expr = parse_expression(p);
                    chain.append(expr);
                    kids.append(expr);
                }
            } elif not p.check(Tok.RSQUARE.value) {
                expr = parse_expression(p);
                chain.append(expr);
                kids.append(expr);
            }
        }
    }

    rsquare = p.expect(Tok.RSQUARE.value);
    kids.append(rsquare);

    nd = UniEdgeRefTrailer(
        chain=chain, edges_only=edges_only, is_async=is_async, kid=kids
    );
    p.register_node(nd);
    return nd;
}

"""Check if current token starts an edge_op_ref."""
def _is_edge_op_start(p: any) -> bool {
    tok = p.peek();
    edge_simple: list = [
        Tok.ARROW_R.value,
        Tok.ARROW_L.value,
        Tok.ARROW_BI.value,
        Tok.ARROW_R_P1.value,
        Tok.ARROW_L_P1.value
    ];
    return tok.name in edge_simple;
}

# ── Edge Op Ref ───────────────────────────────────────────────────────
"""Parse edge_op_ref: edge_to | edge_from | edge_any."""
def _parse_edge_op_ref(p: any) -> any {
    tok = p.peek();

    # edge_to: ARROW_R | ARROW_R_P1 typed_filter_compare_list ARROW_R_P2
    if tok.name == Tok.ARROW_R.value {
        arrow = p.advance();
        nd = UniEdgeOpRef(filter_cond=None, edge_dir=EdgeDir.OUT, kid=[arrow]);
        p.register_node(nd);
        return nd;
    }
    if tok.name == Tok.ARROW_R_P1.value {
        arrow_p1 = p.advance();
        fcond = _parse_typed_filter_compare_list(p);
        arrow_p2 = p.expect(Tok.ARROW_R_P2.value);
        kids: list = [arrow_p1, fcond, arrow_p2];
        nd = UniEdgeOpRef(filter_cond=fcond, edge_dir=EdgeDir.OUT, kid=kids);
        p.register_node(nd);
        return nd;
    }

    # edge_from: ARROW_L | ARROW_L_P1 typed_filter_compare_list ARROW_L_P2
    if tok.name == Tok.ARROW_L.value {
        arrow = p.advance();
        nd = UniEdgeOpRef(filter_cond=None, edge_dir=EdgeDir.IN, kid=[arrow]);
        p.register_node(nd);
        return nd;
    }

    # edge_any: ARROW_BI | ARROW_L_P1 typed_filter_compare_list ARROW_R_P2
    # edge_from: ARROW_L_P1 typed_filter_compare_list ARROW_L_P2
    if tok.name == Tok.ARROW_L_P1.value {
        arrow_p1 = p.advance();
        fcond = _parse_typed_filter_compare_list(p);
        # Determine direction: ARROW_L_P2 -> IN, ARROW_R_P2 -> ANY
        if p.check(Tok.ARROW_L_P2.value) {
            arrow_p2 = p.advance();
            kids: list = [arrow_p1, fcond, arrow_p2];
            nd = UniEdgeOpRef(filter_cond=fcond, edge_dir=EdgeDir.IN, kid=kids);
        } else {
            arrow_p2 = p.expect(Tok.ARROW_R_P2.value);
            kids: list = [arrow_p1, fcond, arrow_p2];
            nd = UniEdgeOpRef(filter_cond=fcond, edge_dir=EdgeDir.ANY, kid=kids);
        }
        p.register_node(nd);
        return nd;
    }

    if tok.name == Tok.ARROW_BI.value {
        arrow = p.advance();
        nd = UniEdgeOpRef(filter_cond=None, edge_dir=EdgeDir.ANY, kid=[arrow]);
        p.register_node(nd);
        return nd;
    }

    p.log_error("Expected edge operator", tok);
    return None;
}

# ── Connect Op ────────────────────────────────────────────────────────
"""Parse connect_op: connect_to | connect_from | connect_any."""
def parse_connect_op(p: any) -> any {
    tok = p.peek();

    # connect_to: CARROW_R | CARROW_R_P1 expression (COLON kw_expr_list)? CARROW_R_P2
    if tok.name == Tok.CARROW_R.value {
        arrow = p.advance();
        nd = UniConnectOp(
            conn_type=None, conn_assign=None, edge_dir=EdgeDir.OUT, kid=[arrow]
        );
        p.register_node(nd);
        return nd;
    }
    if tok.name == Tok.CARROW_R_P1.value {
        return _parse_connect_detailed(
            p, Tok.CARROW_R_P1.value, Tok.CARROW_R_P2.value, EdgeDir.OUT
        );
    }

    # connect_from: CARROW_L | CARROW_L_P1 expression (COLON kw_expr_list)? CARROW_L_P2
    if tok.name == Tok.CARROW_L.value {
        arrow = p.advance();
        nd = UniConnectOp(
            conn_type=None, conn_assign=None, edge_dir=EdgeDir.IN, kid=[arrow]
        );
        p.register_node(nd);
        return nd;
    }
    if tok.name == Tok.CARROW_L_P1.value {
        # Could be connect_from or connect_any
        arrow_p1 = p.advance();
        conn_type = parse_expression(p);
        conn_assign = None;
        if p.check(Tok.COLON.value) {
            colon = p.advance();
            kw_pairs = _parse_kw_expr_list(p);
            conn_assign = UniAssignCompr(assigns=kw_pairs, kid=kw_pairs);
            p.register_node(conn_assign);
        }
        # Determine direction: CARROW_L_P2 -> IN, CARROW_R_P2 -> ANY
        if p.check(Tok.CARROW_L_P2.value) {
            arrow_p2 = p.advance();
            edge_dir = EdgeDir.IN;
        } else {
            arrow_p2 = p.expect(Tok.CARROW_R_P2.value);
            edge_dir = EdgeDir.ANY;
        }
        kids: list = [arrow_p1, conn_type];
        if conn_assign is not None {
            kids.append(conn_assign);
        }
        kids.append(arrow_p2);
        nd = UniConnectOp(
            conn_type=conn_type, conn_assign=conn_assign, edge_dir=edge_dir, kid=kids
        );
        p.register_node(nd);
        return nd;
    }

    # connect_any: CARROW_BI
    if tok.name == Tok.CARROW_BI.value {
        arrow = p.advance();
        nd = UniConnectOp(
            conn_type=None, conn_assign=None, edge_dir=EdgeDir.ANY, kid=[arrow]
        );
        p.register_node(nd);
        return nd;
    }

    p.log_error("Expected connect operator", tok);
    return None;
}

"""Parse detailed connect op: P1 expression (COLON kw_expr_list)? P2."""
def _parse_connect_detailed(p: any, p1_tok: str, p2_tok: str, direction: any) -> any {
    arrow_p1 = p.advance();
    conn_type = parse_expression(p);
    conn_assign = None;
    if p.check(Tok.COLON.value) {
        colon = p.advance();
        kw_pairs = _parse_kw_expr_list(p);
        conn_assign = UniAssignCompr(assigns=kw_pairs, kid=kw_pairs);
        p.register_node(conn_assign);
    }
    arrow_p2 = p.expect(p2_tok);
    kids: list = [arrow_p1, conn_type];
    if conn_assign is not None {
        kids.append(conn_assign);
    }
    kids.append(arrow_p2);
    nd = UniConnectOp(
        conn_type=conn_type, conn_assign=conn_assign, edge_dir=direction, kid=kids
    );
    p.register_node(nd);
    return nd;
}

# ── Disconnect Op ─────────────────────────────────────────────────────
"""Parse disconnect_op: KW_DELETE edge_op_ref."""
def parse_disconnect_op(p: any) -> any {
    del_tok = p.expect(Tok.KW_DELETE.value);
    edge_spec = _parse_edge_op_ref(p);
    kids: list = [del_tok, edge_spec];
    nd = UniDisconnectOp(edge_spec=edge_spec, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── Filter Compr ──────────────────────────────────────────────────────
"""Parse filter_compr: LPAREN NULL_OK filter_compare_list RPAREN
                         | LPAREN TYPE_OP NULL_OK typed_filter_compare_list RPAREN."""
def _parse_filter_compr_standalone(p: any) -> any {
    lparen = p.expect(Tok.LPAREN.value);
    kids: list = [lparen];

    if p.check(Tok.TYPE_OP.value) {
        type_op = p.advance();
        kids.append(type_op);
        null_ok = p.expect(Tok.NULL_OK.value);
        kids.append(null_ok);
        filt = _parse_typed_filter_compare_list(p);
        kids.append(filt);
        rparen = p.expect(Tok.RPAREN.value);
        kids.append(rparen);
        # Return the typed filter with adjusted kids
        return filt;
    }

    null_ok = p.expect(Tok.NULL_OK.value);
    kids.append(null_ok);
    compares = parse_filter_compare_list(p);
    for c in compares {
        kids.append(c);
    }
    rparen = p.expect(Tok.RPAREN.value);
    kids.append(rparen);

    nd = UniFilterCompr(f_type=None, compares=compares, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── Typed Filter Compare List ─────────────────────────────────────────
"""Parse typed_filter_compare_list: expression (COLON filter_compare_list)?."""
def _parse_typed_filter_compare_list(p: any) -> any {
    type_expr = parse_expression(p);
    kids: list = [type_expr];
    compares: list = [];
    if p.check(Tok.COLON.value) {
        colon = p.advance();
        kids.append(colon);
        compares = parse_filter_compare_list(p);
        for c in compares {
            kids.append(c);
        }
    }
    nd = UniFilterCompr(f_type=type_expr, compares=compares, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── Filter Compare List ───────────────────────────────────────────────
"""Parse filter_compare_list: (filter_compare_list COMMA)? filter_compare_item."""
def parse_filter_compare_list(p: any) -> list {
    items: list = [];
    item = _parse_filter_compare_item(p);
    items.append(item);
    while p.check(Tok.COMMA.value) {
        p.advance();
        item = _parse_filter_compare_item(p);
        items.append(item);
    }
    return items;
}

"""Parse filter_compare_item: named_ref cmp_op expression."""
def _parse_filter_compare_item(p: any) -> any {
    name_ref = p.parse_named_ref();
    cmp_op = p.advance();
    expr = parse_expression(p);
    kids: list = [name_ref, cmp_op, expr];
    nd = UniCompareExpr(left=name_ref, ops=[cmp_op], rights=[expr], kid=kids);
    p.register_node(nd);
    return nd;
}

# ── KW Expr List ──────────────────────────────────────────────────────
"""Parse kw_expr_list: kw_expr (COMMA kw_expr)*."""
def _parse_kw_expr_list(p: any) -> list {
    pairs: list = [];
    pair = _parse_kw_expr(p);
    pairs.append(pair);
    while p.check(Tok.COMMA.value) {
        p.advance();
        pair = _parse_kw_expr(p);
        pairs.append(pair);
    }
    return pairs;
}

"""Parse kw_expr: named_ref EQ expression | STAR_POW expression."""
def _parse_kw_expr(p: any) -> any {
    kids: list = [];

    if p.check(Tok.STAR_POW.value) {
        star = p.advance();
        kids.append(star);
        value = parse_expression(p);
        kids.append(value);
        nd = UniKWPair(key=None, value=value, kid=kids);
        p.register_node(nd);
        return nd;
    }

    key = p.parse_named_ref();
    kids.append(key);
    eq = p.expect(Tok.EQ.value);
    kids.append(eq);
    value = parse_expression(p);
    kids.append(value);
    nd = UniKWPair(key=key, value=value, kid=kids);
    p.register_node(nd);
    return nd;
}
