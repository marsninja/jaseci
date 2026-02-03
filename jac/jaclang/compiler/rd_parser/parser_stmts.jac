# Statement parsing for the Jac recursive descent parser.
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
    AtomExpr,
    NameAtom,
    CodeBlockStmt,
    ContextAwareNode,
    IfStmt as UniIfStmt,
    ElseIf as UniElseIf,
    ElseStmt as UniElseStmt,
    WhileStmt as UniWhileStmt,
    IterForStmt as UniIterForStmt,
    InForStmt as UniInForStmt,
    TryStmt as UniTryStmt,
    Except as UniExcept,
    FinallyStmt as UniFinallyStmt,
    WithStmt as UniWithStmt,
    ExprAsItem as UniExprAsItem,
    ReturnStmt as UniReturnStmt,
    YieldExpr as UniYieldExpr,
    RaiseStmt as UniRaiseStmt,
    AssertStmt as UniAssertStmt,
    DeleteStmt as UniDeleteStmt,
    ReportStmt as UniReportStmt,
    CtrlStmt as UniCtrlStmt,
    VisitStmt as UniVisitStmt,
    DisengageStmt as UniDisengageStmt,
    Assignment as UniAssignment,
    GlobalStmt as UniGlobalStmt,
    NonLocalStmt as UniNonLocalStmt,
    TypedCtxBlock as UniTypedCtxBlock,
    ExprStmt as UniExprStmt,
    SubTag as UniSubTag,
    Semi as UniSemi,
    Import as UniImport,
    PyInlineCode as UniPyInlineCode
}

import from jaclang.pycore.constant { Tokens as Tok }

import from jaclang.compiler.rd_parser.ast_builder {
    is_eof_token,
    is_name_token,
    is_special_ref_token,
    AUGMENTED_ASSIGN_OPS,
    STATEMENT_START_TOKENS,
    STMT_SYNC_TOKENS,
    ARCH_TYPE_TOKENS
}

import from jaclang.compiler.rd_parser.parser_exprs {
    parse_expression,
    parse_atomic_chain,
    parse_arithmetic,
    parse_pipe,
    parse_yield_expr
}

# ── Code block ──────────────────────────────────────────────────────────
def parse_code_block(
    p: any
) -> list {
    # code_block: LBRACE statement* RBRACE
    # Returns list of CodeBlockStmt
    p.expect(Tok.LBRACE.value);
    stmts: list = [];
    while not p.at_end() and not p.check(Tok.RBRACE.value) {
        stmt = parse_statement(p);
        if stmt is not None {
            stmts.append(stmt);
        } else {
            if not p.at_end() and not p.check(Tok.RBRACE.value) {
                p.advance();
            }
        }
    }
    p.expect(Tok.RBRACE.value);
    return stmts;
}

def parse_code_block_with_kids(p: any) -> tuple {
    # Returns (stmts_list, kids_list) where kids includes LBRACE, stmts, RBRACE
    lbrace = p.expect(Tok.LBRACE.value);
    stmts: list = [];
    kids: list = [lbrace];
    while not p.at_end() and not p.check(Tok.RBRACE.value) {
        stmt = parse_statement(p);
        if stmt is not None {
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

# ── Statement dispatch ──────────────────────────────────────────────────
def parse_statement(
    p: any
) -> any {
    # statement: import_stmt | ability | has_stmt | archetype | impl_def
    #          | if_stmt | while_stmt | for_stmt | try_stmt | match_stmt
    #          | switch_stmt | with_stmt | global_ref SEMI | nonlocal_ref SEMI
    #          | typed_ctx_block | return_stmt SEMI | yield_expr SEMI
    #          | raise_stmt SEMI | assert_stmt SEMI | assignment SEMI
    #          | delete_stmt SEMI | report_stmt SEMI | expression SEMI
    #          | ctrl_stmt SEMI | py_code_block | spatial_stmt | SEMI
    tok = p.peek();

    # Empty statement
    if tok.name == Tok.SEMI.value {
        semi = p.advance();
        return semi;
    }

    # Import statement
    if tok.name in [Tok.KW_IMPORT.value, Tok.KW_INCLUDE.value] {
        return p.parse_import_stmt();
    }

    # Ability (def/can)
    if tok.name in [
        Tok.KW_DEF.value,
        Tok.KW_CAN.value,
        Tok.KW_OVERRIDE.value,
        Tok.KW_STATIC.value
    ] {
        return p.parse_ability();
    }

    # Has statement
    if tok.name == Tok.KW_HAS.value {
        return p.parse_has_stmt();
    }

    # Archetype
    if tok.name in ARCH_TYPE_TOKENS {
        return p.parse_archetype();
    }

    # Enum
    if tok.name == Tok.KW_ENUM.value {
        return p.parse_enum();
    }

    # Decorator (for nested archetype/ability)
    if tok.name == Tok.DECOR_OP.value {
        return p.parse_decorated_def();
    }

    # Impl definition
    if tok.name == Tok.KW_IMPL.value {
        return p.parse_impl_def();
    }

    # If statement
    if tok.name == Tok.KW_IF.value {
        return parse_if_stmt(p);
    }

    # While statement
    if tok.name == Tok.KW_WHILE.value {
        return parse_while_stmt(p);
    }

    # For statement
    if tok.name == Tok.KW_FOR.value {
        return parse_for_stmt(p);
    }

    # Async for / async with
    if tok.name == Tok.KW_ASYNC.value {
        peek1 = p.peek(1);
        if peek1.name == Tok.KW_FOR.value {
            return parse_for_stmt(p);
        }
        if peek1.name == Tok.KW_WITH.value {
            return parse_with_stmt(p);
        }
        # Async ability or archetype
        if peek1.name in ARCH_TYPE_TOKENS {
            return p.parse_archetype();
        }
        return p.parse_ability();
    }

    # Try statement
    if tok.name == Tok.KW_TRY.value {
        return parse_try_stmt(p);
    }

    # Match statement
    if tok.name == Tok.KW_MATCH.value {
        return p.parse_match_stmt();
    }

    # Switch statement
    if tok.name == Tok.KW_SWITCH.value {
        return p.parse_switch_stmt();
    }

    # With statement
    if tok.name == Tok.KW_WITH.value {
        return parse_with_stmt(p);
    }

    # Global reference
    if tok.name == Tok.GLOBAL_OP.value {
        return parse_global_ref(p);
    }

    # Nonlocal reference
    if tok.name == Tok.NONLOCAL_OP.value {
        return parse_nonlocal_ref(p);
    }

    # Typed context block
    if tok.name == Tok.RETURN_HINT.value {
        return parse_typed_ctx_block(p);
    }

    # Return statement
    if tok.name == Tok.KW_RETURN.value {
        return parse_return_stmt(p);
    }

    # Yield expression - must be wrapped in ExprStmt at statement level
    if tok.name == Tok.KW_YIELD.value {
        yield_expr = parse_yield_expr(p);
        semi = p.expect(Tok.SEMI.value);
        kids: list = [yield_expr, semi];
        nd = UniExprStmt(expr=yield_expr, in_fstring=False, kid=kids);
        p.register_node(nd);
        return nd;
    }

    # Raise statement
    if tok.name == Tok.KW_RAISE.value {
        return parse_raise_stmt(p);
    }

    # Assert statement
    if tok.name == Tok.KW_ASSERT.value {
        return parse_assert_stmt(p);
    }

    # Delete statement
    if tok.name == Tok.KW_DELETE.value {
        # Could also be disconnect_op (del edge_op), handle that case
        peek1 = p.peek(1);
        if peek1.name in [
            Tok.ARROW_R.value,
            Tok.ARROW_L.value,
            Tok.ARROW_BI.value,
            Tok.ARROW_R_P1.value,
            Tok.ARROW_L_P1.value
        ] {
            # This is probably part of an expression (disconnect)
            return _parse_expr_or_assignment(p);
        }
        return parse_delete_stmt(p);
    }

    # Report statement
    if tok.name == Tok.KW_REPORT.value {
        return parse_report_stmt(p);
    }

    # Control statements
    if tok.name in [Tok.KW_BREAK.value, Tok.KW_CONTINUE.value, Tok.KW_SKIP.value] {
        return parse_ctrl_stmt(p);
    }

    # Visit statement
    if tok.name == Tok.KW_VISIT.value {
        return parse_visit_stmt(p);
    }

    # Disengage statement
    if tok.name == Tok.KW_DISENGAGE.value {
        return parse_disengage_stmt(p);
    }

    # Inline Python
    if tok.name == Tok.PYNLINE.value {
        return p.parse_py_code_block();
    }

    # Expression or assignment
    return _parse_expr_or_assignment(p);
}

# ── Expression or Assignment ───────────────────────────────────────────
def _parse_expr_or_assignment(
    p: any
) -> any {
    # Parse expression, then check for assignment operators
    # assignment: (atomic_chain EQ)+ (yield_expr | expression)
    #           | atomic_chain type_tag (EQ (yield_expr | expression))?
    #           | atomic_chain aug_op (yield_expr | expression)
    expr = parse_expression(p);

    # Check for assignment: EQ
    if p.check(Tok.EQ.value) {
        targets: list = [expr];
        kids: list = [expr];
        while p.check(Tok.EQ.value) {
            eq = p.advance();
            kids.append(eq);
            # Parse value (could be another target if followed by EQ)
            if p.check(Tok.KW_YIELD.value) {
                value = parse_yield_expr(p);
            } else {
                value = parse_expression(p);
            }
            kids.append(value);
            if p.check(Tok.EQ.value) {
                targets.append(value);
            }
        }
        semi = p.expect(Tok.SEMI.value);
        kids.append(semi);
        nd = UniAssignment(
            target=targets,
            value=value,
            type_tag=None,
            kid=kids,
            mutable=True,
            aug_op=None
        );
        p.register_node(nd);
        return nd;
    }

    # Check for typed assignment: COLON type (= value)?
    if p.check(Tok.COLON.value) {
        colon = p.advance();
        type_expr = parse_pipe(p);
        tag_kids: list = [colon, type_expr];
        type_tag = UniSubTag(tag=type_expr, kid=tag_kids);
        p.register_node(type_tag);
        value = None;
        kids: list = [expr, type_tag];
        if p.check(Tok.EQ.value) {
            eq = p.advance();
            kids.append(eq);
            if p.check(Tok.KW_YIELD.value) {
                value = parse_yield_expr(p);
            } else {
                value = parse_expression(p);
            }
            kids.append(value);
        }
        semi = p.expect(Tok.SEMI.value);
        kids.append(semi);
        nd = UniAssignment(
            target=[expr],
            value=value,
            type_tag=type_tag,
            kid=kids,
            mutable=True,
            aug_op=None
        );
        p.register_node(nd);
        return nd;
    }

    # Check for augmented assignment: +=, -=, etc.
    if p.peek().name in AUGMENTED_ASSIGN_OPS {
        aug = p.advance();
        if p.check(Tok.KW_YIELD.value) {
            value = parse_yield_expr(p);
        } else {
            value = parse_expression(p);
        }
        semi = p.expect(Tok.SEMI.value);
        kids: list = [expr, aug, value, semi];
        nd = UniAssignment(
            target=[expr],
            value=value,
            type_tag=None,
            kid=kids,
            mutable=True,
            aug_op=aug
        );
        p.register_node(nd);
        return nd;
    }

    # Just an expression statement
    semi = p.expect(Tok.SEMI.value);
    kids: list = [expr, semi];
    nd = UniExprStmt(expr=expr, in_fstring=False, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── If statement ───────────────────────────────────────────────────────
def parse_if_stmt(
    p: any
) -> any {
    # if_stmt: KW_IF expression code_block (elif_stmt | else_stmt)?
    if_tok = p.expect(Tok.KW_IF.value);
    condition = parse_expression(p);
    block = parse_code_block_with_kids(p);
    body = block[0];
    block_kids = block[1];

    else_body = None;
    if p.check(Tok.KW_ELIF.value) {
        else_body = parse_elif_stmt(p);
    } elif p.check(Tok.KW_ELSE.value) {
        else_body = parse_else_stmt(p);
    }

    kids: list = [if_tok, condition];
    kids.extend(block_kids);
    if else_body is not None {
        kids.append(else_body);
    }

    nd = UniIfStmt(condition=condition, body=body, else_body=else_body, kid=kids);
    p.register_node(nd);
    return nd;
}

def parse_elif_stmt(p: any) -> any {
    # elif_stmt: KW_ELIF expression code_block (elif_stmt | else_stmt)?
    elif_tok = p.expect(Tok.KW_ELIF.value);
    condition = parse_expression(p);
    block = parse_code_block_with_kids(p);
    body = block[0];
    block_kids = block[1];

    else_body = None;
    if p.check(Tok.KW_ELIF.value) {
        else_body = parse_elif_stmt(p);
    } elif p.check(Tok.KW_ELSE.value) {
        else_body = parse_else_stmt(p);
    }

    kids: list = [elif_tok, condition];
    kids.extend(block_kids);
    if else_body is not None {
        kids.append(else_body);
    }

    nd = UniElseIf(condition=condition, body=body, else_body=else_body, kid=kids);
    p.register_node(nd);
    return nd;
}

def parse_else_stmt(p: any) -> any {
    # else_stmt: KW_ELSE code_block
    else_tok = p.expect(Tok.KW_ELSE.value);
    block = parse_code_block_with_kids(p);
    body = block[0];
    block_kids = block[1];

    kids: list = [else_tok];
    kids.extend(block_kids);

    nd = UniElseStmt(body=body, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── While statement ────────────────────────────────────────────────────
def parse_while_stmt(
    p: any
) -> any {
    # while_stmt: KW_WHILE expression code_block else_stmt?
    while_tok = p.expect(Tok.KW_WHILE.value);
    condition = parse_expression(p);
    block = parse_code_block_with_kids(p);
    body = block[0];
    block_kids = block[1];

    else_body = None;
    if p.check(Tok.KW_ELSE.value) {
        else_body = parse_else_stmt(p);
    }

    kids: list = [while_tok, condition];
    kids.extend(block_kids);
    if else_body is not None {
        kids.append(else_body);
    }

    nd = UniWhileStmt(condition=condition, body=body, else_body=else_body, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── For statement ──────────────────────────────────────────────────────
def parse_for_stmt(
    p: any
) -> any {
    # for_stmt: KW_ASYNC? KW_FOR assignment KW_TO expression KW_BY assignment code_block else_stmt?
    #         | KW_ASYNC? KW_FOR atomic_chain KW_IN expression code_block else_stmt?
    kids: list = [];
    is_async = False;

    if p.check(Tok.KW_ASYNC.value) {
        async_tok = p.advance();
        is_async = True;
        kids.append(async_tok);
    }

    for_tok = p.expect(Tok.KW_FOR.value);
    kids.append(for_tok);

    # Parse the target/assignment part.
    # Use parse_arithmetic (stops before comparison operators like `in`, `is`)
    # so that `for x in collection` doesn't consume `in` as a compare op.
    target_expr = parse_arithmetic(p);

    # For iter-for loops (C-style), the first part may be an assignment: `for i = 0 to ...`
    # Check if we have an `=` and parse it as an assignment
    if p.check(Tok.EQ.value) {
        eq_tok = p.advance();
        value = parse_arithmetic(p);
        assign_kids: list = [target_expr, eq_tok, value];
        target_expr = UniAssignment(
            target=[target_expr],
            value=value,
            type_tag=None,
            kid=assign_kids,
            mutable=True,
            aug_op=None
        );
        p.register_node(target_expr);
    }

    # Check which form: KW_TO (iter-for) or KW_IN (in-for)
    if p.check(Tok.KW_TO.value) {
        # IterForStmt: for assignment KW_TO expression KW_BY assignment code_block
        # target_expr should be the iter assignment (parsed as expression)
        # Need to check if it was an assignment (had EQ)
        iter_assign = _expr_to_assignment(p, target_expr);
        to_tok = p.advance();
        kids.extend([target_expr, to_tok]);
        condition = parse_pipe(p);
        kids.append(condition);
        by_tok = p.expect(Tok.KW_BY.value);
        kids.append(by_tok);
        # count_by can be: expression, assignment (i = i + 1), or augmented assignment (i += 1)
        count_by_expr = parse_arithmetic(p);
        # Check for augmented assignment: +=, -=, etc.
        if p.peek().name in AUGMENTED_ASSIGN_OPS {
            aug_op = p.advance();
            aug_value = parse_arithmetic(p);
            assign_kids: list = [count_by_expr, aug_op, aug_value];
            count_by = UniAssignment(
                target=[count_by_expr],
                value=aug_value,
                type_tag=None,
                kid=assign_kids,
                mutable=True,
                aug_op=aug_op
            );
            p.register_node(count_by);
            kids.append(count_by);
        } elif p.check(Tok.EQ.value) {
            # Regular assignment: i = i + 1
            eq_tok = p.advance();
            eq_value = parse_arithmetic(p);
            assign_kids: list = [count_by_expr, eq_tok, eq_value];
            count_by = UniAssignment(
                target=[count_by_expr],
                value=eq_value,
                type_tag=None,
                kid=assign_kids,
                mutable=True,
                aug_op=None
            );
            p.register_node(count_by);
            kids.append(count_by);
        } else {
            # Simple expression (wrapped in Assignment for compatibility)
            count_by = _expr_to_assignment(p, count_by_expr);
            kids.append(count_by_expr);
        }
        block = parse_code_block_with_kids(p);
        body = block[0];
        kids.extend(block[1]);
        else_body = None;
        if p.check(Tok.KW_ELSE.value) {
            else_body = parse_else_stmt(p);
            kids.append(else_body);
        }
        nd = UniIterForStmt(
            iter=iter_assign,
            is_async=is_async,
            condition=condition,
            count_by=count_by,
            body=body,
            else_body=else_body,
            kid=kids
        );
        p.register_node(nd);
        return nd;
    }

    # InForStmt: for atomic_chain KW_IN expression code_block
    in_tok = p.expect(Tok.KW_IN.value);
    kids.extend([target_expr, in_tok]);
    collection = parse_expression(p);
    kids.append(collection);

    block = parse_code_block_with_kids(p);
    body = block[0];
    kids.extend(block[1]);

    else_body = None;
    if p.check(Tok.KW_ELSE.value) {
        else_body = parse_else_stmt(p);
        kids.append(else_body);
    }

    nd = UniInForStmt(
        target=target_expr,
        is_async=is_async,
        collection=collection,
        body=body,
        else_body=else_body,
        kid=kids
    );
    p.register_node(nd);
    return nd;
}

def _expr_to_assignment(p: any, expr: any) -> any {
    # Wrap an expression as an Assignment if needed
    if isinstance(expr, UniAssignment) {
        return expr;
    }
    # Create a simple assignment: target = target (identity)
    nd = UniAssignment(
        target=[expr], value=None, type_tag=None, kid=[expr], mutable=True, aug_op=None
    );
    p.register_node(nd);
    return nd;
}

# ── Try statement ──────────────────────────────────────────────────────
def parse_try_stmt(
    p: any
) -> any {
    # try_stmt: KW_TRY code_block except_list? else_stmt? finally_stmt?
    try_tok = p.expect(Tok.KW_TRY.value);
    block = parse_code_block_with_kids(p);
    body = block[0];
    kids: list = [try_tok];
    kids.extend(block[1]);

    excepts: list = [];
    while p.check(Tok.KW_EXCEPT.value) {
        exc = parse_except_def(p);
        excepts.append(exc);
        kids.append(exc);
    }

    else_body = None;
    if p.check(Tok.KW_ELSE.value) {
        else_body = parse_else_stmt(p);
        kids.append(else_body);
    }

    finally_body = None;
    if p.check(Tok.KW_FINALLY.value) {
        finally_body = parse_finally_stmt(p);
        kids.append(finally_body);
    }

    nd = UniTryStmt(
        body=body,
        excepts=excepts,
        else_body=else_body,
        finally_body=finally_body,
        kid=kids
    );
    p.register_node(nd);
    return nd;
}

def parse_except_def(p: any) -> any {
    # except_def: KW_EXCEPT expression (KW_AS NAME)? code_block
    except_tok = p.expect(Tok.KW_EXCEPT.value);
    ex_type = parse_expression(p);
    kids: list = [except_tok, ex_type];

    name = None;
    if p.check(Tok.KW_AS.value) {
        as_tok = p.advance();
        kids.append(as_tok);
        name = p.parse_named_ref();
        kids.append(name);
    }

    block = parse_code_block_with_kids(p);
    body = block[0];
    kids.extend(block[1]);

    nd = UniExcept(ex_type=ex_type, name=name, body=body, kid=kids);
    p.register_node(nd);
    return nd;
}

def parse_finally_stmt(p: any) -> any {
    # finally_stmt: KW_FINALLY code_block
    finally_tok = p.expect(Tok.KW_FINALLY.value);
    block = parse_code_block_with_kids(p);
    body = block[0];
    kids: list = [finally_tok];
    kids.extend(block[1]);

    nd = UniFinallyStmt(body=body, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── With statement ─────────────────────────────────────────────────────
def parse_with_stmt(
    p: any
) -> any {
    # with_stmt: KW_ASYNC? KW_WITH expr_as_list code_block
    kids: list = [];
    is_async = False;

    if p.check(Tok.KW_ASYNC.value) {
        async_tok = p.advance();
        is_async = True;
        kids.append(async_tok);
    }

    with_tok = p.expect(Tok.KW_WITH.value);
    kids.append(with_tok);

    # Parse expr_as list
    exprs: list = [];
    while True {
        item = _parse_expr_as(p);
        exprs.append(item);
        kids.append(item);
        if not p.check(Tok.COMMA.value) {
            break;
        }
        comma = p.advance();
        kids.append(comma);
    }

    block = parse_code_block_with_kids(p);
    body = block[0];
    kids.extend(block[1]);

    nd = UniWithStmt(is_async=is_async, exprs=exprs, body=body, kid=kids);
    p.register_node(nd);
    return nd;
}

def _parse_expr_as(p: any) -> any {
    # expr_as: expression (KW_AS expression)?
    expr = parse_expression(p);
    alias = None;
    kids: list = [expr];
    if p.check(Tok.KW_AS.value) {
        as_tok = p.advance();
        kids.append(as_tok);
        alias = parse_expression(p);
        kids.append(alias);
    }
    nd = UniExprAsItem(expr=expr, alias=alias, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── Return statement ───────────────────────────────────────────────────
def parse_return_stmt(
    p: any
) -> any {
    # return_stmt: KW_RETURN expression?
    return_tok = p.expect(Tok.KW_RETURN.value);
    expr = None;
    kids: list = [return_tok];
    if not p.check(Tok.SEMI.value) and not p.check(Tok.RBRACE.value) and not p.at_end() {
        expr = parse_expression(p);
        kids.append(expr);
    }
    semi = p.expect(Tok.SEMI.value);
    kids.append(semi);
    nd = UniReturnStmt(expr=expr, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── Raise statement ────────────────────────────────────────────────────
def parse_raise_stmt(
    p: any
) -> any {
    # raise_stmt: KW_RAISE (expression (KW_FROM expression)?)?
    raise_tok = p.expect(Tok.KW_RAISE.value);
    cause = None;
    from_target = None;
    kids: list = [raise_tok];

    if not p.check(Tok.SEMI.value) and not p.at_end() {
        cause = parse_expression(p);
        kids.append(cause);
        if p.check(Tok.KW_FROM.value) {
            from_tok = p.advance();
            kids.append(from_tok);
            from_target = parse_expression(p);
            kids.append(from_target);
        }
    }
    semi = p.expect(Tok.SEMI.value);
    kids.append(semi);
    nd = UniRaiseStmt(cause=cause, from_target=from_target, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── Assert statement ───────────────────────────────────────────────────
def parse_assert_stmt(
    p: any
) -> any {
    # assert_stmt: KW_ASSERT expression (COMMA expression)?
    assert_tok = p.expect(Tok.KW_ASSERT.value);
    condition = parse_expression(p);
    error_msg = None;
    kids: list = [assert_tok, condition];

    if p.check(Tok.COMMA.value) {
        comma = p.advance();
        kids.append(comma);
        error_msg = parse_expression(p);
        kids.append(error_msg);
    }
    semi = p.expect(Tok.SEMI.value);
    kids.append(semi);
    nd = UniAssertStmt(condition=condition, error_msg=error_msg, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── Delete statement ───────────────────────────────────────────────────
def parse_delete_stmt(
    p: any
) -> any {
    # delete_stmt: KW_DELETE expression
    del_tok = p.expect(Tok.KW_DELETE.value);
    target = parse_expression(p);
    semi = p.expect(Tok.SEMI.value);
    kids: list = [del_tok, target, semi];
    nd = UniDeleteStmt(target=target, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── Report statement ───────────────────────────────────────────────────
def parse_report_stmt(
    p: any
) -> any {
    # report_stmt: KW_REPORT expression
    report_tok = p.expect(Tok.KW_REPORT.value);
    expr = parse_expression(p);
    semi = p.expect(Tok.SEMI.value);
    kids: list = [report_tok, expr, semi];
    nd = UniReportStmt(expr=expr, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── Control statements ─────────────────────────────────────────────────
def parse_ctrl_stmt(
    p: any
) -> any {
    # ctrl_stmt: KW_SKIP | KW_BREAK | KW_CONTINUE
    ctrl = p.advance();
    semi = p.expect(Tok.SEMI.value);
    kids: list = [ctrl, semi];
    nd = UniCtrlStmt(ctrl=ctrl, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── Visit statement ────────────────────────────────────────────────────
def parse_visit_stmt(
    p: any
) -> any {
    # visit_stmt: KW_VISIT (COLON expression COLON)? expression (else_stmt | SEMI)
    visit_tok = p.expect(Tok.KW_VISIT.value);
    kids: list = [visit_tok];

    insert_loc = None;
    if p.check(Tok.COLON.value) {
        colon1 = p.advance();
        kids.append(colon1);
        insert_loc = parse_expression(p);
        kids.append(insert_loc);
        colon2 = p.expect(Tok.COLON.value);
        kids.append(colon2);
    }

    target = parse_expression(p);
    kids.append(target);

    else_body = None;
    if p.check(Tok.KW_ELSE.value) {
        else_body = parse_else_stmt(p);
        kids.append(else_body);
    } else {
        semi = p.expect(Tok.SEMI.value);
        kids.append(semi);
    }

    nd = UniVisitStmt(
        insert_loc=insert_loc, target=target, else_body=else_body, kid=kids
    );
    p.register_node(nd);
    return nd;
}

# ── Disengage statement ────────────────────────────────────────────────
def parse_disengage_stmt(
    p: any
) -> any {
    # disenage_stmt: KW_DISENGAGE SEMI
    dis_tok = p.expect(Tok.KW_DISENGAGE.value);
    semi = p.expect(Tok.SEMI.value);
    kids: list = [dis_tok, semi];
    nd = UniDisengageStmt(kid=kids);
    p.register_node(nd);
    return nd;
}

# ── Global reference ───────────────────────────────────────────────────
def parse_global_ref(
    p: any
) -> any {
    # global_ref: GLOBAL_OP name_list
    global_tok = p.advance();
    names: list = [];
    kids: list = [global_tok];
    while True {
        name = p.parse_named_ref();
        names.append(name);
        kids.append(name);
        if not p.check(Tok.COMMA.value) {
            break;
        }
        comma = p.advance();
        kids.append(comma);
    }
    semi = p.expect(Tok.SEMI.value);
    kids.append(semi);
    nd = UniGlobalStmt(target=names, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── Nonlocal reference ─────────────────────────────────────────────────
def parse_nonlocal_ref(
    p: any
) -> any {
    # nonlocal_ref: NONLOCAL_OP name_list
    nonlocal_tok = p.advance();
    names: list = [];
    kids: list = [nonlocal_tok];
    while True {
        name = p.parse_named_ref();
        names.append(name);
        kids.append(name);
        if not p.check(Tok.COMMA.value) {
            break;
        }
        comma = p.advance();
        kids.append(comma);
    }
    semi = p.expect(Tok.SEMI.value);
    kids.append(semi);
    nd = UniNonLocalStmt(target=names, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── Typed context block ────────────────────────────────────────────────
def parse_typed_ctx_block(
    p: any
) -> any {
    # typed_ctx_block: RETURN_HINT expression code_block
    hint_tok = p.expect(Tok.RETURN_HINT.value);
    type_ctx = parse_expression(p);
    block = parse_code_block_with_kids(p);
    body = block[0];
    kids: list = [hint_tok, type_ctx];
    kids.extend(block[1]);
    nd = UniTypedCtxBlock(type_ctx=type_ctx, body=body, kid=kids);
    p.register_node(nd);
    return nd;
}
