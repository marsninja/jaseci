# JSX element parsing for the Jac recursive descent parser.
#
# Handles JSX elements, fragments, attributes, and children.
#
# All functions take `p` (the parser instance) as first argument.
import from jaclang.pycore.unitree {
    UniNode,
    Token as UniToken,
    Name as UniName,
    String as UniString,
    Expr,
    JsxElement as UniJsxElement,
    JsxElementName as UniJsxElementName,
    JsxAttribute as UniJsxAttribute,
    JsxSpreadAttribute as UniJsxSpreadAttribute,
    JsxNormalAttribute as UniJsxNormalAttribute,
    JsxChild as UniJsxChild,
    JsxText as UniJsxText,
    JsxExpression as UniJsxExpression
}

import from jaclang.pycore.constant { Tokens as Tok }

import from jaclang.compiler.rd_parser.parser_exprs { parse_expression }

# ── JSX Element ───────────────────────────────────────────────────────
"""Parse jsx_element: jsx_self_closing | jsx_fragment | jsx_opening_closing."""
def parse_jsx_element(p: any) -> any {
    tok = p.peek();

    # Fragment: <>
    if tok.name == Tok.JSX_FRAG_OPEN.value {
        return _parse_jsx_fragment(p);
    }

    # Opening tag: <Name
    if tok.name == Tok.JSX_OPEN_START.value {
        return _parse_jsx_tag(p);
    }

    p.log_error("Expected JSX element", tok);
    return None;
}

"""Parse JSX self-closing or opening/closing tag."""
def _parse_jsx_tag(p: any) -> any {
    open_start = p.expect(Tok.JSX_OPEN_START.value);
    name = _parse_jsx_element_name(p);
    kids: list = [open_start, name];

    # Parse optional attributes
    attrs: list = [];
    while not p.at_end()
    and not p.check(Tok.JSX_SELF_CLOSE.value)
    and not p.check(Tok.JSX_TAG_END.value) {
        attr = _parse_jsx_attribute(p);
        if attr is not None {
            attrs.append(attr);
            kids.append(attr);
        } else {
            break;
        }
    }

    # Self-closing: />
    if p.check(Tok.JSX_SELF_CLOSE.value) {
        self_close = p.advance();
        kids.append(self_close);
        nd = UniJsxElement(
            name=name,
            attributes=attrs,
            children=None,
            is_self_closing=True,
            is_fragment=False,
            kid=kids
        );
        p.register_node(nd);
        return nd;
    }

    # Opening tag: >
    tag_end = p.expect(Tok.JSX_TAG_END.value);
    kids.append(tag_end);

    # Parse children
    children: list = [];
    while not p.at_end() and not p.check(Tok.JSX_CLOSE_START.value) {
        child = _parse_jsx_child(p);
        if child is not None {
            children.append(child);
            kids.append(child);
        } else {
            break;
        }
    }

    # Closing tag: </Name>
    close_start = p.expect(Tok.JSX_CLOSE_START.value);
    kids.append(close_start);
    close_name = _parse_jsx_element_name(p);
    kids.append(close_name);
    close_end = p.expect(Tok.JSX_TAG_END.value);
    kids.append(close_end);

    nd = UniJsxElement(
        name=name,
        attributes=attrs,
        children=children if len(children) > 0 else None,
        is_self_closing=False,
        is_fragment=False,
        kid=kids
    );
    p.register_node(nd);
    return nd;
}

"""Parse jsx_fragment: JSX_FRAG_OPEN jsx_children? JSX_FRAG_CLOSE."""
def _parse_jsx_fragment(p: any) -> any {
    frag_open = p.expect(Tok.JSX_FRAG_OPEN.value);
    kids: list = [frag_open];
    children: list = [];

    while not p.at_end() and not p.check(Tok.JSX_FRAG_CLOSE.value) {
        child = _parse_jsx_child(p);
        if child is not None {
            children.append(child);
            kids.append(child);
        } else {
            break;
        }
    }

    frag_close = p.expect(Tok.JSX_FRAG_CLOSE.value);
    kids.append(frag_close);

    nd = UniJsxElement(
        name=None,
        attributes=None,
        children=children if len(children) > 0 else None,
        is_self_closing=False,
        is_fragment=True,
        kid=kids
    );
    p.register_node(nd);
    return nd;
}

# ── JSX Element Name ──────────────────────────────────────────────────
"""Parse jsx_element_name: JSX_NAME (DOT JSX_NAME)*."""
def _parse_jsx_element_name(p: any) -> any {
    parts: list = [];
    kids: list = [];

    first = p.expect(Tok.JSX_NAME.value);
    parts.append(first);
    kids.append(first);

    while p.check(Tok.DOT.value) {
        dot = p.advance();
        kids.append(dot);
        part = p.expect(Tok.JSX_NAME.value);
        parts.append(part);
        kids.append(part);
    }

    nd = UniJsxElementName(parts=parts, kid=kids);
    p.register_node(nd);
    return nd;
}

# ── JSX Attributes ────────────────────────────────────────────────────
"""Parse jsx_attribute: jsx_spread_attribute | jsx_normal_attribute."""
def _parse_jsx_attribute(p: any) -> any {
    # Spread: { ...expr }
    if p.check(Tok.LBRACE.value) {
        return _parse_jsx_spread_attribute(p);
    }

    # Normal: JSX_NAME (= value)?
    if p.check(Tok.JSX_NAME.value) {
        return _parse_jsx_normal_attribute(p);
    }

    return None;
}

"""Parse jsx_spread_attribute: LBRACE ELLIPSIS expression RBRACE."""
def _parse_jsx_spread_attribute(p: any) -> any {
    lbrace = p.expect(Tok.LBRACE.value);
    ellipsis = p.expect(Tok.ELLIPSIS.value);
    expr = parse_expression(p);
    rbrace = p.expect(Tok.RBRACE.value);
    kids: list = [lbrace, ellipsis, expr, rbrace];
    nd = UniJsxSpreadAttribute(expr=expr, kid=kids);
    p.register_node(nd);
    return nd;
}

"""Parse jsx_normal_attribute: JSX_NAME (EQ jsx_attr_value)?."""
def _parse_jsx_normal_attribute(p: any) -> any {
    name = p.expect(Tok.JSX_NAME.value);
    kids: list = [name];
    value = None;

    if p.check(Tok.EQ.value) {
        eq = p.advance();
        kids.append(eq);
        value = _parse_jsx_attr_value(p);
        kids.append(value);
    }

    nd = UniJsxNormalAttribute(name=name, value=value, kid=kids);
    p.register_node(nd);
    return nd;
}

"""Parse jsx_attr_value: STRING | LBRACE expression RBRACE."""
def _parse_jsx_attr_value(p: any) -> any {
    if p.check(Tok.STRING.value) {
        return p.advance();
    }
    lbrace = p.expect(Tok.LBRACE.value);
    expr = parse_expression(p);
    rbrace = p.expect(Tok.RBRACE.value);
    return expr;
}

# ── JSX Children ──────────────────────────────────────────────────────
"""Parse jsx_child: jsx_element | jsx_expression | jsx_text."""
def _parse_jsx_child(p: any) -> any {
    tok = p.peek();

    # Nested JSX element
    if tok.name == Tok.JSX_OPEN_START.value or tok.name == Tok.JSX_FRAG_OPEN.value {
        return parse_jsx_element(p);
    }

    # JSX expression: { expression }
    if tok.name == Tok.LBRACE.value {
        return _parse_jsx_expression(p);
    }

    # JSX text
    if tok.name == Tok.JSX_TEXT.value {
        return _parse_jsx_text(p);
    }

    # Keywords as text in JSX context
    if _is_jsx_text_keyword(tok) {
        return _parse_jsx_text_keyword(p);
    }

    return None;
}

"""Parse jsx_expression: LBRACE expression RBRACE."""
def _parse_jsx_expression(p: any) -> any {
    lbrace = p.expect(Tok.LBRACE.value);
    expr = parse_expression(p);
    rbrace = p.expect(Tok.RBRACE.value);
    kids: list = [lbrace, expr, rbrace];
    nd = UniJsxExpression(expr=expr, kid=kids);
    p.register_node(nd);
    return nd;
}

"""Parse jsx_text: JSX_TEXT."""
def _parse_jsx_text(p: any) -> any {
    text_tok = p.advance();
    escaped = text_tok.value;
    nd = UniJsxText(value=escaped, kid=[text_tok]);
    p.register_node(nd);
    return nd;
}

"""Parse keyword used as text in JSX content."""
def _parse_jsx_text_keyword(p: any) -> any {
    kw_tok = p.advance();
    nd = UniJsxText(value=kw_tok, kid=[kw_tok]);
    p.register_node(nd);
    return nd;
}

glob JSX_TEXT_KEYWORD_TOKENS: set = {Tok.KW_TO.value,Tok.KW_AS.value,Tok.KW_FROM.value,Tok.KW_WITH.value,Tok.KW_IF.value,Tok.KW_FOR.value,Tok.KW_BY.value,Tok.KW_IN.value,Tok.KW_IS.value,Tok.KW_HAS.value,Tok.KW_CAN.value,Tok.KW_TRY.value,Tok.KW_MATCH.value,Tok.KW_CASE.value,Tok.KW_TEST.value,Tok.KW_ELSE.value,Tok.KW_RETURN.value,Tok.KW_BREAK.value,Tok.KW_CLASS.value,Tok.KW_NODE.value,Tok.KW_EDGE.value,Tok.KW_VISIT.value,Tok.KW_ENTRY.value,Tok.KW_EXIT.value,Tok.KW_WAIT.value,Tok.KW_FLOW.value,Tok.KW_SKIP.value,Tok.KW_CONTINUE.value,Tok.KW_REPORT.value,Tok.KW_RAISE.value,Tok.KW_DEFAULT.value,Tok.KW_YIELD.value,Tok.KW_EXCEPT.value,Tok.KW_FINALLY.value,Tok.KW_ASSERT.value,Tok.KW_WHILE.value,Tok.KW_STATIC.value,Tok.KW_OVERRIDE.value,Tok.KW_SWITCH.value,Tok.KW_HERE.value,Tok.KW_SELF.value,Tok.KW_PROPS.value,Tok.KW_SUPER.value,Tok.KW_ROOT.value,Tok.NOT.value,Tok.KW_DELETE.value,Tok.KW_IMPORT.value,Tok.KW_INCLUDE.value,Tok.KW_ASYNC.value,Tok.KW_AWAIT.value,Tok.KW_SPAWN.value,Tok.KW_LAMBDA.value,Tok.KW_ENUM.value,Tok.KW_OBJECT.value,Tok.KW_ABSTRACT.value,Tok.KW_WALKER.value,Tok.KW_IMPL.value,Tok.KW_SEM.value,Tok.KW_ELIF.value,Tok.KW_DISENGAGE.value,Tok.KW_PRIV.value,Tok.KW_PUB.value,Tok.KW_PROT.value,Tok.KW_GLOBAL.value,Tok.KW_DEF.value,Tok.KW_CLIENT.value,Tok.KW_INIT.value,Tok.KW_POST_INIT.value,Tok.KW_VISITOR.value,Tok.KW_AND.value,Tok.KW_OR.value};

"""Check if a token is a keyword that can appear as text in JSX."""
def _is_jsx_text_keyword(tok: any) -> bool {
    return tok.name in JSX_TEXT_KEYWORD_TOKENS;
}
