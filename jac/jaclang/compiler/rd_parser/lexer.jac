"""Handwritten lexer for the Jac language.

Produces uni.Token (and subclasses) directly, with full source location tracking.
Supports mode-based context-sensitive tokenization for f-strings and JSX.
"""

import re;

import from jaclang.pycore.unitree {
    Token as UniToken,
    Name as UniName,
    Semi as UniSemi,
    Float as UniFloat,
    Int as UniInt,
    String as UniString,
    Bool as UniBool,
    Null as UniNull,
    Ellipsis as UniEllipsis,
    BuiltinType as UniBuiltinType,
    CommentToken as UniCommentToken,
    Source as UniSource,
    SpecialVarRef as UniSpecialVarRef
}

import from jaclang.pycore.constant { Tokens as Tok }

# ── Lexer Mode Enum ──────────────────────────────────────────────────────────
enum LexerMode {
    NORMAL = "normal",
    FSTRING_DQ = "fstring_dq",
    FSTRING_SQ = "fstring_sq",
    FSTRING_TDQ = "fstring_tdq",
    FSTRING_TSQ = "fstring_tsq",
    FSTRING_EXPR = "fstring_expr",
    FSTRING_FORMAT = "fstring_format",  # For format specs after : in f-string expressions
    JSX_TAG = "jsx_tag",
    JSX_CONTENT = "jsx_content"
}

# ── Keyword Map ──────────────────────────────────────────────────────────────
glob KEYWORD_MAP:
         dict = {
         "abs": Tok.KW_ABSTRACT,
         "obj": Tok.KW_OBJECT,
         "class": Tok.KW_CLASS,
         "enum": Tok.KW_ENUM,
         "node": Tok.KW_NODE,
         "edge": Tok.KW_EDGE,
         "walker": Tok.KW_WALKER,
         "def": Tok.KW_DEF,
         "can": Tok.KW_CAN,
         "static": Tok.KW_STATIC,
         "override": Tok.KW_OVERRIDE,
         "has": Tok.KW_HAS,
         "if": Tok.KW_IF,
         "elif": Tok.KW_ELIF,
         "else": Tok.KW_ELSE,
         "for": Tok.KW_FOR,
         "to": Tok.KW_TO,
         "by": Tok.KW_BY,
         "while": Tok.KW_WHILE,
         "continue": Tok.KW_CONTINUE,
         "break": Tok.KW_BREAK,
         "skip": Tok.KW_SKIP,
         "return": Tok.KW_RETURN,
         "yield": Tok.KW_YIELD,
         "del": Tok.KW_DELETE,
         "try": Tok.KW_TRY,
         "except": Tok.KW_EXCEPT,
         "finally": Tok.KW_FINALLY,
         "raise": Tok.KW_RAISE,
         "assert": Tok.KW_ASSERT,
         "import": Tok.KW_IMPORT,
         "include": Tok.KW_INCLUDE,
         "from": Tok.KW_FROM,
         "as": Tok.KW_AS,
         "with": Tok.KW_WITH,
         "entry": Tok.KW_ENTRY,
         "exit": Tok.KW_EXIT,
         "async": Tok.KW_ASYNC,
         "await": Tok.KW_AWAIT,
         "flow": Tok.KW_FLOW,
         "wait": Tok.KW_WAIT,
         "spawn": Tok.KW_SPAWN,
         "test": Tok.KW_TEST,
         "visit": Tok.KW_VISIT,
         "disengage": Tok.KW_DISENGAGE,
         "report": Tok.KW_REPORT,
         "match": Tok.KW_MATCH,
         "switch": Tok.KW_SWITCH,
         "case": Tok.KW_CASE,
         "default": Tok.KW_DEFAULT,
         "impl": Tok.KW_IMPL,
         "sem": Tok.KW_SEM,
         "lambda": Tok.KW_LAMBDA,
         "glob": Tok.KW_GLOBAL,
         "priv": Tok.KW_PRIV,
         "pub": Tok.KW_PUB,
         "protect": Tok.KW_PROT,
         "cl": Tok.KW_CLIENT,
         "sv": Tok.KW_SERVER,
         "na": Tok.KW_NATIVE,
         # Logic keyword-operators
         "and": Tok.KW_AND,
         "or": Tok.KW_OR,
         "not": Tok.NOT,
         "in": Tok.KW_IN,
         "is": Tok.KW_IS,
         # Literals
         "True": Tok.BOOL,
         "False": Tok.BOOL,
         "None": Tok.NULL,
         # Special refs
         "init": Tok.KW_INIT,
         "postinit": Tok.KW_POST_INIT,
         "self": Tok.KW_SELF,
         "props": Tok.KW_PROPS,
         "super": Tok.KW_SUPER,
         "root": Tok.KW_ROOT,
         "here": Tok.KW_HERE,
         "visitor": Tok.KW_VISITOR,
         # Global/nonlocal as keyword-operators
         "global": Tok.GLOBAL_OP,
         "nonlocal": Tok.NONLOCAL_OP
     },
     BUILTIN_TYPE_MAP: dict = {
         "str": Tok.TYP_STRING,
         "int": Tok.TYP_INT,
         "float": Tok.TYP_FLOAT,
         "list": Tok.TYP_LIST,
         "tuple": Tok.TYP_TUPLE,
         "set": Tok.TYP_SET,
         "dict": Tok.TYP_DICT,
         "bool": Tok.TYP_BOOL,
         "bytes": Tok.TYP_BYTES,
         "any": Tok.TYP_ANY,
         "type": Tok.TYP_TYPE
     },
     SPECIAL_REF_TOKENS: set = {Tok.KW_INIT.value,Tok.KW_POST_INIT.value,Tok.KW_SELF.value,Tok.KW_PROPS.value,Tok.KW_SUPER.value,Tok.KW_ROOT.value,Tok.KW_HERE.value,Tok.KW_VISITOR.value},
     NAME_TOKENS: set = {Tok.NAME.value,Tok.KWESC_NAME.value,Tok.KW_INIT.value,Tok.KW_POST_INIT.value,Tok.KW_SELF.value,Tok.KW_PROPS.value,Tok.KW_SUPER.value,Tok.KW_ROOT.value,Tok.KW_HERE.value,Tok.KW_VISITOR.value},
     EOF_NAME: str = "__EOF__";

# ── JacLexer ─────────────────────────────────────────────────────────────────
obj JacLexer {
    """Lexer for the Jac language with mode-based context-sensitive tokenization."""
    has source: str,
        orig_src: UniSource,
        pos: int = 0,
        line: int = 1,
        col: int = 1,
        mode_stack: list = [],
        comments: list = [],
        peeked: list = [],
        terminals: list = [],
        all_tokens: list = [],
        in_jsx_close_tag: bool = False,
        fstring_bracket_depth: int = 0;

    def init(source: str, orig_src: UniSource) {
        self.source = source;
        self.orig_src = orig_src;
        self.pos = 0;
        self.line = 1;
        self.col = 1;
        self.mode_stack = [LexerMode.NORMAL];
        self.comments = [];
        self.peeked = [];
        self.terminals = [];
        self.all_tokens = [];
        self.in_jsx_close_tag = False;
        self.fstring_bracket_depth = 0;
    }

    # ── Mode management ──────────────────────────────────────────────────
    def current_mode -> str {
        if len(self.mode_stack) > 0 {
            return self.mode_stack[-1];
        }
        return LexerMode.NORMAL;
    }

    def push_mode(mode: str) {
        self.mode_stack.append(mode);
    }

    def pop_mode {
        if len(self.mode_stack) > 1 {
            self.mode_stack.pop();
        }
    }

    # ── Position helpers ─────────────────────────────────────────────────
    def at_end -> bool {
        return self.pos >= len(self.source);
    }

    def char_at(offset: int = 0) -> str {
        # Return character at current pos + offset, or empty string if out of bounds.
        idx = self.pos + offset;
        if idx < len(self.source) {
            return self.source[idx];
        }
        return "";
    }

    def starts_with(s: str) -> bool {
        # Check if source at current position starts with given string.
        return self.source[self.pos:self.pos + len(s)] == s;
    }

    def advance_char -> str {
        # Advance position by one character, updating line/col tracking.
        ch = self.source[self.pos];
        self.pos += 1;
        if ch == "\n" {
            self.line += 1;
            self.col = 1;
        } else {
            self.col += 1;
        }
        return ch;
    }

    def advance_n(n: int) {
        # Advance position by n characters, updating line/col tracking.
        i = 0;
        while i < n {
            self.advance_char();
            i += 1;
        }
    }

    # ── Token creation ───────────────────────────────────────────────────
    def make_token(
        tok_type: str, value: str, start_pos: int, start_line: int, start_col: int
    ) -> UniToken {
        # Create the appropriate Token subclass based on token type.
        end_pos = self.pos;
        end_line = self.line;
        end_col = self.col;

        tok_name = tok_type;

        # Determine correct subclass
        if tok_name in NAME_TOKENS {
            ret = UniName(
                orig_src=self.orig_src,
                name=tok_name,
                value=value[2:] if tok_name == Tok.KWESC_NAME.value else value,
                line=start_line,
                end_line=end_line,
                col_start=start_col,
                col_end=end_col,
                pos_start=start_pos,
                pos_end=end_pos,
                is_kwesc=tok_name == Tok.KWESC_NAME.value
            );
            self.terminals.append(ret);
            self.all_tokens.append(ret);
            return ret;
        } elif tok_name == Tok.SEMI.value {
            ret = UniSemi(
                orig_src=self.orig_src,
                name=tok_name,
                value=value,
                line=start_line,
                end_line=end_line,
                col_start=start_col,
                col_end=end_col,
                pos_start=start_pos,
                pos_end=end_pos
            );
            self.terminals.append(ret);
            self.all_tokens.append(ret);
            return ret;
        } elif tok_name == Tok.NULL.value {
            ret = UniNull(
                orig_src=self.orig_src,
                name=tok_name,
                value=value,
                line=start_line,
                end_line=end_line,
                col_start=start_col,
                col_end=end_col,
                pos_start=start_pos,
                pos_end=end_pos
            );
            self.terminals.append(ret);
            self.all_tokens.append(ret);
            return ret;
        } elif tok_name == Tok.ELLIPSIS.value {
            ret = UniEllipsis(
                orig_src=self.orig_src,
                name=tok_name,
                value=value,
                line=start_line,
                end_line=end_line,
                col_start=start_col,
                col_end=end_col,
                pos_start=start_pos,
                pos_end=end_pos
            );
            self.terminals.append(ret);
            self.all_tokens.append(ret);
            return ret;
        } elif tok_name == Tok.FLOAT.value {
            ret = UniFloat(
                orig_src=self.orig_src,
                name=tok_name,
                value=value,
                line=start_line,
                end_line=end_line,
                col_start=start_col,
                col_end=end_col,
                pos_start=start_pos,
                pos_end=end_pos
            );
            self.terminals.append(ret);
            self.all_tokens.append(ret);
            return ret;
        } elif tok_name in [Tok.INT.value, Tok.HEX.value, Tok.BIN.value, Tok.OCT.value] {
            ret = UniInt(
                orig_src=self.orig_src,
                name=tok_name,
                value=value,
                line=start_line,
                end_line=end_line,
                col_start=start_col,
                col_end=end_col,
                pos_start=start_pos,
                pos_end=end_pos
            );
            self.terminals.append(ret);
            self.all_tokens.append(ret);
            return ret;
        } elif tok_name in [
            Tok.STRING.value,
            Tok.D_LBRACE.value,
            Tok.D_RBRACE.value,
            Tok.F_TEXT_DQ.value,
            Tok.F_TEXT_SQ.value,
            Tok.F_TEXT_TDQ.value,
            Tok.F_TEXT_TSQ.value,
            Tok.RF_TEXT_DQ.value,
            Tok.RF_TEXT_SQ.value,
            Tok.RF_TEXT_TDQ.value,
            Tok.RF_TEXT_TSQ.value,
            Tok.F_FORMAT_TEXT.value
        ] {
            actual_value = value;
            if tok_name == Tok.D_LBRACE.value {
                actual_value = "{";
            } elif tok_name == Tok.D_RBRACE.value {
                actual_value = "}";
            }
            ret = UniString(
                orig_src=self.orig_src,
                name=tok_name,
                value=actual_value,
                line=start_line,
                end_line=end_line,
                col_start=start_col,
                col_end=end_col,
                pos_start=start_pos,
                pos_end=end_pos
            );
            self.terminals.append(ret);
            self.all_tokens.append(ret);
            return ret;
        } elif tok_name == Tok.BOOL.value {
            ret = UniBool(
                orig_src=self.orig_src,
                name=tok_name,
                value=value,
                line=start_line,
                end_line=end_line,
                col_start=start_col,
                col_end=end_col,
                pos_start=start_pos,
                pos_end=end_pos
            );
            self.terminals.append(ret);
            self.all_tokens.append(ret);
            return ret;
        } elif tok_name == Tok.PYNLINE.value {
            ret = UniToken(
                orig_src=self.orig_src,
                name=tok_name,
                value=value,
                line=start_line,
                end_line=end_line,
                col_start=start_col,
                col_end=end_col,
                pos_start=start_pos,
                pos_end=end_pos
            );
            self.terminals.append(ret);
            self.all_tokens.append(ret);
            return ret;
        }

        # Builtin types produce BuiltinType nodes
        if tok_name in [
            Tok.TYP_STRING.value,
            Tok.TYP_INT.value,
            Tok.TYP_FLOAT.value,
            Tok.TYP_LIST.value,
            Tok.TYP_TUPLE.value,
            Tok.TYP_SET.value,
            Tok.TYP_DICT.value,
            Tok.TYP_BOOL.value,
            Tok.TYP_BYTES.value,
            Tok.TYP_ANY.value,
            Tok.TYP_TYPE.value
        ] {
            ret = UniBuiltinType(
                orig_src=self.orig_src,
                name=tok_name,
                value=value,
                line=start_line,
                end_line=end_line,
                col_start=start_col,
                col_end=end_col,
                pos_start=start_pos,
                pos_end=end_pos
            );
            self.terminals.append(ret);
            self.all_tokens.append(ret);
            return ret;
        }

        # Default: plain Token
        ret = UniToken(
            orig_src=self.orig_src,
            name=tok_name,
            value=value,
            line=start_line,
            end_line=end_line,
            col_start=start_col,
            col_end=end_col,
            pos_start=start_pos,
            pos_end=end_pos
        );
        self.terminals.append(ret);
        self.all_tokens.append(ret);
        return ret;
    }

    def make_eof_token -> UniToken {
        # Create an EOF sentinel token.
        return UniToken(
            orig_src=self.orig_src,
            name=EOF_NAME,
            value="",
            line=self.line,
            end_line=self.line,
            col_start=self.col,
            col_end=self.col,
            pos_start=self.pos,
            pos_end=self.pos
        );
    }

    # ── Whitespace and comments ──────────────────────────────────────────
    def skip_whitespace_and_comments {
        # Skip whitespace and collect comments.
        while not self.at_end() {
            ch = self.char_at();

            # Whitespace
            if ch in " \t\r\n\f" {
                self.advance_char();
                continue;
            }

            # Block comment: #* ... *#
            if ch == "#" and self.char_at(1) == "*" {
                self._scan_block_comment();
                continue;
            }

            # Line comment: # ...
            if ch == "#" {
                self._scan_line_comment();
                continue;
            }

            break;
        }
    }

    def _scan_line_comment {
        start_pos = self.pos;
        start_line = self.line;
        start_col = self.col;
        value = "";
        while not self.at_end() and self.char_at() != "\n" {
            value += self.advance_char();
        }
        comment = UniCommentToken(
            orig_src=self.orig_src,
            name=Tok.COMMENT.value,
            value=value,
            line=start_line,
            end_line=self.line,
            col_start=start_col,
            col_end=self.col,
            pos_start=start_pos,
            pos_end=self.pos,
            kid=[]
        );
        self.comments.append(comment);
    }

    def _scan_block_comment {
        start_pos = self.pos;
        start_line = self.line;
        start_col = self.col;
        value = "";
        # consume #*
        value += self.advance_char();
        value += self.advance_char();
        while not self.at_end() {
            if self.char_at() == "*" and self.char_at(1) == "#" {
                value += self.advance_char();
                value += self.advance_char();
                break;
            }
            value += self.advance_char();
        }
        comment = UniCommentToken(
            orig_src=self.orig_src,
            name=Tok.COMMENT.value,
            value=value,
            line=start_line,
            end_line=self.line,
            col_start=start_col,
            col_end=self.col,
            pos_start=start_pos,
            pos_end=self.pos,
            kid=[]
        );
        self.comments.append(comment);
    }

    # ── Number scanning ──────────────────────────────────────────────────
    def _scan_number -> UniToken {
        # Scan a numeric literal (INT, FLOAT, HEX, BIN, OCT).
        start_pos = self.pos;
        start_line = self.line;
        start_col = self.col;

        ch = self.char_at();
        ch1 = self.char_at(1);

        # Hex: 0x...
        if ch == "0" and ch1 in "xX" {
            value = self.advance_char() + self.advance_char();
            while not self.at_end() and (self.char_at() in "0123456789abcdefABCDEF_") {
                value += self.advance_char();
            }
            return self.make_token(
                Tok.HEX.value, value, start_pos, start_line, start_col
            );
        }

        # Binary: 0b...
        if ch == "0" and ch1 in "bB" {
            value = self.advance_char() + self.advance_char();
            while not self.at_end() and (self.char_at() in "01_") {
                value += self.advance_char();
            }
            return self.make_token(
                Tok.BIN.value, value, start_pos, start_line, start_col
            );
        }

        # Octal: 0o...
        if ch == "0" and ch1 in "oO" {
            value = self.advance_char() + self.advance_char();
            while not self.at_end() and (self.char_at() in "01234567_") {
                value += self.advance_char();
            }
            return self.make_token(
                Tok.OCT.value, value, start_pos, start_line, start_col
            );
        }

        # Integer or float
        value = "";
        is_float = False;

        # Integer part
        while not self.at_end() and (self.char_at() in "0123456789_") {
            value += self.advance_char();
        }

        # Decimal point
        if not self.at_end() and self.char_at() == "." and self.char_at(1) != "." {
            is_float = True;
            value += self.advance_char();
            while not self.at_end() and (self.char_at() in "0123456789_") {
                value += self.advance_char();
            }
        }

        # Exponent
        if not self.at_end() and self.char_at() in "eE" {
            is_float = True;
            value += self.advance_char();
            if not self.at_end() and self.char_at() in "+-" {
                value += self.advance_char();
            }
            while not self.at_end() and (self.char_at() in "0123456789_") {
                value += self.advance_char();
            }
        }

        if is_float {
            return self.make_token(
                Tok.FLOAT.value, value, start_pos, start_line, start_col
            );
        }
        return self.make_token(Tok.INT.value, value, start_pos, start_line, start_col);
    }

    def _scan_dot_number -> UniToken {
        # Scan a number starting with dot: .5, .5e3, etc.
        start_pos = self.pos;
        start_line = self.line;
        start_col = self.col;
        value = self.advance_char();  # consume '.'
        while not self.at_end() and self.char_at() in "0123456789_" {
            value += self.advance_char();
        }
        # Exponent
        if not self.at_end() and self.char_at() in "eE" {
            value += self.advance_char();
            if not self.at_end() and self.char_at() in "+-" {
                value += self.advance_char();
            }
            while not self.at_end() and self.char_at() in "0123456789_" {
                value += self.advance_char();
            }
        }
        return self.make_token(
            Tok.FLOAT.value, value, start_pos, start_line, start_col
        );
    }

    # ── String scanning ──────────────────────────────────────────────────
    def _scan_string(prefix: str = "") -> UniToken {
        # Scan a string literal with optional prefix (r, b, rb, br).
        start_pos = self.pos;
        start_line = self.line;
        start_col = self.col;

        # Skip prefix chars already consumed
        value = prefix;

        quote_char = self.char_at();
        # Check for triple-quote
        if self.char_at(1) == quote_char and self.char_at(2) == quote_char {
            # Triple-quoted string
            triple = quote_char * 3;
            value += self.advance_char() + self.advance_char() + self.advance_char();
            while not self.at_end() {
                if self.char_at() == quote_char
                and self.char_at(1) == quote_char
                and self.char_at(2) == quote_char {
                    value += self.advance_char() + self.advance_char() + self.advance_char();
                    break;
                }
                if self.char_at() == "\\" {
                    value += self.advance_char();
                    if not self.at_end() {
                        value += self.advance_char();
                    }
                } else {
                    value += self.advance_char();
                }
            }
        } else {
            # Single-quoted string
            value += self.advance_char();  # opening quote
            while not self.at_end()
            and self.char_at() != quote_char
            and self.char_at() != "\n" {
                if self.char_at() == "\\" {
                    value += self.advance_char();
                    if not self.at_end() {
                        value += self.advance_char();
                    }
                } else {
                    value += self.advance_char();
                }
            }
            if not self.at_end() and self.char_at() == quote_char {
                value += self.advance_char();  # closing quote
            }
        }

        return self.make_token(
            Tok.STRING.value, value, start_pos, start_line, start_col
        );
    }

    # ── F-string scanning ────────────────────────────────────────────────
    def _scan_fstring_start(prefix: str) -> UniToken {
        # Scan f-string opening (e.g., f", f', f\"\"\", rf', etc.).
        start_pos = self.pos;
        start_line = self.line;
        start_col = self.col;

        value = prefix;
        is_raw = "r" in prefix.lower();

        quote_char = self.char_at();
        # Check for triple-quote
        if self.char_at(1) == quote_char and self.char_at(2) == quote_char {
            value += self.advance_char() + self.advance_char() + self.advance_char();
            if quote_char == '"' {
                tok_type = Tok.RF_TDQ_START.value if is_raw else Tok.F_TDQ_START.value;
                self.push_mode(LexerMode.FSTRING_TDQ);
            } else {
                tok_type = Tok.RF_TSQ_START.value if is_raw else Tok.F_TSQ_START.value;
                self.push_mode(LexerMode.FSTRING_TSQ);
            }
        } else {
            value += self.advance_char();  # single quote
            if quote_char == '"' {
                tok_type = Tok.RF_DQ_START.value if is_raw else Tok.F_DQ_START.value;
                self.push_mode(LexerMode.FSTRING_DQ);
            } else {
                tok_type = Tok.RF_SQ_START.value if is_raw else Tok.F_SQ_START.value;
                self.push_mode(LexerMode.FSTRING_SQ);
            }
        }

        return self.make_token(tok_type, value, start_pos, start_line, start_col);
    }

    def _scan_fstring_body -> UniToken {
        # Scan f-string body content in the appropriate mode.
        mode = self.current_mode();
        start_pos = self.pos;
        start_line = self.line;
        start_col = self.col;

        is_raw = mode in [LexerMode.FSTRING_TDQ, LexerMode.FSTRING_TSQ] and False;
        # Determine is_raw from mode name (modes with RF prefix are handled differently)
        # Actually, we track raw-ness by the start token. For now detect from f-string mode.

        # Determine quote char and triple
        is_triple = mode in [LexerMode.FSTRING_TDQ, LexerMode.FSTRING_TSQ];

        if mode in [LexerMode.FSTRING_DQ, LexerMode.FSTRING_TDQ] {
            quote_char = '"';
        } else {
            quote_char = "'";
        }

        # Check for end of f-string
        if is_triple {
            end_str = quote_char * 3;
            if self.starts_with(end_str) {
                value = self.advance_char() + self.advance_char() + self.advance_char();
                self.pop_mode();
                tok_type = Tok.F_TDQ_END.value
                if quote_char == '"'
                else Tok.F_TSQ_END.value;
                return self.make_token(
                    tok_type, value, start_pos, start_line, start_col
                );
            }
        } else {
            if self.char_at() == quote_char {
                value = self.advance_char();
                self.pop_mode();
                tok_type = Tok.F_DQ_END.value
                if quote_char == '"'
                else Tok.F_SQ_END.value;
                return self.make_token(
                    tok_type, value, start_pos, start_line, start_col
                );
            }
        }

        # Escaped braces {{ and }}
        if self.char_at() == "{" and self.char_at(1) == "{" {
            value = self.advance_char() + self.advance_char();
            return self.make_token(
                Tok.D_LBRACE.value, value, start_pos, start_line, start_col
            );
        }
        if self.char_at() == "}" and self.char_at(1) == "}" {
            value = self.advance_char() + self.advance_char();
            return self.make_token(
                Tok.D_RBRACE.value, value, start_pos, start_line, start_col
            );
        }

        # Expression start {
        if self.char_at() == "{" {
            value = self.advance_char();
            self.push_mode(LexerMode.FSTRING_EXPR);
            self.fstring_bracket_depth = 0;  # Reset bracket depth for new expression
            return self.make_token(
                Tok.LBRACE.value, value, start_pos, start_line, start_col
            );
        }

        # Text content
        value = "";

        # Determine text token type
        if mode == LexerMode.FSTRING_DQ {
            text_tok = Tok.F_TEXT_DQ.value;
        } elif mode == LexerMode.FSTRING_SQ {
            text_tok = Tok.F_TEXT_SQ.value;
        } elif mode == LexerMode.FSTRING_TDQ {
            text_tok = Tok.F_TEXT_TDQ.value;
        } else {
            text_tok = Tok.F_TEXT_TSQ.value;
        }

        while not self.at_end() {
            ch = self.char_at();

            # Check for end of f-string
            if is_triple {
                if ch == quote_char
                and self.char_at(1) == quote_char
                and self.char_at(2) == quote_char {
                    break;
                }
            } else {
                if ch == quote_char {
                    break;
                }
                if ch == "\n" {
                    break;
                }
            }

            # Expression or escaped braces
            if ch == "{" {
                if self.char_at(1) == "{" {
                    break;
                }
                break;
            }
            if ch == "}" {
                if self.char_at(1) == "}" {
                    break;
                }
                break;
            }

            # Escape sequence (non-raw)
            if ch == "\\" and not is_raw {
                value += self.advance_char();
                if not self.at_end() {
                    value += self.advance_char();
                }
            } else {
                value += self.advance_char();
            }
        }

        if len(value) > 0 {
            return self.make_token(text_tok, value, start_pos, start_line, start_col);
        }

        # Shouldn't reach here, but handle gracefully
        return self.make_token(text_tok, "", start_pos, start_line, start_col);
    }

    def _scan_fstring_format -> UniToken {
        # Scan format spec content after : in f-string expression.
        # Format specs are text until } or { for nested expressions.
        start_pos = self.pos;
        start_line = self.line;
        start_col = self.col;

        if self.at_end() {
            self.pop_mode();  # Exit format mode
            return self.make_eof_token();
        }

        ch = self.char_at();
        ch1 = self.char_at(1);

        # Closing brace ends format spec and the expression
        if ch == "}" {
            value = self.advance_char();
            self.pop_mode();  # Exit FSTRING_FORMAT mode
            self.pop_mode();  # Exit FSTRING_EXPR mode
            return self.make_token(
                Tok.RBRACE.value, value, start_pos, start_line, start_col
            );
        }

        # Escaped braces {{ and }}
        if ch == "{" and ch1 == "{" {
            value = self.advance_char() + self.advance_char();
            return self.make_token(
                Tok.D_LBRACE.value, value, start_pos, start_line, start_col
            );
        }
        if ch == "}" and ch1 == "}" {
            value = self.advance_char() + self.advance_char();
            return self.make_token(
                Tok.D_RBRACE.value, value, start_pos, start_line, start_col
            );
        }

        # Nested expression start
        if ch == "{" {
            value = self.advance_char();
            self.push_mode(LexerMode.FSTRING_EXPR);
            self.fstring_bracket_depth = 0;  # Reset bracket depth for new expression
            return self.make_token(
                Tok.LBRACE.value, value, start_pos, start_line, start_col
            );
        }

        # Collect format text until we hit { or }
        value = "";
        while not self.at_end() {
            ch = self.char_at();
            ch1 = self.char_at(1);

            # Stop at brace (single or double)
            if ch == "{" or ch == "}" {
                break;
            }

            value += self.advance_char();
        }

        if len(value) > 0 {
            return self.make_token(
                Tok.F_FORMAT_TEXT.value, value, start_pos, start_line, start_col
            );
        }

        # Shouldn't reach here, but handle gracefully
        return self.make_token(
            Tok.F_FORMAT_TEXT.value, "", start_pos, start_line, start_col
        );
    }

    # ── Identifier / keyword scanning ────────────────────────────────────
    def _scan_identifier_or_keyword -> UniToken {
        # Scan an identifier, keyword, or builtin type.
        start_pos = self.pos;
        start_line = self.line;
        start_col = self.col;

        value = "";
        while not self.at_end() {
            ch = self.char_at();
            if ch.isalnum() or ch == "_" {
                value += self.advance_char();
            } else {
                break;
            }
        }

        # Multi-word token: is not
        if value == "is" {
            saved_pos = self.pos;
            saved_line = self.line;
            saved_col = self.col;
            ws = "";
            while not self.at_end() and self.char_at() in " \t" {
                ws += self.advance_char();
            }
            if self.starts_with("not") {
                # Check next char after "not" is not alphanumeric
                check_pos = self.pos + 3;
                if check_pos >= len(self.source)
                or not (
                    self.source[check_pos].isalnum() or self.source[check_pos] == "_"
                ) {
                    # Consume "not"
                    i = 0;
                    while i < 3 {
                        self.advance_char();
                        i += 1;
                    }
                    return self.make_token(
                        Tok.KW_ISN.value,
                        "is" + ws + "not",
                        start_pos,
                        start_line,
                        start_col
                    );
                }
            }
            # Restore
            self.pos = saved_pos;
            self.line = saved_line;
            self.col = saved_col;
        }

        # Multi-word token: not in
        if value == "not" {
            saved_pos = self.pos;
            saved_line = self.line;
            saved_col = self.col;
            ws = "";
            while not self.at_end() and self.char_at() in " \t" {
                ws += self.advance_char();
            }
            if self.starts_with("in") {
                check_pos = self.pos + 2;
                if check_pos >= len(self.source)
                or not (
                    self.source[check_pos].isalnum() or self.source[check_pos] == "_"
                ) {
                    i = 0;
                    while i < 2 {
                        self.advance_char();
                        i += 1;
                    }
                    return self.make_token(
                        Tok.KW_NIN.value,
                        "not" + ws + "in",
                        start_pos,
                        start_line,
                        start_col
                    );
                }
            }
            # Restore
            self.pos = saved_pos;
            self.line = saved_line;
            self.col = saved_col;
        }

        # Check for builtin type
        if value in BUILTIN_TYPE_MAP {
            tok_type = BUILTIN_TYPE_MAP[value];
            return self.make_token(
                tok_type.value, value, start_pos, start_line, start_col
            );
        }

        # Check for keyword
        if value in KEYWORD_MAP {
            tok_type = KEYWORD_MAP[value];
            return self.make_token(
                tok_type.value, value, start_pos, start_line, start_col
            );
        }

        # Logical operators with symbol form: &&, ||
        # These are already handled as operators, but "and" and "or" keywords
        # are handled here via KEYWORD_MAP above.

        # Regular identifier
        return self.make_token(Tok.NAME.value, value, start_pos, start_line, start_col);
    }

    # ── Inline python block ──────────────────────────────────────────────
    def _scan_pynline -> UniToken {
        # Scan ::py:: ... ::py:: inline Python block.
        start_pos = self.pos;
        start_line = self.line;
        start_col = self.col;

        # Consume opening ::py::
        full_value = "";
        i = 0;
        while i < 6 {
            full_value += self.advance_char();
            i += 1;
        }

        # Scan until closing ::py::
        content = "";
        while not self.at_end() {
            if self.starts_with("::py::") {
                # Consume closing ::py::
                j = 0;
                while j < 6 {
                    full_value += self.advance_char();
                    j += 1;
                }
                break;
            }
            ch = self.advance_char();
            content += ch;
            full_value += ch;
        }

        # Value is content between ::py:: markers (stripped)
        return self.make_token(
            Tok.PYNLINE.value, content, start_pos, start_line, start_col
        );
    }

    # ── Operator / punctuation scanning ──────────────────────────────────
    def _scan_operator -> UniToken {
        # Scan operators and punctuation. Uses longest-match.
        start_pos = self.pos;
        start_line = self.line;
        start_col = self.col;

        ch = self.char_at();
        ch1 = self.char_at(1);
        ch2 = self.char_at(2);
        ch3 = self.char_at(3);

        # 4-char operators
        four = ch + ch1 + ch2 + ch3;
        if four == "<-->" {
            self.advance_n(4);
            return self.make_token(
                Tok.ARROW_BI.value, "<-->", start_pos, start_line, start_col
            );
        }
        if four == "<++>" {
            self.advance_n(4);
            return self.make_token(
                Tok.CARROW_BI.value, "<++>", start_pos, start_line, start_col
            );
        }

        # 3-char operators
        three = ch + ch1 + ch2;
        if three == "..." {
            self.advance_n(3);
            return self.make_token(
                Tok.ELLIPSIS.value, "...", start_pos, start_line, start_col
            );
        }
        if three == "**=" {
            self.advance_n(3);
            return self.make_token(
                Tok.STAR_POW_EQ.value, "**=", start_pos, start_line, start_col
            );
        }
        if three == "//=" {
            self.advance_n(3);
            return self.make_token(
                Tok.FLOOR_DIV_EQ.value, "//=", start_pos, start_line, start_col
            );
        }
        if three == "<<=" {
            self.advance_n(3);
            return self.make_token(
                Tok.LSHIFT_EQ.value, "<<=", start_pos, start_line, start_col
            );
        }
        if three == ">>=" {
            self.advance_n(3);
            return self.make_token(
                Tok.RSHIFT_EQ.value, ">>=", start_pos, start_line, start_col
            );
        }
        if three == "-->" {
            self.advance_n(3);
            return self.make_token(
                Tok.ARROW_R.value, "-->", start_pos, start_line, start_col
            );
        }
        if three == "<--" {
            self.advance_n(3);
            return self.make_token(
                Tok.ARROW_L.value, "<--", start_pos, start_line, start_col
            );
        }
        if three == "++>" {
            self.advance_n(3);
            return self.make_token(
                Tok.CARROW_R.value, "++>", start_pos, start_line, start_col
            );
        }
        if three == "<++" {
            self.advance_n(3);
            return self.make_token(
                Tok.CARROW_L.value, "<++", start_pos, start_line, start_col
            );
        }
        if three == "<-:" {
            self.advance_n(3);
            return self.make_token(
                Tok.ARROW_L_P1.value, "<-:", start_pos, start_line, start_col
            );
        }
        if three == ":->" {
            self.advance_n(3);
            return self.make_token(
                Tok.ARROW_R_P2.value, ":->", start_pos, start_line, start_col
            );
        }
        if three == ":<-" {
            self.advance_n(3);
            return self.make_token(
                Tok.ARROW_L_P2.value, ":<-", start_pos, start_line, start_col
            );
        }
        if three == "->:" {
            self.advance_n(3);
            return self.make_token(
                Tok.ARROW_R_P1.value, "->:", start_pos, start_line, start_col
            );
        }
        if three == "<+:" {
            self.advance_n(3);
            return self.make_token(
                Tok.CARROW_L_P1.value, "<+:", start_pos, start_line, start_col
            );
        }
        if three == ":+>" {
            self.advance_n(3);
            return self.make_token(
                Tok.CARROW_R_P2.value, ":+>", start_pos, start_line, start_col
            );
        }
        if three == ":<+" {
            self.advance_n(3);
            return self.make_token(
                Tok.CARROW_L_P2.value, ":<+", start_pos, start_line, start_col
            );
        }
        if three == "+>:" {
            self.advance_n(3);
            return self.make_token(
                Tok.CARROW_R_P1.value, "+>:", start_pos, start_line, start_col
            );
        }
        if three == "<>/" {
            # This is for JSX fragment close, handled elsewhere
            # JSX fragment close handled elsewhere
        }

        # 2-char operators
        two = ch + ch1;
        if two == "**" {
            self.advance_n(2);
            return self.make_token(
                Tok.STAR_POW.value, "**", start_pos, start_line, start_col
            );
        }
        if two == "//" {
            self.advance_n(2);
            return self.make_token(
                Tok.FLOOR_DIV.value, "//", start_pos, start_line, start_col
            );
        }
        if two == "|>" {
            self.advance_n(2);
            return self.make_token(
                Tok.PIPE_FWD.value, "|>", start_pos, start_line, start_col
            );
        }
        if two == "<|" {
            self.advance_n(2);
            return self.make_token(
                Tok.PIPE_BKWD.value, "<|", start_pos, start_line, start_col
            );
        }
        if two == ":>" {
            self.advance_n(2);
            return self.make_token(
                Tok.A_PIPE_FWD.value, ":>", start_pos, start_line, start_col
            );
        }
        if two == "<:" {
            self.advance_n(2);
            return self.make_token(
                Tok.A_PIPE_BKWD.value, "<:", start_pos, start_line, start_col
            );
        }
        if two == ".>" {
            self.advance_n(2);
            return self.make_token(
                Tok.DOT_FWD.value, ".>", start_pos, start_line, start_col
            );
        }
        if two == "<." {
            self.advance_n(2);
            return self.make_token(
                Tok.DOT_BKWD.value, "<.", start_pos, start_line, start_col
            );
        }
        if two == "==" {
            self.advance_n(2);
            return self.make_token(
                Tok.EE.value, "==", start_pos, start_line, start_col
            );
        }
        if two == "!=" {
            self.advance_n(2);
            return self.make_token(
                Tok.NE.value, "!=", start_pos, start_line, start_col
            );
        }
        if two == "<=" {
            self.advance_n(2);
            return self.make_token(
                Tok.LTE.value, "<=", start_pos, start_line, start_col
            );
        }
        if two == ">=" {
            self.advance_n(2);
            return self.make_token(
                Tok.GTE.value, ">=", start_pos, start_line, start_col
            );
        }
        if two == "<<" {
            self.advance_n(2);
            return self.make_token(
                Tok.LSHIFT.value, "<<", start_pos, start_line, start_col
            );
        }
        if two == ">>" {
            self.advance_n(2);
            return self.make_token(
                Tok.RSHIFT.value, ">>", start_pos, start_line, start_col
            );
        }
        if two == "+=" {
            self.advance_n(2);
            return self.make_token(
                Tok.ADD_EQ.value, "+=", start_pos, start_line, start_col
            );
        }
        if two == "-=" {
            self.advance_n(2);
            return self.make_token(
                Tok.SUB_EQ.value, "-=", start_pos, start_line, start_col
            );
        }
        if two == "*=" {
            self.advance_n(2);
            return self.make_token(
                Tok.MUL_EQ.value, "*=", start_pos, start_line, start_col
            );
        }
        if two == "/=" {
            self.advance_n(2);
            return self.make_token(
                Tok.DIV_EQ.value, "/=", start_pos, start_line, start_col
            );
        }
        if two == "%=" {
            self.advance_n(2);
            return self.make_token(
                Tok.MOD_EQ.value, "%=", start_pos, start_line, start_col
            );
        }
        if two == "@=" {
            self.advance_n(2);
            return self.make_token(
                Tok.MATMUL_EQ.value, "@=", start_pos, start_line, start_col
            );
        }
        if two == "&=" {
            self.advance_n(2);
            return self.make_token(
                Tok.BW_AND_EQ.value, "&=", start_pos, start_line, start_col
            );
        }
        if two == "|=" {
            self.advance_n(2);
            return self.make_token(
                Tok.BW_OR_EQ.value, "|=", start_pos, start_line, start_col
            );
        }
        if two == "^=" {
            self.advance_n(2);
            return self.make_token(
                Tok.BW_XOR_EQ.value, "^=", start_pos, start_line, start_col
            );
        }
        if two == "->" {
            self.advance_n(2);
            return self.make_token(
                Tok.RETURN_HINT.value, "->", start_pos, start_line, start_col
            );
        }
        if two == ":=" {
            self.advance_n(2);
            return self.make_token(
                Tok.WALRUS_EQ.value, ":=", start_pos, start_line, start_col
            );
        }
        if two == "&&" {
            self.advance_n(2);
            return self.make_token(
                Tok.KW_AND.value, "&&", start_pos, start_line, start_col
            );
        }
        if two == "||" {
            self.advance_n(2);
            return self.make_token(
                Tok.KW_OR.value, "||", start_pos, start_line, start_col
            );
        }
        if two == "/>" {
            self.advance_n(2);
            return self.make_token(
                Tok.JSX_SELF_CLOSE.value, "/>", start_pos, start_line, start_col
            );
        }
        if two == "</" {
            self.advance_n(2);
            self.in_jsx_close_tag = True;
            self.push_mode(LexerMode.JSX_TAG);
            return self.make_token(
                Tok.JSX_CLOSE_START.value, "</", start_pos, start_line, start_col
            );
        }
        # <> as fragment open
        if two == "<>" {
            self.advance_n(2);
            return self.make_token(
                Tok.JSX_FRAG_OPEN.value, "<>", start_pos, start_line, start_col
            );
        }

        # 1-char operators
        if ch == "+" {
            self.advance_char();
            return self.make_token(
                Tok.PLUS.value, "+", start_pos, start_line, start_col
            );
        }
        if ch == "-" {
            self.advance_char();
            return self.make_token(
                Tok.MINUS.value, "-", start_pos, start_line, start_col
            );
        }
        if ch == "*" {
            self.advance_char();
            return self.make_token(
                Tok.STAR_MUL.value, "*", start_pos, start_line, start_col
            );
        }
        if ch == "/" {
            self.advance_char();
            return self.make_token(
                Tok.DIV.value, "/", start_pos, start_line, start_col
            );
        }
        if ch == "%" {
            self.advance_char();
            return self.make_token(
                Tok.MOD.value, "%", start_pos, start_line, start_col
            );
        }
        if ch == "@" {
            self.advance_char();
            return self.make_token(
                Tok.DECOR_OP.value, "@", start_pos, start_line, start_col
            );
        }
        if ch == "&" {
            self.advance_char();
            return self.make_token(
                Tok.BW_AND.value, "&", start_pos, start_line, start_col
            );
        }
        if ch == "|" {
            self.advance_char();
            return self.make_token(
                Tok.BW_OR.value, "|", start_pos, start_line, start_col
            );
        }
        if ch == "^" {
            self.advance_char();
            return self.make_token(
                Tok.BW_XOR.value, "^", start_pos, start_line, start_col
            );
        }
        if ch == "~" {
            self.advance_char();
            return self.make_token(
                Tok.BW_NOT.value, "~", start_pos, start_line, start_col
            );
        }
        if ch == "<" {
            # Check if this could be JSX: <identifier or <_identifier
            next_ch = self.char_at(1);
            if next_ch.isalpha() or next_ch == "_" {
                # This looks like JSX start: <div, <MyComponent, etc.
                self.advance_char();
                self.push_mode(LexerMode.JSX_TAG);
                return self.make_token(
                    Tok.JSX_OPEN_START.value, "<", start_pos, start_line, start_col
                );
            }
            self.advance_char();
            return self.make_token(Tok.LT.value, "<", start_pos, start_line, start_col);
        }
        if ch == ">" {
            self.advance_char();
            return self.make_token(Tok.GT.value, ">", start_pos, start_line, start_col);
        }
        if ch == "=" {
            self.advance_char();
            return self.make_token(Tok.EQ.value, "=", start_pos, start_line, start_col);
        }
        if ch == "." {
            self.advance_char();
            return self.make_token(
                Tok.DOT.value, ".", start_pos, start_line, start_col
            );
        }
        if ch == "," {
            self.advance_char();
            return self.make_token(
                Tok.COMMA.value, ",", start_pos, start_line, start_col
            );
        }
        if ch == ":" {
            self.advance_char();
            return self.make_token(
                Tok.COLON.value, ":", start_pos, start_line, start_col
            );
        }
        if ch == ";" {
            self.advance_char();
            return self.make_token(
                Tok.SEMI.value, ";", start_pos, start_line, start_col
            );
        }
        if ch == "?" {
            self.advance_char();
            return self.make_token(
                Tok.NULL_OK.value, "?", start_pos, start_line, start_col
            );
        }
        if ch == "`" {
            self.advance_char();
            return self.make_token(
                Tok.TYPE_OP.value, "`", start_pos, start_line, start_col
            );
        }
        if ch == "(" {
            self.advance_char();
            return self.make_token(
                Tok.LPAREN.value, "(", start_pos, start_line, start_col
            );
        }
        if ch == ")" {
            self.advance_char();
            return self.make_token(
                Tok.RPAREN.value, ")", start_pos, start_line, start_col
            );
        }
        if ch == "[" {
            self.advance_char();
            return self.make_token(
                Tok.LSQUARE.value, "[", start_pos, start_line, start_col
            );
        }
        if ch == "]" {
            self.advance_char();
            return self.make_token(
                Tok.RSQUARE.value, "]", start_pos, start_line, start_col
            );
        }
        if ch == "{" {
            self.advance_char();
            return self.make_token(
                Tok.LBRACE.value, "{", start_pos, start_line, start_col
            );
        }
        if ch == "}" {
            self.advance_char();
            return self.make_token(
                Tok.RBRACE.value, "}", start_pos, start_line, start_col
            );
        }

        # Unknown character - advance and return as error token
        value = self.advance_char();
        return self.make_token("ERROR", value, start_pos, start_line, start_col);
    }

    # ── JSX scanning ─────────────────────────────────────────────────────
    def _scan_jsx_tag_token -> UniToken {
        # Scan a token inside a JSX tag: <Tag attr="val" ...>.
        self.skip_whitespace_and_comments();
        if self.at_end() {
            return self.make_eof_token();
        }

        start_pos = self.pos;
        start_line = self.line;
        start_col = self.col;
        ch = self.char_at();

        # End of tag
        if ch == ">" {
            self.advance_char();
            self.pop_mode();  # Exit JSX_TAG
            # Only push JSX_CONTENT for opening tags, not closing tags
            if not self.in_jsx_close_tag {
                self.push_mode(LexerMode.JSX_CONTENT);
            }
            self.in_jsx_close_tag = False;  # Reset for next tag
            return self.make_token(
                Tok.JSX_TAG_END.value, ">", start_pos, start_line, start_col
            );
        }

        # Self-closing
        if ch == "/" and self.char_at(1) == ">" {
            self.advance_n(2);
            self.pop_mode();  # Exit JSX_TAG
            return self.make_token(
                Tok.JSX_SELF_CLOSE.value, "/>", start_pos, start_line, start_col
            );
        }

        # Attribute expression: {expr}
        if ch == "{" {
            self.advance_char();
            return self.make_token(
                Tok.LBRACE.value, "{", start_pos, start_line, start_col
            );
        }

        # Dot for element name chaining
        if ch == "." {
            self.advance_char();
            return self.make_token(
                Tok.DOT.value, ".", start_pos, start_line, start_col
            );
        }

        # Equals for attribute assignment
        if ch == "=" {
            self.advance_char();
            return self.make_token(Tok.EQ.value, "=", start_pos, start_line, start_col);
        }

        # Ellipsis
        if ch == "." and self.char_at(1) == "." and self.char_at(2) == "." {
            self.advance_n(3);
            return self.make_token(
                Tok.ELLIPSIS.value, "...", start_pos, start_line, start_col
            );
        }

        # String attribute value
        if ch in "\"'" {
            return self._scan_string();
        }

        # JSX_NAME: [A-Za-z_][A-Za-z0-9_-]*
        if ch.isalpha() or ch == "_" {
            value = "";
            while not self.at_end() {
                c = self.char_at();
                if c.isalnum() or c in "_-" {
                    value += self.advance_char();
                } else {
                    break;
                }
            }
            return self.make_token(
                Tok.JSX_NAME.value, value, start_pos, start_line, start_col
            );
        }

        # Fallback
        return self._scan_operator();
    }

    def _scan_jsx_content_token -> UniToken {
        # Scan content between JSX tags.
        if self.at_end() {
            return self.make_eof_token();
        }

        start_pos = self.pos;
        start_line = self.line;
        start_col = self.col;
        ch = self.char_at();

        # Expression: {expr}
        if ch == "{" {
            self.advance_char();
            return self.make_token(
                Tok.LBRACE.value, "{", start_pos, start_line, start_col
            );
        }

        # Closing tag: </
        if ch == "<" and self.char_at(1) == "/" {
            # Check for fragment close: </>
            if self.char_at(2) == ">" {
                self.advance_n(3);
                self.pop_mode();  # Exit JSX_CONTENT
                return self.make_token(
                    Tok.JSX_FRAG_CLOSE.value, "</>", start_pos, start_line, start_col
                );
            }
            self.advance_n(2);
            self.pop_mode();  # Exit JSX_CONTENT
            self.in_jsx_close_tag = True;
            self.push_mode(LexerMode.JSX_TAG);
            return self.make_token(
                Tok.JSX_CLOSE_START.value, "</", start_pos, start_line, start_col
            );
        }

        # Nested JSX element: <
        if ch == "<" {
            next_ch = self.char_at(1);
            if next_ch.isalpha() or next_ch == "_" {
                self.advance_char();
                self.push_mode(LexerMode.JSX_TAG);
                return self.make_token(
                    Tok.JSX_OPEN_START.value, "<", start_pos, start_line, start_col
                );
            }
            # Fragment: <>
            if next_ch == ">" {
                self.advance_n(2);
                self.push_mode(LexerMode.JSX_CONTENT);
                return self.make_token(
                    Tok.JSX_FRAG_OPEN.value, "<>", start_pos, start_line, start_col
                );
            }
        }

        # JSX text content
        value = "";
        while not self.at_end() {
            c = self.char_at();
            if c in "<{}" {
                break;
            }
            if c == "\n" {
                break;
            }
            value += self.advance_char();
        }

        if len(value) > 0 {
            return self.make_token(
                Tok.JSX_TEXT.value, value, start_pos, start_line, start_col
            );
        }

        # Newlines as text
        if not self.at_end() and self.char_at() == "\n" {
            value = self.advance_char();
            return self.make_token(
                Tok.JSX_TEXT.value, value, start_pos, start_line, start_col
            );
        }

        return self.make_eof_token();
    }

    # ── Main token dispatch ──────────────────────────────────────────────
    def _scan_token -> UniToken {
        # Raw scan: always reads the next token from source (ignores peeked buffer).
        mode = self.current_mode();

        # F-string body modes
        if mode in [
            LexerMode.FSTRING_DQ,
            LexerMode.FSTRING_SQ,
            LexerMode.FSTRING_TDQ,
            LexerMode.FSTRING_TSQ
        ] {
            if self.at_end() {
                return self.make_eof_token();
            }
            return self._scan_fstring_body();
        }

        # JSX modes
        if mode == LexerMode.JSX_TAG {
            return self._scan_jsx_tag_token();
        }
        if mode == LexerMode.JSX_CONTENT {
            return self._scan_jsx_content_token();
        }

        # FSTRING_FORMAT mode: emit F_FORMAT_TEXT tokens until } or {
        if mode == LexerMode.FSTRING_FORMAT {
            return self._scan_fstring_format();
        }

        # FSTRING_EXPR mode: lex as normal but track brace depth
        # (handled below in NORMAL + FSTRING_EXPR)

        # Normal mode (and FSTRING_EXPR mode)
        self.skip_whitespace_and_comments();

        if self.at_end() {
            return self.make_eof_token();
        }

        ch = self.char_at();
        ch1 = self.char_at(1);

        # In FSTRING_EXPR, closing brace at depth 0 exits the mode
        if mode == LexerMode.FSTRING_EXPR and ch == "}" {
            start_pos = self.pos;
            start_line = self.line;
            start_col = self.col;
            self.advance_char();
            self.pop_mode();
            return self.make_token(
                Tok.RBRACE.value, "}", start_pos, start_line, start_col
            );
        }

        # In FSTRING_EXPR, colon starts format spec mode ONLY if not inside brackets
        if mode == LexerMode.FSTRING_EXPR
        and ch == ":"
        and self.fstring_bracket_depth == 0 {
            start_pos = self.pos;
            start_line = self.line;
            start_col = self.col;
            self.advance_char();
            self.push_mode(LexerMode.FSTRING_FORMAT);
            return self.make_token(
                Tok.COLON.value, ":", start_pos, start_line, start_col
            );
        }

        # Track bracket depth in FSTRING_EXPR mode for slice support
        if mode == LexerMode.FSTRING_EXPR and ch == "[" {
            self.fstring_bracket_depth += 1;
        }
        if mode == LexerMode.FSTRING_EXPR and ch == "]" {
            if self.fstring_bracket_depth > 0 {
                self.fstring_bracket_depth -= 1;
            }
        }

        # ::py:: blocks
        if self.starts_with("::py::") {
            return self._scan_pynline();
        }

        # Keyword-escaped name: <>identifier
        if ch == "<" and ch1 == ">" {
            start_pos = self.pos;
            start_line = self.line;
            start_col = self.col;
            prefix = self.advance_char() + self.advance_char();  # consume <>
            value = prefix;
            while not self.at_end()
            and (self.char_at().isalnum() or self.char_at() == "_") {
                value += self.advance_char();
            }
            return self.make_token(
                Tok.KWESC_NAME.value, value, start_pos, start_line, start_col
            );
        }

        # F-string or raw-f-string start
        if (ch in "fF" and ch1 in "\"'")
        or (ch in "rR" and ch1 in "fF" and self.char_at(2) in "\"'")
        or (ch in "fF" and ch1 in "rR" and self.char_at(2) in "\"'") {
            start_pos = self.pos;
            start_line = self.line;
            start_col = self.col;
            prefix = "";
            if ch in "fF" and ch1 in "\"'" {
                prefix = self.advance_char();  # f
            } elif ch in "rR" and ch1 in "fF" {
                prefix = self.advance_char() + self.advance_char();  # rf
            } else {
                prefix = self.advance_char() + self.advance_char();  # fr
            }
            return self._scan_fstring_start(prefix);
        }

        # Raw or byte strings: r"...", b"...", rb"...", br"..."
        if ch in "rRbB" {
            # Check for various string prefixes
            if ch in "rR" and ch1 in "\"'" {
                prefix = self.advance_char();
                return self._scan_string(prefix);
            }
            if ch in "bB" and ch1 in "\"'" {
                prefix = self.advance_char();
                return self._scan_string(prefix);
            }
            if ch in "rR" and ch1 in "bB" and self.char_at(2) in "\"'" {
                prefix = self.advance_char() + self.advance_char();
                return self._scan_string(prefix);
            }
            if ch in "bB" and ch1 in "rR" and self.char_at(2) in "\"'" {
                prefix = self.advance_char() + self.advance_char();
                return self._scan_string(prefix);
            }
        }

        # Regular strings
        if ch in "\"'" {
            return self._scan_string();
        }

        # Numbers
        if ch.isdigit() {
            return self._scan_number();
        }
        # Numbers starting with dot: .5, .5e3
        if ch == "." and ch1.isdigit() {
            return self._scan_dot_number();
        }

        # Identifiers and keywords
        if ch.isalpha() or ch == "_" {
            return self._scan_identifier_or_keyword();
        }

        # Operators and punctuation
        return self._scan_operator();
    }

    def next_token -> UniToken {
        # Get the next token. Returns from peeked buffer first, then scans source.
        if len(self.peeked) > 0 {
            return self.peeked.pop(0);
        }
        return self._scan_token();
    }

    def peek(offset: int = 0) -> UniToken {
        # Peek at the next token without consuming it. Supports lookahead.
        # Always scans directly from source to fill the buffer (never via next_token,
        # which would consume from the same buffer and cause an infinite loop).
        while len(self.peeked) <= offset {
            self.peeked.append(self._scan_token());
        }
        return self.peeked[offset];
    }

    def push_back(token: UniToken) {
        # Push a token back to be read again.
        self.peeked.insert(0, token);
    }

    # ── JSX context helpers (called by parser) ───────────────────────────
    def enter_jsx_tag_mode {
        # Enter JSX tag mode (called by parser when < is detected as JSX).
        self.push_mode(LexerMode.JSX_TAG);
    }

    def exit_jsx_mode {
        # Exit current JSX mode.
        if self.current_mode() in [LexerMode.JSX_TAG, LexerMode.JSX_CONTENT] {
            self.pop_mode();
        }
    }
}
# Sentinel for EOF
