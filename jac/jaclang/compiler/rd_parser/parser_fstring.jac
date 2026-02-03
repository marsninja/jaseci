# F-string and multistring parsing for the Jac recursive descent parser.
#
# Handles fstring, multistring, and formatted value parts.
#
# All functions take `p` (the parser instance) as first argument.
import from jaclang.pycore.unitree {
    UniNode,
    Token as UniToken,
    Name as UniName,
    String as UniString,
    Expr,
    FString as UniFString,
    MultiString as UniMultiString,
    FormattedValue as UniFormattedValue
}

import from jaclang.pycore.constant { Tokens as Tok }

import from jaclang.compiler.rd_parser.parser_exprs { parse_expression }

# ── F-string start token sets ─────────────────────────────────────────
glob FSTRING_START_TOKENS:
         set = {Tok.F_DQ_START.value,Tok.F_SQ_START.value,Tok.F_TDQ_START.value,Tok.F_TSQ_START.value,Tok.RF_DQ_START.value,Tok.RF_SQ_START.value,Tok.RF_TDQ_START.value,Tok.RF_TSQ_START.value},
     FSTRING_TEXT_TOKENS: set = {Tok.F_TEXT_DQ.value,Tok.F_TEXT_SQ.value,Tok.F_TEXT_TDQ.value,Tok.F_TEXT_TSQ.value,Tok.RF_TEXT_DQ.value,Tok.RF_TEXT_SQ.value,Tok.RF_TEXT_TDQ.value,Tok.RF_TEXT_TSQ.value};

# ── Multistring ───────────────────────────────────────────────────────
"""Parse multistring: (fstring | STRING)+."""
def parse_multistring(p: any) -> any {
    strings: list = [];
    kids: list = [];

    first = _parse_string_or_fstring(p);
    strings.append(first);
    kids.append(first);

    while p.check(Tok.STRING.value) or p.peek().name in FSTRING_START_TOKENS {
        nd = _parse_string_or_fstring(p);
        strings.append(nd);
        kids.append(nd);
    }

    if len(strings) == 1 and isinstance(strings[0], UniString) {
        return strings[0];
    }

    nd = UniMultiString(strings=strings, kid=kids);
    p.register_node(nd);
    return nd;
}

"""Parse either a regular string or an f-string."""
def _parse_string_or_fstring(p: any) -> any {
    if p.peek().name in FSTRING_START_TOKENS {
        return parse_fstring(p);
    }
    return p.advance();
}

# ── F-string ──────────────────────────────────────────────────────────
"""Parse fstring: F_*_START fstr_*_part* F_*_END."""
def parse_fstring(p: any) -> any {
    start_tok = p.advance();
    kids: list = [start_tok];
    parts: list = [];

    # Determine the end token and text token based on start
    end_tok_name = _get_fstring_end_token(start_tok.name);
    text_tok_name = _get_fstring_text_token(start_tok.name);

    # Parse parts until end token
    while not p.at_end() and not p.check(end_tok_name) {
        part = _parse_fstr_part(p, text_tok_name);
        if part is not None {
            parts.append(part);
            kids.append(part);
        }
    }

    end_tok = p.expect(end_tok_name);
    kids.append(end_tok);

    nd = UniFString(start=start_tok, parts=parts, end=end_tok, kid=kids);
    p.register_node(nd);
    return nd;
}

"""Get the matching end token name for a given f-string start token."""
def _get_fstring_end_token(start_name: str) -> str {
    if start_name == Tok.F_DQ_START.value or start_name == Tok.RF_DQ_START.value {
        return Tok.F_DQ_END.value;
    }
    if start_name == Tok.F_SQ_START.value or start_name == Tok.RF_SQ_START.value {
        return Tok.F_SQ_END.value;
    }
    if start_name == Tok.F_TDQ_START.value or start_name == Tok.RF_TDQ_START.value {
        return Tok.F_TDQ_END.value;
    }
    if start_name == Tok.F_TSQ_START.value or start_name == Tok.RF_TSQ_START.value {
        return Tok.F_TSQ_END.value;
    }
    return Tok.F_DQ_END.value;
}

"""Get the matching text token name for a given f-string start token."""
def _get_fstring_text_token(start_name: str) -> str {
    if start_name == Tok.F_DQ_START.value {
        return Tok.F_TEXT_DQ.value;
    }
    if start_name == Tok.F_SQ_START.value {
        return Tok.F_TEXT_SQ.value;
    }
    if start_name == Tok.F_TDQ_START.value {
        return Tok.F_TEXT_TDQ.value;
    }
    if start_name == Tok.F_TSQ_START.value {
        return Tok.F_TEXT_TSQ.value;
    }
    if start_name == Tok.RF_DQ_START.value {
        return Tok.RF_TEXT_DQ.value;
    }
    if start_name == Tok.RF_SQ_START.value {
        return Tok.RF_TEXT_SQ.value;
    }
    if start_name == Tok.RF_TDQ_START.value {
        return Tok.RF_TEXT_TDQ.value;
    }
    if start_name == Tok.RF_TSQ_START.value {
        return Tok.RF_TEXT_TSQ.value;
    }
    return Tok.F_TEXT_DQ.value;
}

"""Parse a single f-string part: text | {{ | }} | {expression CONV? (:fformat*)?}."""
def _parse_fstr_part(p: any, text_tok_name: str) -> any {
    tok = p.peek();

    # Plain text - lexer already creates String nodes for these
    if tok.name == text_tok_name or tok.name in FSTRING_TEXT_TOKENS {
        return p.advance();  # Already a String node from lexer

    }

    # Double brace escapes {{ or }} - lexer already creates String nodes with correct values
    if tok.name == Tok.D_LBRACE.value or tok.name == Tok.D_RBRACE.value {
        return p.advance();  # Already a String node from lexer

    }

    # Formatted expression: { expression CONV? (COLON fformat*)? }
    if tok.name == Tok.LBRACE.value {
        return _parse_formatted_value(p);
    }

    # Unknown token in fstring context - skip
    return p.advance();
}

"""Parse { expression CONV? (COLON fformat*)? }."""
def _parse_formatted_value(p: any) -> any {
    lbrace = p.expect(Tok.LBRACE.value);
    expr = parse_expression(p);
    kids: list = [lbrace, expr];

    # Optional conversion: !r, !s, !a
    conversion = -1;
    if p.check(Tok.CONV.value) {
        conv_tok = p.advance();
        kids.append(conv_tok);
        conv_char = conv_tok.value;
        if len(conv_char) > 1 {
            conversion = ord(conv_char[1]);
        }
    }

    # Optional format spec: COLON fformat*
    format_spec = None;
    if p.check(Tok.COLON.value) {
        colon = p.advance();
        kids.append(colon);
        format_parts: list = [];
        while not p.at_end() and not p.check(Tok.RBRACE.value) {
            part = _parse_fformat(p);
            if part is not None {
                format_parts.append(part);
                kids.append(part);
            } else {
                break;
            }
        }
        if len(format_parts) == 1 and isinstance(format_parts[0], UniString) {
            format_spec = format_parts[0];
        } elif len(format_parts) > 0 {
            format_spec = UniFString(
                start=None, parts=format_parts, end=None, kid=format_parts
            );
            p.register_node(format_spec);
        }
    }

    rbrace = p.expect(Tok.RBRACE.value);
    kids.append(rbrace);

    nd = UniFormattedValue(
        format_part=expr, conversion=conversion, format_spec=format_spec, kid=kids
    );
    p.register_node(nd);
    return nd;
}

"""Parse fformat: F_FORMAT_TEXT | D_LBRACE | D_RBRACE | {expression CONV? (:fformat*)?}."""
def _parse_fformat(p: any) -> any {
    tok = p.peek();

    # Lexer already creates String nodes for these tokens
    if tok.name == Tok.F_FORMAT_TEXT.value {
        return p.advance();
    }
    if tok.name == Tok.D_LBRACE.value or tok.name == Tok.D_RBRACE.value {
        return p.advance();
    }
    if tok.name == Tok.LBRACE.value {
        return _parse_formatted_value(p);
    }
    return None;
}
