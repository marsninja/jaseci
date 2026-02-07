"""Bootstrap lexer for the Jac bootstrap compiler (Layer 1).

Tokenizes the expanded Jac subset that the bootstrap compiler understands.
Handles more features than the seed lexer: decorators, *args, **kwargs,
triple-quoted strings, walrus operator, etc.

Written using ONLY the Layer 0 subset so the seed compiler can compile it.
""";

import from jaclang.bootstrap.bootstrap_ast { BootstrapToken }

# =============================================================================
# Keyword Table
# =============================================================================

glob KEYWORDS: dict[str, str] = {
    "obj": "KW_OBJ",
    "node": "KW_NODE",
    "edge": "KW_EDGE",
    "walker": "KW_WALKER",
    "enum": "KW_ENUM",
    "impl": "KW_IMPL",
    "can": "KW_CAN",
    "has": "KW_HAS",
    "glob": "KW_GLOB",
    "import": "KW_IMPORT",
    "from": "KW_FROM",
    "as": "KW_AS",
    "if": "KW_IF",
    "elif": "KW_ELIF",
    "else": "KW_ELSE",
    "while": "KW_WHILE",
    "for": "KW_FOR",
    "in": "KW_IN",
    "return": "KW_RETURN",
    "break": "KW_BREAK",
    "continue": "KW_CONTINUE",
    "and": "KW_AND",
    "or": "KW_OR",
    "not": "KW_NOT",
    "is": "KW_IS",
    "True": "KW_TRUE",
    "False": "KW_FALSE",
    "None": "KW_NONE",
    "def": "KW_DEF",
    "self": "KW_SELF",
    "try": "KW_TRY",
    "except": "KW_EXCEPT",
    "finally": "KW_FINALLY",
    "raise": "KW_RAISE",
    "with": "KW_WITH",
    "assert": "KW_ASSERT",
    "del": "KW_DEL",
    "pass": "KW_PASS",
    "class": "KW_CLASS",
    "yield": "KW_YIELD",
    "lambda": "KW_LAMBDA",
    "match": "KW_MATCH",
    "case": "KW_CASE",
    "async": "KW_ASYNC",
    "await": "KW_AWAIT",
    "spawn": "KW_SPAWN",
    "visit": "KW_VISIT",
    "abstract": "KW_ABSTRACT",
    "override": "KW_OVERRIDE"
};

# =============================================================================
# Lexer
# =============================================================================

obj BootstrapLexer {
    has source: str = "",
        filename: str = "<bootstrap>",
        pos: int = 0,
        line: int = 1,
        col: int = 1,
        tokens: list[BootstrapToken] = [];

    # -------------------------------------------------------------------------
    # Character Helpers
    # -------------------------------------------------------------------------

    def peek(offset: int) -> str {
        p = self.pos + offset;
        if p < len(self.source) {
            return self.source[p];
        }
        return "";
    }

    def current_char() -> str {
        if self.pos < len(self.source) {
            return self.source[self.pos];
        }
        return "";
    }

    def advance_char() -> str {
        ch = self.source[self.pos];
        self.pos = self.pos + 1;
        if ch == "\n" {
            self.line = self.line + 1;
            self.col = 1;
        } else {
            self.col = self.col + 1;
        }
        return ch;
    }

    def make_token(kind: str, value: str, line: int, col: int) -> BootstrapToken {
        return BootstrapToken(kind=kind, value=value, line=line, col=col);
    }

    def is_alpha(ch: str) -> bool {
        return ch >= "a" and ch <= "z" or ch >= "A" and ch <= "Z" or ch == "_";
    }

    def is_digit(ch: str) -> bool {
        return ch >= "0" and ch <= "9";
    }

    def join_chars(chars: list[str]) -> str {
        result = "";
        for ch in chars {
            result = result + ch;
        }
        return result;
    }

    # -------------------------------------------------------------------------
    # Whitespace and Comments
    # -------------------------------------------------------------------------

    def skip_whitespace() -> None {
        while self.pos < len(self.source) {
            ch = self.source[self.pos];
            if ch == " " or ch == "\t" or ch == "\r" or ch == "\n" {
                self.advance_char();
            } elif ch == "#" {
                while self.pos < len(self.source) and self.source[self.pos] != "\n" {
                    self.advance_char();
                }
            } elif ch == "/" and self.peek(1) == "*" {
                self.advance_char();
                self.advance_char();
                while self.pos < len(self.source) {
                    if self.source[self.pos] == "*" and self.peek(1) == "/" {
                        self.advance_char();
                        self.advance_char();
                        break;
                    }
                    self.advance_char();
                }
            } else {
                break;
            }
        }
    }

    # -------------------------------------------------------------------------
    # String Handling
    # -------------------------------------------------------------------------

    def read_string(quote: str) -> BootstrapToken {
        start_line = self.line;
        start_col = self.col;
        triple = False;
        if self.peek(1) == quote and self.peek(2) == quote {
            triple = True;
            self.advance_char();
            self.advance_char();
            self.advance_char();
        } else {
            self.advance_char();
        }
        chars: list[str] = [];
        while self.pos < len(self.source) {
            if triple {
                if self.source[self.pos] == quote and self.peek(1) == quote and self.peek(2) == quote {
                    self.advance_char();
                    self.advance_char();
                    self.advance_char();
                    q3 = quote + quote + quote;
                    val = q3 + self.join_chars(chars) + q3;
                    return self.make_token("STRING", val, start_line, start_col);
                }
            } else {
                if self.source[self.pos] == quote {
                    self.advance_char();
                    val = quote + self.join_chars(chars) + quote;
                    return self.make_token("STRING", val, start_line, start_col);
                }
                if self.source[self.pos] == "\n" {
                    return self.make_token("ERROR", "Unterminated string", start_line, start_col);
                }
            }
            if self.source[self.pos] == "\\" {
                chars.append(self.advance_char());
                if self.pos < len(self.source) {
                    chars.append(self.advance_char());
                }
            } else {
                chars.append(self.advance_char());
            }
        }
        return self.make_token("ERROR", "Unterminated string", start_line, start_col);
    }

    def read_fstring(quote: str) -> BootstrapToken {
        start_line = self.line;
        start_col = self.col;
        self.advance_char();
        self.advance_char();
        chars: list[str] = [];
        chars.append("f");
        chars.append(quote);
        depth = 0;
        while self.pos < len(self.source) {
            ch = self.source[self.pos];
            if ch == "{" and self.peek(1) == "{" {
                chars.append(self.advance_char());
                chars.append(self.advance_char());
            } elif ch == "}" and self.peek(1) == "}" {
                chars.append(self.advance_char());
                chars.append(self.advance_char());
            } elif ch == "{" {
                depth = depth + 1;
                chars.append(self.advance_char());
            } elif ch == "}" {
                depth = depth - 1;
                chars.append(self.advance_char());
            } elif ch == quote and depth == 0 {
                chars.append(self.advance_char());
                return self.make_token("FSTRING", self.join_chars(chars), start_line, start_col);
            } elif ch == "\\" {
                chars.append(self.advance_char());
                if self.pos < len(self.source) {
                    chars.append(self.advance_char());
                }
            } elif ch == "\n" {
                return self.make_token("ERROR", "Unterminated f-string", start_line, start_col);
            } else {
                chars.append(self.advance_char());
            }
        }
        return self.make_token("ERROR", "Unterminated f-string", start_line, start_col);
    }

    # -------------------------------------------------------------------------
    # Number Handling
    # -------------------------------------------------------------------------

    def read_number() -> BootstrapToken {
        start_line = self.line;
        start_col = self.col;
        chars: list[str] = [];
        is_float = False;
        while self.pos < len(self.source) {
            ch = self.source[self.pos];
            if ch >= "0" and ch <= "9" or ch == "_" {
                chars.append(self.advance_char());
            } else {
                break;
            }
        }
        if self.pos < len(self.source) and self.source[self.pos] == "." {
            nxt = self.peek(1);
            if nxt >= "0" and nxt <= "9" {
                is_float = True;
                chars.append(self.advance_char());
                while self.pos < len(self.source) {
                    ch = self.source[self.pos];
                    if ch >= "0" and ch <= "9" or ch == "_" {
                        chars.append(self.advance_char());
                    } else {
                        break;
                    }
                }
            }
        }
        val = self.join_chars(chars);
        if is_float {
            return self.make_token("FLOAT", val, start_line, start_col);
        }
        return self.make_token("INT", val, start_line, start_col);
    }

    # -------------------------------------------------------------------------
    # Identifier Handling
    # -------------------------------------------------------------------------

    def read_name() -> BootstrapToken {
        start_line = self.line;
        start_col = self.col;
        chars: list[str] = [];
        while self.pos < len(self.source) {
            ch = self.source[self.pos];
            if ch >= "a" and ch <= "z" or ch >= "A" and ch <= "Z" or ch >= "0" and ch <= "9" or ch == "_" {
                chars.append(self.advance_char());
            } else {
                break;
            }
        }
        val = self.join_chars(chars);
        if val in KEYWORDS {
            return self.make_token(KEYWORDS[val], val, start_line, start_col);
        }
        return self.make_token("NAME", val, start_line, start_col);
    }

    # -------------------------------------------------------------------------
    # Main Tokenize Loop
    # -------------------------------------------------------------------------

    def tokenize() -> list[BootstrapToken] {
        self.tokens = [];
        while True {
            self.skip_whitespace();
            if self.pos >= len(self.source) {
                self.tokens.append(self.make_token("EOF", "", self.line, self.col));
                break;
            }
            ch = self.source[self.pos];
            start_line = self.line;
            start_col = self.col;

            # F-strings
            if ch == "f" and self.pos + 1 < len(self.source) {
                nxt = self.source[self.pos + 1];
                if nxt == "\"" or nxt == "'" {
                    self.tokens.append(self.read_fstring(nxt));
                    continue;
                }
            }

            # Strings
            if ch == "\"" or ch == "'" {
                self.tokens.append(self.read_string(ch));
                continue;
            }

            # Numbers
            if self.is_digit(ch) {
                self.tokens.append(self.read_number());
                continue;
            }

            # Names / keywords
            if self.is_alpha(ch) {
                self.tokens.append(self.read_name());
                continue;
            }

            # Two-char operators
            two = "";
            if self.pos + 1 < len(self.source) {
                two = ch + self.source[self.pos + 1];
            }
            if two == "==" {
                self.advance_char();
                self.advance_char();
                self.tokens.append(self.make_token("EQEQ", two, start_line, start_col));
                continue;
            }
            if two == "!=" {
                self.advance_char();
                self.advance_char();
                self.tokens.append(self.make_token("NEQ", two, start_line, start_col));
                continue;
            }
            if two == "<=" {
                self.advance_char();
                self.advance_char();
                self.tokens.append(self.make_token("LTE", two, start_line, start_col));
                continue;
            }
            if two == ">=" {
                self.advance_char();
                self.advance_char();
                self.tokens.append(self.make_token("GTE", two, start_line, start_col));
                continue;
            }
            if two == "+=" {
                self.advance_char();
                self.advance_char();
                self.tokens.append(self.make_token("PLUS_EQ", two, start_line, start_col));
                continue;
            }
            if two == "-=" {
                self.advance_char();
                self.advance_char();
                self.tokens.append(self.make_token("MINUS_EQ", two, start_line, start_col));
                continue;
            }
            if two == "*=" {
                self.advance_char();
                self.advance_char();
                self.tokens.append(self.make_token("STAR_EQ", two, start_line, start_col));
                continue;
            }
            if two == "/=" {
                self.advance_char();
                self.advance_char();
                self.tokens.append(self.make_token("SLASH_EQ", two, start_line, start_col));
                continue;
            }
            if two == "//" {
                self.advance_char();
                self.advance_char();
                self.tokens.append(self.make_token("DSLASH", two, start_line, start_col));
                continue;
            }
            if two == "->" {
                self.advance_char();
                self.advance_char();
                self.tokens.append(self.make_token("ARROW", two, start_line, start_col));
                continue;
            }
            if two == "**" {
                self.advance_char();
                self.advance_char();
                self.tokens.append(self.make_token("DSTAR", two, start_line, start_col));
                continue;
            }
            if two == ":=" {
                self.advance_char();
                self.advance_char();
                self.tokens.append(self.make_token("WALRUS", two, start_line, start_col));
                continue;
            }

            # Single-char operators
            if ch == "(" {
                self.advance_char();
                self.tokens.append(self.make_token("LPAREN", ch, start_line, start_col));
                continue;
            }
            if ch == ")" {
                self.advance_char();
                self.tokens.append(self.make_token("RPAREN", ch, start_line, start_col));
                continue;
            }
            if ch == "[" {
                self.advance_char();
                self.tokens.append(self.make_token("LBRACKET", ch, start_line, start_col));
                continue;
            }
            if ch == "]" {
                self.advance_char();
                self.tokens.append(self.make_token("RBRACKET", ch, start_line, start_col));
                continue;
            }
            if ch == "{" {
                self.advance_char();
                self.tokens.append(self.make_token("LBRACE", ch, start_line, start_col));
                continue;
            }
            if ch == "}" {
                self.advance_char();
                self.tokens.append(self.make_token("RBRACE", ch, start_line, start_col));
                continue;
            }
            if ch == "," {
                self.advance_char();
                self.tokens.append(self.make_token("COMMA", ch, start_line, start_col));
                continue;
            }
            if ch == ":" {
                self.advance_char();
                self.tokens.append(self.make_token("COLON", ch, start_line, start_col));
                continue;
            }
            if ch == ";" {
                self.advance_char();
                self.tokens.append(self.make_token("SEMI", ch, start_line, start_col));
                continue;
            }
            if ch == "." {
                self.advance_char();
                self.tokens.append(self.make_token("DOT", ch, start_line, start_col));
                continue;
            }
            if ch == "=" {
                self.advance_char();
                self.tokens.append(self.make_token("EQ", ch, start_line, start_col));
                continue;
            }
            if ch == "+" {
                self.advance_char();
                self.tokens.append(self.make_token("PLUS", ch, start_line, start_col));
                continue;
            }
            if ch == "-" {
                self.advance_char();
                self.tokens.append(self.make_token("MINUS", ch, start_line, start_col));
                continue;
            }
            if ch == "*" {
                self.advance_char();
                self.tokens.append(self.make_token("STAR", ch, start_line, start_col));
                continue;
            }
            if ch == "/" {
                self.advance_char();
                self.tokens.append(self.make_token("SLASH", ch, start_line, start_col));
                continue;
            }
            if ch == "%" {
                self.advance_char();
                self.tokens.append(self.make_token("PERCENT", ch, start_line, start_col));
                continue;
            }
            if ch == "<" {
                self.advance_char();
                self.tokens.append(self.make_token("LT", ch, start_line, start_col));
                continue;
            }
            if ch == ">" {
                self.advance_char();
                self.tokens.append(self.make_token("GT", ch, start_line, start_col));
                continue;
            }
            if ch == "|" {
                self.advance_char();
                self.tokens.append(self.make_token("PIPE", ch, start_line, start_col));
                continue;
            }
            if ch == "@" {
                self.advance_char();
                self.tokens.append(self.make_token("AT", ch, start_line, start_col));
                continue;
            }
            if ch == "~" {
                self.advance_char();
                self.tokens.append(self.make_token("TILDE", ch, start_line, start_col));
                continue;
            }
            if ch == "&" {
                self.advance_char();
                self.tokens.append(self.make_token("AMP", ch, start_line, start_col));
                continue;
            }
            if ch == "^" {
                self.advance_char();
                self.tokens.append(self.make_token("CARET", ch, start_line, start_col));
                continue;
            }

            # Unknown character
            self.advance_char();
            self.tokens.append(self.make_token("ERROR", ch, start_line, start_col));
        }
        return self.tokens;
    }
}
