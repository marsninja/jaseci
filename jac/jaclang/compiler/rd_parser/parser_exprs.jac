# Expression parsing for the Jac recursive descent parser.
#
# All functions take `p` (the parser instance) as first argument.
# Type is `any` to avoid circular imports with parser.jac.
# Functions build kid lists manually (no KidCollector).
import from jaclang.pycore.unitree {
    UniNode,
    Token as UniToken,
    Name as UniName,
    String as UniString,
    Source as UniSource,
    Expr,
    AtomExpr,
    NameAtom,
    CodeBlockStmt,
    BinaryExpr as UniBinaryExpr,
    CompareExpr as UniCompareExpr,
    BoolExpr as UniBoolExpr,
    UnaryExpr as UniUnaryExpr,
    IfElseExpr as UniIfElseExpr,
    ConcurrentExpr as UniConcurrentExpr,
    AwaitExpr as UniAwaitExpr,
    YieldExpr as UniYieldExpr,
    LambdaExpr as UniLambdaExpr,
    AtomTrailer as UniAtomTrailer,
    FuncCall as UniFuncCall,
    AtomUnit as UniAtomUnit,
    IndexSlice as UniIndexSlice,
    TypeRef as UniTypeRef,
    ListVal as UniListVal,
    SetVal as UniSetVal,
    TupleVal as UniTupleVal,
    DictVal as UniDictVal,
    KVPair as UniKVPair,
    KWPair as UniKWPair,
    ListCompr as UniListCompr,
    GenCompr as UniGenCompr,
    SetCompr as UniSetCompr,
    DictCompr as UniDictCompr,
    InnerCompr as UniInnerCompr,
    MultiString as UniMultiString,
    FString as UniFString,
    FormattedValue as UniFormattedValue,
    Assignment as UniAssignment,
    SubTag as UniSubTag,
    FuncSignature as UniFuncSignature,
    ParamVar as UniParamVar,
    BuiltinType as UniBuiltinType,
    SpecialVarRef as UniSpecialVarRef,
    FilterCompr as UniFilterCompr,
    AssignCompr as UniAssignCompr
}

import from jaclang.pycore.constant { Tokens as Tok, EdgeDir }

import from jaclang.compiler.rd_parser.lexer {
    KEYWORD_MAP,
    BUILTIN_TYPE_MAP,
    SPECIAL_REF_TOKENS,
    EOF_NAME
}

import from jaclang.compiler.rd_parser.ast_builder {
    is_eof_token,
    is_name_token,
    is_special_ref_token,
    wrap_special_ref,
    AUGMENTED_ASSIGN_OPS,
    COMPARISON_OPS,
    UNARY_PREFIX_OPS,
    EDGE_OP_TOKENS,
    CONNECT_OP_TOKENS,
    ALL_EDGE_CONNECT_TOKENS,
    EDGE_CONNECT_START_TOKENS,
    CONNECT_OP_START_TOKENS,
    EXPR_SYNC_TOKENS
}

# ── Expression (lowest precedence) ──────────────────────────────────────
def parse_expression(
    p: any
) -> any {
    # expression: concurrent_expr (KW_IF expression KW_ELSE expression)?
    #           | lambda_expr
    if p.check(Tok.KW_LAMBDA.value) {
        return parse_lambda(p);
    }

    value = parse_concurrent(p);

    if p.check(Tok.KW_IF.value) {
        if_tok = p.advance();
        condition = parse_expression(p);
        else_tok = p.expect(Tok.KW_ELSE.value);
        else_value = parse_expression(p);
        kids: list = [value, if_tok, condition, else_tok, else_value];
        nd = UniIfElseExpr(
            condition=condition, value=value, else_value=else_value, kid=kids
        );
        p.register_node(nd);
        return nd;
    }
    return value;
}

# ── Concurrent ──────────────────────────────────────────────────────────
def parse_concurrent(
    p: any
) -> any {
    # concurrent_expr: (KW_FLOW | KW_WAIT)? walrus_assign
    tok = p.match_any(Tok.KW_FLOW.value, Tok.KW_WAIT.value);
    value = parse_walrus(p);
    if tok is not None {
        kids: list = [tok, value];
        nd = UniConcurrentExpr(tok=tok, target=value, kid=kids);
        p.register_node(nd);
        return nd;
    }
    return value;
}

# ── Walrus assignment ───────────────────────────────────────────────────
def parse_walrus(
    p: any
) -> any {
    # walrus_assign: (named_ref WALRUS_EQ)? by_expr
    if is_name_token(p.peek()) and p.peek(1).name == Tok.WALRUS_EQ.value {
        name = p.parse_named_ref();
        op = p.advance();
        value = parse_by_expr(p);
        kids: list = [name, op, value];
        nd = UniBinaryExpr(left=name, op=op, right=value, kid=kids);
        p.register_node(nd);
        return nd;
    }
    return parse_by_expr(p);
}

# ── By expression ──────────────────────────────────────────────────────
def parse_by_expr(
    p: any
) -> any {
    # by_expr: pipe | pipe KW_BY by_expr  (right-associative)
    left = parse_pipe(p);
    if p.check(Tok.KW_BY.value) {
        op = p.advance();
        right = parse_by_expr(p);
        kids: list = [left, op, right];
        nd = UniBinaryExpr(left=left, op=op, right=right, kid=kids);
        p.register_node(nd);
        return nd;
    }
    return left;
}

# ── Lambda ──────────────────────────────────────────────────────────────
def parse_lambda(
    p: any
) -> any {
    # lambda_expr: KW_LAMBDA func_decl_params (RETURN_HINT expression)?
    #              (COLON expression | code_block)
    #            | KW_LAMBDA func_decl? (COLON expression | code_block)
    lambda_tok = p.expect(Tok.KW_LAMBDA.value);
    kids: list = [lambda_tok];

    # Parse optional signature
    sig = None;
    if not p.check(Tok.COLON.value)
    and not p.check(Tok.LBRACE.value)
    and not p.check(Tok.RETURN_HINT.value) {
        sig = p.parse_func_signature();
        if sig is not None {
            kids.append(sig);
        }
    }

    # Optional return hint
    ret_type = None;
    if p.check(Tok.RETURN_HINT.value) {
        hint_tok = p.advance();
        kids.append(hint_tok);
        ret_type = parse_expression(p);
        kids.append(ret_type);
        if sig is not None {
            sig.return_type = ret_type;
        }
    }

    # Body: COLON expression or code_block
    if p.check(Tok.COLON.value) {
        colon = p.advance();
        kids.append(colon);
        body_expr = parse_expression(p);
        kids.append(body_expr);
        nd = UniLambdaExpr(body=body_expr, kid=kids, signature=sig);
    } else {
        body_stmts = p.parse_code_block();
        for s in body_stmts {
            kids.append(s);
        }
        nd = UniLambdaExpr(body=body_stmts, kid=kids, signature=sig);
    }
    p.register_node(nd);
    return nd;
}

# ── Pipe forward ────────────────────────────────────────────────────────
def parse_pipe(
    p: any
) -> any {
    # pipe: (pipe PIPE_FWD)? pipe_back  (left-associative)
    left = parse_pipe_back(p);
    while p.check(Tok.PIPE_FWD.value) {
        op = p.advance();
        right = parse_pipe_back(p);
        kids: list = [left, op, right];
        left = UniBinaryExpr(left=left, op=op, right=right, kid=kids);
        p.register_node(left);
    }
    return left;
}

# ── Pipe backward ──────────────────────────────────────────────────────
def parse_pipe_back(
    p: any
) -> any {
    # pipe_back: (pipe_back PIPE_BKWD)? bitwise_or
    left = parse_bitwise_or(p);
    while p.check(Tok.PIPE_BKWD.value) {
        op = p.advance();
        right = parse_bitwise_or(p);
        kids: list = [left, op, right];
        left = UniBinaryExpr(left=left, op=op, right=right, kid=kids);
        p.register_node(left);
    }
    return left;
}

# ── Bitwise OR ──────────────────────────────────────────────────────────
def parse_bitwise_or(
    p: any
) -> any {
    # bitwise_or: (bitwise_or BW_OR)? bitwise_xor
    left = parse_bitwise_xor(p);
    while p.check(Tok.BW_OR.value) {
        op = p.advance();
        right = parse_bitwise_xor(p);
        kids: list = [left, op, right];
        left = UniBinaryExpr(left=left, op=op, right=right, kid=kids);
        p.register_node(left);
    }
    return left;
}

# ── Bitwise XOR ─────────────────────────────────────────────────────────
def parse_bitwise_xor(
    p: any
) -> any {
    # bitwise_xor: (bitwise_xor BW_XOR)? bitwise_and
    left = parse_bitwise_and(p);
    while p.check(Tok.BW_XOR.value) {
        op = p.advance();
        right = parse_bitwise_and(p);
        kids: list = [left, op, right];
        left = UniBinaryExpr(left=left, op=op, right=right, kid=kids);
        p.register_node(left);
    }
    return left;
}

# ── Bitwise AND ─────────────────────────────────────────────────────────
def parse_bitwise_and(
    p: any
) -> any {
    # bitwise_and: (bitwise_and BW_AND)? shift
    left = parse_shift(p);
    while p.check(Tok.BW_AND.value) {
        op = p.advance();
        right = parse_shift(p);
        kids: list = [left, op, right];
        left = UniBinaryExpr(left=left, op=op, right=right, kid=kids);
        p.register_node(left);
    }
    return left;
}

# ── Shift ───────────────────────────────────────────────────────────────
def parse_shift(
    p: any
) -> any {
    # shift: (shift (RSHIFT | LSHIFT))? logical_or
    left = parse_logical_or(p);
    while p.check_any(Tok.RSHIFT.value, Tok.LSHIFT.value) {
        op = p.advance();
        right = parse_logical_or(p);
        kids: list = [left, op, right];
        left = UniBinaryExpr(left=left, op=op, right=right, kid=kids);
        p.register_node(left);
    }
    return left;
}

# ── Logical OR ──────────────────────────────────────────────────────────
def parse_logical_or(
    p: any
) -> any {
    # logical_or: logical_and (KW_OR logical_and)*
    first = parse_logical_and(p);
    if not p.check(Tok.KW_OR.value) {
        return first;
    }
    values: list = [first];
    kids: list = [first];
    op = None;
    while p.check(Tok.KW_OR.value) {
        op_tok = p.advance();
        if op is None {
            op = op_tok;
        }
        next_val = parse_logical_and(p);
        values.append(next_val);
        kids.append(op_tok);
        kids.append(next_val);
    }
    nd = UniBoolExpr(op=op, values=values, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── Logical AND ─────────────────────────────────────────────────────────
def parse_logical_and(
    p: any
) -> any {
    # logical_and: logical_not (KW_AND logical_not)*
    first = parse_logical_not(p);
    if not p.check(Tok.KW_AND.value) {
        return first;
    }
    values: list = [first];
    kids: list = [first];
    op = None;
    while p.check(Tok.KW_AND.value) {
        op_tok = p.advance();
        if op is None {
            op = op_tok;
        }
        next_val = parse_logical_not(p);
        values.append(next_val);
        kids.append(op_tok);
        kids.append(next_val);
    }
    nd = UniBoolExpr(op=op, values=values, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── Logical NOT ─────────────────────────────────────────────────────────
def parse_logical_not(
    p: any
) -> any {
    # logical_not: NOT logical_not | compare
    if p.check(Tok.NOT.value) {
        op = p.advance();
        operand = parse_logical_not(p);
        kids: list = [op, operand];
        nd = UniUnaryExpr(operand=operand, op=op, kid=kids);
        p.register_node(nd);
        return nd;
    }
    return parse_compare(p);
}

# ── Compare ─────────────────────────────────────────────────────────────
def parse_compare(
    p: any
) -> any {
    # compare: (arithmetic cmp_op)* arithmetic
    left = parse_arithmetic(p);
    if p.peek().name not in COMPARISON_OPS {
        return left;
    }
    ops: list = [];
    rights: list = [];
    kids: list = [left];
    while p.peek().name in COMPARISON_OPS {
        op = p.advance();
        right = parse_arithmetic(p);
        ops.append(op);
        rights.append(right);
        kids.append(op);
        kids.append(right);
    }
    nd = UniCompareExpr(left=left, rights=rights, ops=ops, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── Arithmetic (+, -) ──────────────────────────────────────────────────
def parse_arithmetic(
    p: any
) -> any {
    # arithmetic: (arithmetic (MINUS | PLUS))? term
    left = parse_term(p);
    while p.check_any(Tok.PLUS.value, Tok.MINUS.value) {
        op = p.advance();
        right = parse_term(p);
        kids: list = [left, op, right];
        left = UniBinaryExpr(left=left, op=op, right=right, kid=kids);
        p.register_node(left);
    }
    return left;
}

# ── Term (*, /, //, %, @) ──────────────────────────────────────────────
def parse_term(
    p: any
) -> any {
    # term: (term (MOD | DIV | FLOOR_DIV | STAR_MUL | DECOR_OP))? power
    left = parse_power(p);
    while p.check_any(
        Tok.MOD.value,
        Tok.DIV.value,
        Tok.FLOOR_DIV.value,
        Tok.STAR_MUL.value,
        Tok.DECOR_OP.value
    ) {
        op = p.advance();
        right = parse_power(p);
        kids: list = [left, op, right];
        left = UniBinaryExpr(left=left, op=op, right=right, kid=kids);
        p.register_node(left);
    }
    return left;
}

# ── Power (**) ──────────────────────────────────────────────────────────
def parse_power(
    p: any
) -> any {
    # power: (power STAR_POW)? factor  -- right-associative
    left = parse_factor(p);
    if p.check(Tok.STAR_POW.value) {
        op = p.advance();
        right = parse_power(p);
        kids: list = [left, op, right];
        nd = UniBinaryExpr(left=left, op=op, right=right, kid=kids);
        p.register_node(nd);
        return nd;
    }
    return left;
}

# ── Factor (unary -, +, ~) ─────────────────────────────────────────────
def parse_factor(
    p: any
) -> any {
    # factor: (BW_NOT | MINUS | PLUS) factor | connect
    if p.peek().name in UNARY_PREFIX_OPS {
        op = p.advance();
        operand = parse_factor(p);
        kids: list = [op, operand];
        nd = UniUnaryExpr(operand=operand, op=op, kid=kids);
        p.register_node(nd);
        return nd;
    }
    return parse_connect(p);
}

# ── Connect expressions ────────────────────────────────────────────────
def parse_connect(
    p: any
) -> any {
    # connect: (connect (connect_op | disconnect_op))? atomic_pipe
    left = parse_atomic_pipe(p);
    while p.peek().name in CONNECT_OP_START_TOKENS
    or (p.check(Tok.KW_DELETE.value) and p.peek(1).name in EDGE_OP_TOKENS) {
        if p.check(Tok.KW_DELETE.value) {
            # disconnect_op: KW_DELETE edge_op_ref
            op = p.parse_disconnect_op();
        } else {
            op = p.parse_connect_op();
        }
        right = parse_atomic_pipe(p);
        kids: list = [left, op, right];
        left = UniBinaryExpr(left=left, op=op, right=right, kid=kids);
        p.register_node(left);
    }
    return left;
}

# ── Atomic pipe forward (:>) ───────────────────────────────────────────
def parse_atomic_pipe(
    p: any
) -> any {
    # atomic_pipe: (atomic_pipe A_PIPE_FWD)? atomic_pipe_back
    left = parse_atomic_pipe_back(p);
    while p.check(Tok.A_PIPE_FWD.value) {
        op = p.advance();
        right = parse_atomic_pipe_back(p);
        kids: list = [left, op, right];
        left = UniBinaryExpr(left=left, op=op, right=right, kid=kids);
        p.register_node(left);
    }
    return left;
}

# ── Atomic pipe backward (<:) ──────────────────────────────────────────
def parse_atomic_pipe_back(
    p: any
) -> any {
    # atomic_pipe_back: (atomic_pipe_back A_PIPE_BKWD)? os_spawn
    left = parse_spawn(p);
    while p.check(Tok.A_PIPE_BKWD.value) {
        op = p.advance();
        right = parse_spawn(p);
        kids: list = [left, op, right];
        left = UniBinaryExpr(left=left, op=op, right=right, kid=kids);
        p.register_node(left);
    }
    return left;
}

# ── Spawn ───────────────────────────────────────────────────────────────
def parse_spawn(
    p: any
) -> any {
    # os_spawn: (os_spawn KW_SPAWN)? unpack
    left = parse_unpack(p);
    while p.check(Tok.KW_SPAWN.value) {
        op = p.advance();
        right = parse_unpack(p);
        kids: list = [left, op, right];
        left = UniBinaryExpr(left=left, op=op, right=right, kid=kids);
        p.register_node(left);
    }
    return left;
}

# ── Unpack (*) ──────────────────────────────────────────────────────────
def parse_unpack(
    p: any
) -> any {
    # unpack: STAR_MUL? ref
    if p.check(Tok.STAR_MUL.value) {
        op = p.advance();
        operand = parse_ref(p);
        kids: list = [op, operand];
        nd = UniUnaryExpr(operand=operand, op=op, kid=kids);
        p.register_node(nd);
        return nd;
    }
    return parse_ref(p);
}

# ── Reference (&) ──────────────────────────────────────────────────────
def parse_ref(
    p: any
) -> any {
    # ref: BW_AND? await_expr
    if p.check(Tok.BW_AND.value) {
        # Make sure this is a reference, not bitwise and
        # Reference & is a prefix unary op, bitwise & is infix
        op = p.advance();
        operand = parse_await(p);
        kids: list = [op, operand];
        nd = UniUnaryExpr(operand=operand, op=op, kid=kids);
        p.register_node(nd);
        return nd;
    }
    return parse_await(p);
}

# ── Await ───────────────────────────────────────────────────────────────
def parse_await(
    p: any
) -> any {
    # await_expr: KW_AWAIT? pipe_call
    if p.check(Tok.KW_AWAIT.value) {
        await_tok = p.advance();
        target = parse_pipe_call(p);
        kids: list = [await_tok, target];
        nd = UniAwaitExpr(target=target, kid=kids);
        p.register_node(nd);
        return nd;
    }
    return parse_pipe_call(p);
}

# ── Pipe call (prefix |>, :>, spawn) ───────────────────────────────────
def parse_pipe_call(
    p: any
) -> any {
    # pipe_call: (PIPE_FWD | A_PIPE_FWD | KW_SPAWN)? atomic_chain
    if p.check_any(Tok.PIPE_FWD.value, Tok.A_PIPE_FWD.value, Tok.KW_SPAWN.value) {
        op = p.advance();
        operand = parse_atomic_chain(p);
        kids: list = [op, operand];
        nd = UniUnaryExpr(operand=operand, op=op, kid=kids);
        p.register_node(nd);
        return nd;
    }
    return parse_atomic_chain(p);
}

# ── Atomic chain (., [], (), ?) ────────────────────────────────────────
def parse_atomic_chain(
    p: any
) -> any {
    # atomic_chain: atomic_chain NULL_OK? (filter_compr|assign_compr|index_slice)
    #             | atomic_chain NULL_OK? (DOT_BKWD|DOT_FWD|DOT) named_ref
    #             | (atomic_call | atom | edge_ref_chain)
    left = parse_atom_or_edge(p);

    while not p.at_end() {
        # Check for null-safe chaining: ?
        null_ok_tok = None;
        is_null = False;

        if p.check(Tok.NULL_OK.value) {
            peek1_name = p.peek(1).name;
            if peek1_name in [
                Tok.DOT.value,
                Tok.DOT_FWD.value,
                Tok.DOT_BKWD.value,
                Tok.LSQUARE.value,
                Tok.LPAREN.value
            ] {
                null_ok_tok = p.advance();
                is_null = True;
            } else {
                break;
            }
        }

        # Dot access
        if p.check_any(Tok.DOT.value, Tok.DOT_FWD.value, Tok.DOT_BKWD.value) {
            dot = p.advance();
            right = p.parse_named_ref();
            kids: list = [left];
            if null_ok_tok is not None {
                kids.append(null_ok_tok);
            }
            kids.append(dot);
            kids.append(right);
            left = UniAtomTrailer(
                target=left, right=right, is_attr=True, is_null_ok=is_null, kid=kids
            );
            p.register_node(left);
            continue;
        }

        # Function call
        if p.check(Tok.LPAREN.value) {
            left = _parse_call_or_gencompr(p, left, null_ok_tok);
            continue;
        }

        # Index/slice
        if p.check(Tok.LSQUARE.value) {
            idx = parse_index_slice(p);
            kids: list = [left];
            if null_ok_tok is not None {
                kids.append(null_ok_tok);
            }
            kids.append(idx);
            left = UniAtomTrailer(
                target=left, right=idx, is_attr=False, is_null_ok=is_null, kid=kids
            );
            p.register_node(left);
            continue;
        }

        # Nothing matched after null_ok - shouldn't happen (we checked peek above)
        break;
    }
    return left;
}

def parse_atom_or_edge(p: any) -> any {
    # Dispatch between atom and edge_ref_chain
    # edge_ref_chain starts with LSQUARE followed by edge keywords/operators
    if p.check(Tok.LSQUARE.value) {
        # Could be list_val, index_slice, or edge_ref_chain
        # Edge ref chain: [ async? (node|edge)? expr? edge_op_ref ... ]
        # List val: [ expr, expr, ... ]
        # Disambiguate by looking ahead
        peek1 = p.peek(1);
        peek2 = p.peek(2);
        edge_start_names = [Tok.KW_ASYNC.value, Tok.KW_NODE.value, Tok.KW_EDGE.value];
        if (peek1.name in edge_start_names or peek1.name in EDGE_OP_TOKENS) {
            return p.parse_edge_ref_chain();
        }
        # Also check for [name edge_op ...] pattern (e.g., [self-->])
        if is_name_token(peek1) and peek2.name in EDGE_OP_TOKENS {
            return p.parse_edge_ref_chain();
        }
    }
    return parse_atom(p);
}

# ── Function call ──────────────────────────────────────────────────────
def _parse_call_or_gencompr(
    p: any, target: any, null_ok: any
) -> any {
    # atomic_call: atomic_chain (gen_compr | LPAREN param_list? RPAREN)
    # Also handles filter_compr and assign_compr after null_ok
    lparen = p.advance();

    # Empty call
    if p.check(Tok.RPAREN.value) {
        rparen = p.advance();
        kids: list = [target];
        if null_ok is not None {
            kids.append(null_ok);
        }
        kids.extend([lparen, rparen]);
        nd = UniFuncCall(target=target, params=None, genai_call=None, kid=kids);
        p.register_node(nd);
        return nd;
    }

    # Check for filter_compr: (? filter_compare_list)
    if p.check(Tok.NULL_OK.value) {
        return _parse_filter_compr(p, target, null_ok, lparen);
    }

    # Check for assign_compr: (= kw_expr_list)
    if p.check(Tok.EQ.value) {
        return _parse_assign_compr(p, target, null_ok, lparen);
    }

    # Check for type filter: (:> ? typed_filter_compare_list)
    if p.check(Tok.TYPE_OP.value) {
        return _parse_type_filter_compr(p, target, null_ok, lparen);
    }

    # Parse first parameter (may be keyword arg like name=value)
    first = _parse_param_item(p);

    # Check for generator comprehension: expression KW_FOR ...
    # Only valid if first is a plain expression, not a KWPair
    if not isinstance(first, UniKWPair)
    and (p.check(Tok.KW_FOR.value) or p.check(Tok.KW_ASYNC.value)) {
        comprs = _parse_inner_comprs(p);
        rparen = p.expect(Tok.RPAREN.value);
        gen_kids: list = [lparen, first];
        gen_kids.extend(comprs);
        gen_kids.append(rparen);
        gen = UniGenCompr(out_expr=first, compr=comprs, kid=gen_kids);
        p.register_node(gen);
        # Wrap as FuncCall with genai param
        kids: list = [target];
        if null_ok is not None {
            kids.append(null_ok);
        }
        kids.append(gen);
        nd = UniFuncCall(target=target, params=None, genai_call=None, kid=kids);
        p.register_node(nd);
        return nd;
    }

    # Regular param list
    params: list = [first];
    kids_inner: list = [first];
    while p.check(Tok.COMMA.value) {
        comma = p.advance();
        kids_inner.append(comma);
        if p.check(Tok.RPAREN.value) {
            break;
        }  # trailing comma
        param = _parse_param_item(p);
        params.append(param);
        kids_inner.append(param);
    }
    rparen = p.expect(Tok.RPAREN.value);

    kids: list = [target];
    if null_ok is not None {
        kids.append(null_ok);
    }
    kids.append(lparen);
    kids.extend(kids_inner);
    kids.append(rparen);
    nd = UniFuncCall(target=target, params=params, genai_call=None, kid=kids);
    p.register_node(nd);
    return nd;
}

def _parse_param_item(p: any) -> any {
    # Parse a single parameter in a function call
    # kw_expr: named_ref EQ expression | STAR_POW expression
    # Or just expression

    # **kwargs
    if p.check(Tok.STAR_POW.value) {
        stars = p.advance();
        value = parse_expression(p);
        kids: list = [stars, value];
        nd = UniKWPair(key=None, value=value, kid=kids);
        p.register_node(nd);
        return nd;
    }

    # Check for keyword argument: name = value
    if is_name_token(p.peek()) and p.peek(1).name == Tok.EQ.value {
        name = p.parse_named_ref();
        eq = p.advance();
        value = parse_expression(p);
        kids: list = [name, eq, value];
        nd = UniKWPair(key=name, value=value, kid=kids);
        p.register_node(nd);
        return nd;
    }

    return parse_expression(p);
}

def _parse_filter_compr(p: any, target: any, null_ok: any, lparen: any) -> any {
    # filter_compr: LPAREN NULL_OK filter_compare_list RPAREN
    filter_null = p.advance();  # NULL_OK (?)
    compares = p.parse_filter_compare_list();
    rparen = p.expect(Tok.RPAREN.value);
    kids: list = [lparen, filter_null];
    kids.extend(compares);
    kids.append(rparen);
    filt = UniFilterCompr(f_type=None, compares=compares, kid=kids);
    p.register_node(filt);
    # Wrap as AtomTrailer
    outer_kids: list = [target];
    if null_ok is not None {
        outer_kids.append(null_ok);
    }
    outer_kids.append(filt);
    nd = UniAtomTrailer(
        target=target,
        right=filt,
        is_attr=False,
        is_null_ok=(null_ok is not None),
        kid=outer_kids
    );
    p.register_node(nd);
    return nd;
}

def _parse_assign_compr(p: any, target: any, null_ok: any, lparen: any) -> any {
    # assign_compr: LPAREN EQ kw_expr_list RPAREN
    eq = p.advance();
    assigns = _parse_kw_expr_list(p);
    rparen = p.expect(Tok.RPAREN.value);
    kids: list = [lparen, eq];
    kids.extend(assigns);
    kids.append(rparen);
    acompr = UniAssignCompr(assigns=assigns, kid=kids);
    p.register_node(acompr);
    outer_kids: list = [target];
    if null_ok is not None {
        outer_kids.append(null_ok);
    }
    outer_kids.append(acompr);
    nd = UniAtomTrailer(
        target=target,
        right=acompr,
        is_attr=False,
        is_null_ok=(null_ok is not None),
        kid=outer_kids
    );
    p.register_node(nd);
    return nd;
}

def _parse_type_filter_compr(p: any, target: any, null_ok: any, lparen: any) -> any {
    # filter_compr: LPAREN TYPE_OP NULL_OK typed_filter_compare_list RPAREN
    type_op = p.advance();  # TYPE_OP
    filter_null = p.expect(Tok.NULL_OK.value);
    type_expr = parse_expression(p);
    compares: list = [];
    if p.check(Tok.COLON.value) {
        p.advance();
        compares = p.parse_filter_compare_list();
    }
    rparen = p.expect(Tok.RPAREN.value);
    kids: list = [lparen, type_op, filter_null, type_expr];
    kids.extend(compares);
    kids.append(rparen);
    filt = UniFilterCompr(f_type=type_expr, compares=compares, kid=kids);
    p.register_node(filt);
    outer_kids: list = [target];
    if null_ok is not None {
        outer_kids.append(null_ok);
    }
    outer_kids.append(filt);
    nd = UniAtomTrailer(
        target=target,
        right=filt,
        is_attr=False,
        is_null_ok=(null_ok is not None),
        kid=outer_kids
    );
    p.register_node(nd);
    return nd;
}

# ── Index/Slice ────────────────────────────────────────────────────────
def parse_index_slice(
    p: any
) -> any {
    # index_slice: LSQUARE expression? COLON expression? (COLON expression?)?
    #              (COMMA expression? COLON ...)* RSQUARE
    #            | list_val
    lsquare = p.advance();  # LSQUARE
    kids: list = [lsquare];

    # Check for empty slice or simple index
    if p.check(Tok.RSQUARE.value) {
        rsquare = p.advance();
        kids.append(rsquare);
        nd = UniListVal(values=[], kid=kids);
        p.register_node(nd);
        return nd;
    }

    # Parse first element
    slices: list = [];
    is_range = False;

    # Check if this is a slice (has COLON) or simple index
    start = None;
    if not p.check(Tok.COLON.value) {
        start = parse_expression(p);
        kids.append(start);
    }

    if p.check(Tok.COLON.value) {
        # This is a slice
        is_range = True;
        colon1 = p.advance();
        kids.append(colon1);
        stop = None;
        step = None;
        if not p.check_any(Tok.COLON.value, Tok.RSQUARE.value, Tok.COMMA.value) {
            stop = parse_expression(p);
            kids.append(stop);
        }
        if p.check(Tok.COLON.value) {
            colon2 = p.advance();
            kids.append(colon2);
            if not p.check_any(Tok.RSQUARE.value, Tok.COMMA.value) {
                step = parse_expression(p);
                kids.append(step);
            }
        }
        slices.append(UniIndexSlice.Slice(start=start, stop=stop, step=step));
        # Additional slices
        while p.check(Tok.COMMA.value) {
            comma = p.advance();
            kids.append(comma);
            if p.check(Tok.RSQUARE.value) {
                break;
            }
            s_start = None;
            if not p.check(Tok.COLON.value) {
                s_start = parse_expression(p);
                kids.append(s_start);
            }
            s_colon = p.expect(Tok.COLON.value);
            kids.append(s_colon);
            s_stop = None;
            s_step = None;
            if not p.check_any(Tok.COLON.value, Tok.RSQUARE.value, Tok.COMMA.value) {
                s_stop = parse_expression(p);
                kids.append(s_stop);
            }
            if p.check(Tok.COLON.value) {
                s_colon2 = p.advance();
                kids.append(s_colon2);
                if not p.check_any(Tok.RSQUARE.value, Tok.COMMA.value) {
                    s_step = parse_expression(p);
                    kids.append(s_step);
                }
            }
            slices.append(UniIndexSlice.Slice(start=s_start, stop=s_stop, step=s_step));
        }
    } else {
        # Simple index or multi-value subscript (generic type params).
        # e.g. x[0], Generator[int, None, None], Callable[[int], bool]
        if p.check(Tok.COMMA.value) {
            # Multiple comma-separated expressions → wrap in TupleVal.
            # The TupleVal must be in the IndexSlice kid list so the pass
            # traverses it and populates its gen.py_ast.
            values: list = [start];
            tuple_kids: list = [start];
            while p.check(Tok.COMMA.value) {
                comma = p.advance();
                tuple_kids.append(comma);
                if p.check(Tok.RSQUARE.value) {
                    break;
                }
                val = parse_expression(p);
                tuple_kids.append(val);
                values.append(val);
            }
            if len(values) > 1 {
                tuple_nd = UniTupleVal(values=values, kid=tuple_kids);
                p.register_node(tuple_nd);
                # Remove individual values/commas from IndexSlice kids
                # and add the TupleVal instead so the pass traverses it.
                # kids currently has [lsquare, start, ...]; remove start
                # and replace with the TupleVal.
                kids_clean: list = [lsquare, tuple_nd];
                kids = kids_clean;
                slices.append(
                    UniIndexSlice.Slice(start=tuple_nd, stop=None, step=None)
                );
            } else {
                slices.append(UniIndexSlice.Slice(start=start, stop=None, step=None));
            }
        } else {
            slices.append(UniIndexSlice.Slice(start=start, stop=None, step=None));
        }
    }

    rsquare = p.expect(Tok.RSQUARE.value);
    kids.append(rsquare);

    nd = UniIndexSlice(slices=slices, is_range=is_range, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── Atom ────────────────────────────────────────────────────────────────
def parse_atom(
    p: any
) -> any {
    # atom: named_ref | LPAREN expr RPAREN | atom_collection
    #     | atom_literal | type_ref | jsx_element
    tok = p.peek();

    # Parenthesized expression or tuple
    if tok.name == Tok.LPAREN.value {
        return _parse_paren_expr(p);
    }

    # List literal or comprehension
    if tok.name == Tok.LSQUARE.value {
        return _parse_list_or_compr(p);
    }

    # Dict/set literal or comprehension
    if tok.name == Tok.LBRACE.value {
        return _parse_brace_collection(p);
    }

    # Type reference: :> name
    if tok.name == Tok.TYPE_OP.value {
        return _parse_type_ref(p);
    }

    # String / multistring / fstring
    if tok.name == Tok.STRING.value or _is_fstring_start(tok) {
        return _parse_multistring(p);
    }

    # Numeric literals
    if tok.name == Tok.INT.value {
        return p.advance();
    }
    if tok.name == Tok.FLOAT.value {
        return p.advance();
    }
    if tok.name == Tok.HEX.value {
        return p.advance();
    }
    if tok.name == Tok.BIN.value {
        return p.advance();
    }
    if tok.name == Tok.OCT.value {
        return p.advance();
    }

    # Boolean literal
    if tok.name == Tok.BOOL.value {
        return p.advance();
    }

    # Null literal
    if tok.name == Tok.NULL.value {
        return p.advance();
    }

    # Ellipsis literal
    if tok.name == Tok.ELLIPSIS.value {
        return p.advance();
    }

    # Builtin type name (str, int, float, etc.)
    builtin_type_toks: set = {Tok.TYP_STRING.value,Tok.TYP_INT.value,Tok.TYP_FLOAT.value,Tok.TYP_LIST.value,Tok.TYP_TUPLE.value,Tok.TYP_SET.value,Tok.TYP_DICT.value,Tok.TYP_BOOL.value,Tok.TYP_BYTES.value,Tok.TYP_TYPE.value,Tok.TYP_ANY.value};
    if tok.name in builtin_type_toks {
        return p.advance();
    }

    # JSX element
    if tok.name == Tok.JSX_OPEN_START.value or tok.name == Tok.JSX_FRAG_OPEN.value {
        return p.parse_jsx_element();
    }

    # Named reference (identifier, keyword-escaped, special ref)
    if is_name_token(tok) {
        return p.parse_named_ref();
    }

    # Yield expression (when used as atom)
    if tok.name == Tok.KW_YIELD.value {
        return parse_yield_expr(p);
    }

    # Error - unexpected token
    p.log_error(f"Unexpected token '{tok.value}' in expression", tok);
    p.synchronize(EXPR_SYNC_TOKENS);
    return p._synthesize_token(Tok.NAME.value);
}

# ── Yield expression ───────────────────────────────────────────────────
def parse_yield_expr(
    p: any
) -> any {
    # yield_expr: KW_YIELD KW_FROM? expression
    yield_tok = p.advance();
    with_from = False;
    from_tok = None;
    if p.check(Tok.KW_FROM.value) {
        from_tok = p.advance();
        with_from = True;
    }
    expr = None;
    if not p.check(Tok.SEMI.value) and not p.check(Tok.RBRACE.value) and not p.at_end() {
        expr = parse_expression(p);
    }
    kids: list = [yield_tok];
    if from_tok is not None {
        kids.append(from_tok);
    }
    if expr is not None {
        kids.append(expr);
    }
    nd = UniYieldExpr(expr=expr, with_from=with_from, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── Parenthesized expression / tuple ───────────────────────────────────
def _parse_paren_expr(
    p: any
) -> any {
    # atom: LPAREN (expression | yield_expr | function_decl) RPAREN
    # tuple_val: LPAREN tuple_list? RPAREN
    lparen = p.advance();

    if p.check(Tok.RPAREN.value) {
        # Empty tuple
        rparen = p.advance();
        kids: list = [lparen, rparen];
        nd = UniTupleVal(values=[], kid=kids);
        p.register_node(nd);
        return nd;
    }

    # Check for yield
    if p.check(Tok.KW_YIELD.value) {
        inner = parse_yield_expr(p);
        rparen = p.expect(Tok.RPAREN.value);
        kids: list = [lparen, inner, rparen];
        nd = UniAtomUnit(value=inner, kid=kids);
        p.register_node(nd);
        return nd;
    }

    # Parse first expression
    first = parse_expression(p);

    # Check for generator comprehension inside parens
    if p.check(Tok.KW_FOR.value) or p.check(Tok.KW_ASYNC.value) {
        comprs = _parse_inner_comprs(p);
        rparen = p.expect(Tok.RPAREN.value);
        kids: list = [lparen, first];
        kids.extend(comprs);
        kids.append(rparen);
        nd = UniGenCompr(out_expr=first, compr=comprs, kid=kids);
        p.register_node(nd);
        return nd;
    }

    # Check for tuple (comma after first expr)
    if p.check(Tok.COMMA.value) {
        values: list = [first];
        kids: list = [lparen, first];
        while p.check(Tok.COMMA.value) {
            comma = p.advance();
            kids.append(comma);
            if p.check(Tok.RPAREN.value) {
                break;
            }
            item = _parse_param_item(p);
            values.append(item);
            kids.append(item);
        }
        rparen = p.expect(Tok.RPAREN.value);
        kids.append(rparen);
        nd = UniTupleVal(values=values, kid=kids);
        p.register_node(nd);
        return nd;
    }

    # Single parenthesized expression
    rparen = p.expect(Tok.RPAREN.value);
    kids: list = [lparen, first, rparen];
    nd = UniAtomUnit(value=first, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── List literal / comprehension ───────────────────────────────────────
def _parse_list_or_compr(
    p: any
) -> any {
    lsquare = p.advance();

    if p.check(Tok.RSQUARE.value) {
        rsquare = p.advance();
        kids: list = [lsquare, rsquare];
        nd = UniListVal(values=[], kid=kids);
        p.register_node(nd);
        return nd;
    }

    first = parse_expression(p);

    # List comprehension
    if p.check(Tok.KW_FOR.value) or p.check(Tok.KW_ASYNC.value) {
        comprs = _parse_inner_comprs(p);
        rsquare = p.expect(Tok.RSQUARE.value);
        kids: list = [lsquare, first];
        kids.extend(comprs);
        kids.append(rsquare);
        nd = UniListCompr(out_expr=first, compr=comprs, kid=kids);
        p.register_node(nd);
        return nd;
    }

    # Regular list
    values: list = [first];
    kids: list = [lsquare, first];
    while p.check(Tok.COMMA.value) {
        comma = p.advance();
        kids.append(comma);
        if p.check(Tok.RSQUARE.value) {
            break;
        }
        val = parse_expression(p);
        values.append(val);
        kids.append(val);
    }
    rsquare = p.expect(Tok.RSQUARE.value);
    kids.append(rsquare);
    nd = UniListVal(values=values, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── Dict/Set literal or comprehension ──────────────────────────────────
def _parse_brace_collection(
    p: any
) -> any {
    # Could be: dict_val, set_val, dict_compr, set_compr
    lbrace = p.advance();

    # Empty dict
    if p.check(Tok.RBRACE.value) {
        rbrace = p.advance();
        kids: list = [lbrace, rbrace];
        nd = UniDictVal(kv_pairs=[], kid=kids);
        p.register_node(nd);
        return nd;
    }

    # Check for **expr (dict unpack)
    if p.check(Tok.STAR_POW.value) {
        return _finish_dict_val(p, lbrace);
    }

    # Parse first expression
    first = parse_expression(p);

    # Dict: first COLON value
    if p.check(Tok.COLON.value) {
        colon = p.advance();
        value = parse_expression(p);
        pair_kids: list = [first, colon, value];
        pair = UniKVPair(key=first, value=value, kid=pair_kids);
        p.register_node(pair);
        # Dict comprehension
        if p.check(Tok.KW_FOR.value) or p.check(Tok.KW_ASYNC.value) {
            comprs = _parse_inner_comprs(p);
            rbrace = p.expect(Tok.RBRACE.value);
            kids: list = [lbrace, pair];
            kids.extend(comprs);
            kids.append(rbrace);
            nd = UniDictCompr(kv_pair=pair, compr=comprs, kid=kids);
            p.register_node(nd);
            return nd;
        }
        # Regular dict
        pairs: list = [pair];
        kids: list = [lbrace, pair];
        while p.check(Tok.COMMA.value) {
            comma = p.advance();
            kids.append(comma);
            if p.check(Tok.RBRACE.value) {
                break;
            }
            kv = _parse_kv_pair(p);
            pairs.append(kv);
            kids.append(kv);
        }
        rbrace = p.expect(Tok.RBRACE.value);
        kids.append(rbrace);
        nd = UniDictVal(kv_pairs=pairs, kid=kids);
        p.register_node(nd);
        return nd;
    }

    # Set comprehension
    if p.check(Tok.KW_FOR.value) or p.check(Tok.KW_ASYNC.value) {
        comprs = _parse_inner_comprs(p);
        rbrace = p.expect(Tok.RBRACE.value);
        kids: list = [lbrace, first];
        kids.extend(comprs);
        kids.append(rbrace);
        nd = UniSetCompr(out_expr=first, compr=comprs, kid=kids);
        p.register_node(nd);
        return nd;
    }

    # Set literal
    values: list = [first];
    kids: list = [lbrace, first];
    while p.check(Tok.COMMA.value) {
        comma = p.advance();
        kids.append(comma);
        if p.check(Tok.RBRACE.value) {
            break;
        }
        val = parse_expression(p);
        values.append(val);
        kids.append(val);
    }
    rbrace = p.expect(Tok.RBRACE.value);
    kids.append(rbrace);
    nd = UniSetVal(values=values, kid=kids);
    p.register_node(nd);
    return nd;
}

def _finish_dict_val(p: any, lbrace: any) -> any {
    # Finish parsing dict_val starting with **expr
    pairs: list = [];
    kids: list = [lbrace];
    while True {
        kv = _parse_kv_pair(p);
        pairs.append(kv);
        kids.append(kv);
        if not p.check(Tok.COMMA.value) {
            break;
        }
        comma = p.advance();
        kids.append(comma);
        if p.check(Tok.RBRACE.value) {
            break;
        }
    }
    rbrace = p.expect(Tok.RBRACE.value);
    kids.append(rbrace);
    nd = UniDictVal(kv_pairs=pairs, kid=kids);
    p.register_node(nd);
    return nd;
}

def _parse_kv_pair(p: any) -> any {
    # kv_pair: expression COLON expression | STAR_POW expression
    if p.check(Tok.STAR_POW.value) {
        stars = p.advance();
        value = parse_expression(p);
        kids: list = [stars, value];
        nd = UniKVPair(key=None, value=value, kid=kids);
        p.register_node(nd);
        return nd;
    }
    key = parse_expression(p);
    colon = p.expect(Tok.COLON.value);
    value = parse_expression(p);
    kids: list = [key, colon, value];
    nd = UniKVPair(key=key, value=value, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── Comprehension helpers ──────────────────────────────────────────────
def _parse_inner_comprs(
    p: any
) -> list {
    # inner_compr: KW_ASYNC? KW_FOR atomic_chain KW_IN pipe_call (KW_IF walrus_assign)*
    comprs: list = [];
    while p.check(Tok.KW_FOR.value) or p.check(Tok.KW_ASYNC.value) {
        kids: list = [];
        is_async = False;
        if p.check(Tok.KW_ASYNC.value) {
            async_tok = p.advance();
            is_async = True;
            kids.append(async_tok);
        }
        for_tok = p.expect(Tok.KW_FOR.value);
        kids.append(for_tok);
        target = parse_atomic_chain(p);
        kids.append(target);
        in_tok = p.expect(Tok.KW_IN.value);
        kids.append(in_tok);
        collection = parse_pipe_call(p);
        kids.append(collection);
        conditionals: list = [];
        while p.check(Tok.KW_IF.value) {
            if_tok = p.advance();
            kids.append(if_tok);
            cond = parse_walrus(p);
            conditionals.append(cond);
            kids.append(cond);
        }
        compr = UniInnerCompr(
            is_async=is_async,
            target=target,
            collection=collection,
            conditional=conditionals if len(conditionals) > 0 else None,
            kid=kids
        );
        p.register_node(compr);
        comprs.append(compr);
    }
    return comprs;
}

# ── KW expression list ─────────────────────────────────────────────────
def _parse_kw_expr_list(
    p: any
) -> list {
    # kw_expr_list: (kw_expr_list COMMA)? kw_expr
    items: list = [];
    while True {
        item = _parse_kw_expr(p);
        items.append(item);
        if not p.check(Tok.COMMA.value) {
            break;
        }
        p.advance();
        if p.check(Tok.RPAREN.value) or p.check(Tok.RBRACE.value) {
            break;
        }
    }
    return items;
}

def _parse_kw_expr(p: any) -> any {
    # kw_expr: named_ref EQ expression | STAR_POW expression
    if p.check(Tok.STAR_POW.value) {
        stars = p.advance();
        value = parse_expression(p);
        kids: list = [stars, value];
        nd = UniKWPair(key=None, value=value, kid=kids);
        p.register_node(nd);
        return nd;
    }
    name = p.parse_named_ref();
    eq = p.expect(Tok.EQ.value);
    value = parse_expression(p);
    kids: list = [name, eq, value];
    nd = UniKWPair(key=name, value=value, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── Type reference ─────────────────────────────────────────────────────
def _parse_type_ref(
    p: any
) -> any {
    # type_ref: TYPE_OP (named_ref | builtin_type)
    type_op = p.advance();
    target = p.parse_named_ref();
    kids: list = [type_op, target];
    nd = UniTypeRef(target=target, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── Multistring / fstring ──────────────────────────────────────────────
def _is_fstring_start(
    tok: any
) -> bool {
    # Check if token is the start of an f-string
    return tok.name in [
        Tok.F_DQ_START.value,
        Tok.F_SQ_START.value,
        Tok.F_TDQ_START.value,
        Tok.F_TSQ_START.value,
        Tok.RF_DQ_START.value,
        Tok.RF_SQ_START.value,
        Tok.RF_TDQ_START.value,
        Tok.RF_TSQ_START.value
    ];
}

def _parse_multistring(p: any) -> any {
    # multistring: (fstring | STRING)+
    strings: list = [];
    kids: list = [];
    while p.check(Tok.STRING.value) or _is_fstring_start(p.peek()) {
        if p.check(Tok.STRING.value) {
            s = p.advance();
            strings.append(s);
            kids.append(s);
        } else {
            fs = p.parse_fstring();
            strings.append(fs);
            kids.append(fs);
        }
    }
    if len(strings) == 1 {
        return strings[0];
    }
    nd = UniMultiString(strings=strings, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── Pipe expression (used from type_tag and other contexts) ────────────
def parse_pipe(
    p: any
) -> any {
    # pipe: (pipe PIPE_FWD)? pipe_back  (left-associative)
    left = parse_pipe_back(p);
    while p.check(Tok.PIPE_FWD.value) {
        op = p.advance();
        right = parse_pipe_back(p);
        kids: list = [left, op, right];
        left = UniBinaryExpr(left=left, op=op, right=right, kid=kids);
        p.register_node(left);
    }
    return left;
}
