"""Bootstrap lexer and parser for the Jac language.

This module provides a minimal, dependency-free lexer (and eventually parser)
for bootstrapping the Jac compiler. The lexer tokenizes Jac source code into
a stream of BootstrapToken objects using the same token type names as the
Tokens enum in jaclang.pycore.constant.

The lexer handles:
- All Jac keywords, operators, and delimiters
- Integer, float, hex, binary, and octal literals
- Single-quoted, double-quoted, and triple-quoted strings (with raw/bytes prefixes)
- F-strings with nested expression interpolation and brace depth tracking
- Line comments (#) and block comments (#* ... *#)
- Combined "not in" (KW_NIN) and "is not" (KW_ISN) tokens
- Keyword-escaped names (<>name)
- Inline Python blocks (::py:: ... ::py::)
"""

from __future__ import annotations

import jaclang.pycore.unitree as uni  # noqa: F401 - will be used by parser portion
from jaclang.pycore.constant import Tokens as Tok
from dataclasses import dataclass


# ---------------------------------------------------------------------------
# Token dataclass
# ---------------------------------------------------------------------------


@dataclass
class BootstrapToken:
    """A single token produced by the bootstrap lexer.

    Fields mirror the information needed to construct AST nodes with
    accurate source location tracking.
    """

    type: str  # e.g. Tok.NAME.value == "NAME"
    value: str  # The raw source text of the token
    line: int  # 1-based starting line number
    end_line: int  # 1-based ending line number
    col_start: int  # 1-based starting column
    col_end: int  # 1-based ending column (exclusive)
    pos_start: int  # 0-based byte offset into source (start)
    pos_end: int  # 0-based byte offset into source (end, exclusive)


# ---------------------------------------------------------------------------
# Keyword map: string literal -> Tok enum member
# ---------------------------------------------------------------------------

KEYWORD_MAP: dict[str, Tok] = {
    # Import / module
    "import": Tok.KW_IMPORT,
    "from": Tok.KW_FROM,
    "as": Tok.KW_AS,
    "include": Tok.KW_INCLUDE,
    # Archetype declarations
    "obj": Tok.KW_OBJECT,
    "class": Tok.KW_CLASS,
    "enum": Tok.KW_ENUM,
    "node": Tok.KW_NODE,
    "edge": Tok.KW_EDGE,
    "walker": Tok.KW_WALKER,
    # Member / ability declarations
    "has": Tok.KW_HAS,
    "can": Tok.KW_CAN,
    "def": Tok.KW_DEF,
    "static": Tok.KW_STATIC,
    "override": Tok.KW_OVERRIDE,
    "impl": Tok.KW_IMPL,
    "sem": Tok.KW_SEM,
    "test": Tok.KW_TEST,
    # Scope
    "glob": Tok.KW_GLOBAL,
    "global": Tok.GLOBAL_OP,
    "nonlocal": Tok.NONLOCAL_OP,
    # Modifiers
    "abs": Tok.KW_ABSTRACT,
    # Control flow
    "if": Tok.KW_IF,
    "elif": Tok.KW_ELIF,
    "else": Tok.KW_ELSE,
    "for": Tok.KW_FOR,
    "to": Tok.KW_TO,
    "by": Tok.KW_BY,
    "while": Tok.KW_WHILE,
    "match": Tok.KW_MATCH,
    "switch": Tok.KW_SWITCH,
    "case": Tok.KW_CASE,
    "default": Tok.KW_DEFAULT,
    "try": Tok.KW_TRY,
    "except": Tok.KW_EXCEPT,
    "finally": Tok.KW_FINALLY,
    "with": Tok.KW_WITH,
    "return": Tok.KW_RETURN,
    "yield": Tok.KW_YIELD,
    "break": Tok.KW_BREAK,
    "continue": Tok.KW_CONTINUE,
    "raise": Tok.KW_RAISE,
    "del": Tok.KW_DELETE,
    "assert": Tok.KW_ASSERT,
    "skip": Tok.KW_SKIP,
    "report": Tok.KW_REPORT,
    # Graph / walker control
    "visit": Tok.KW_VISIT,
    "spawn": Tok.KW_SPAWN,
    "entry": Tok.KW_ENTRY,
    "exit": Tok.KW_EXIT,
    "disengage": Tok.KW_DISENGAGE,
    "here": Tok.KW_HERE,
    "visitor": Tok.KW_VISITOR,
    "root": Tok.KW_ROOT,
    # Async
    "async": Tok.KW_ASYNC,
    "await": Tok.KW_AWAIT,
    "flow": Tok.KW_FLOW,
    "wait": Tok.KW_WAIT,
    # Boolean / logical operators (keyword form)
    "and": Tok.KW_AND,
    "or": Tok.KW_OR,
    "not": Tok.NOT,
    "in": Tok.KW_IN,
    "is": Tok.KW_IS,
    "lambda": Tok.KW_LAMBDA,
    # Access modifiers
    "pub": Tok.KW_PUB,
    "priv": Tok.KW_PRIV,
    "protect": Tok.KW_PROT,
    # Context modifiers
    "cl": Tok.KW_CLIENT,
    "sv": Tok.KW_SERVER,
    "na": Tok.KW_NATIVE,
    # Special references
    "self": Tok.KW_SELF,
    "props": Tok.KW_PROPS,
    "init": Tok.KW_INIT,
    "super": Tok.KW_SUPER,
    "postinit": Tok.KW_POST_INIT,
    # Literal keywords
    "True": Tok.BOOL,
    "False": Tok.BOOL,
    "None": Tok.NULL,
    # Built-in type keywords
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
    "type": Tok.TYP_TYPE,
}


# ---------------------------------------------------------------------------
# F-string mode constants
# ---------------------------------------------------------------------------

_MODE_NORMAL = "normal"
_MODE_FSTRING_DQ = "fstring_dq"
_MODE_FSTRING_SQ = "fstring_sq"
_MODE_FSTRING_TDQ = "fstring_tdq"
_MODE_FSTRING_TSQ = "fstring_tsq"
_MODE_FSTRING_EXPR = "fstring_expr"

# Mapping from fstring mode -> (close_quote, is_triple, is_raw, start_tok, end_tok, text_tok)
_FSTRING_MODE_INFO: dict[str, tuple[str, bool, bool, str, str, str]] = {
    _MODE_FSTRING_DQ: ('"', False, False, Tok.F_DQ_START.value, Tok.F_DQ_END.value, Tok.F_TEXT_DQ.value),
    _MODE_FSTRING_SQ: ("'", False, False, Tok.F_SQ_START.value, Tok.F_SQ_END.value, Tok.F_TEXT_SQ.value),
    _MODE_FSTRING_TDQ: ('"', True, False, Tok.F_TDQ_START.value, Tok.F_TDQ_END.value, Tok.F_TEXT_TDQ.value),
    _MODE_FSTRING_TSQ: ("'", True, False, Tok.F_TSQ_START.value, Tok.F_TSQ_END.value, Tok.F_TEXT_TSQ.value),
}

# Raw f-string modes reuse the same mode names but with different start/text tokens.
# We handle the "raw" distinction via a separate set tracked at push time.

# Mapping: (quote_char, is_triple, has_raw_prefix) -> mode name
_FSTRING_QUOTE_TO_MODE: dict[tuple[str, bool], str] = {
    ('"', False): _MODE_FSTRING_DQ,
    ("'", False): _MODE_FSTRING_SQ,
    ('"', True): _MODE_FSTRING_TDQ,
    ("'", True): _MODE_FSTRING_TSQ,
}


# ---------------------------------------------------------------------------
# BootstrapLexer
# ---------------------------------------------------------------------------


class BootstrapLexer:
    """Hand-written lexer for Jac source code.

    Produces a list of BootstrapToken objects compatible with the Tokens enum.
    Handles all Jac lexical constructs including f-strings with nested
    expression interpolation, block comments, and combined keyword tokens.
    """

    def __init__(self, source: str, file_path: str = "<string>") -> None:
        self.source: str = source
        self.pos: int = 0
        self.line: int = 1
        self.col: int = 1
        self.file_path: str = file_path
        self.tokens: list[BootstrapToken] = []

        # F-string mode tracking.
        # The stack holds mode strings: "normal", "fstring_dq", etc.
        # When we enter an f-string expression ({...}), we push "fstring_expr".
        self.mode_stack: list[str] = [_MODE_NORMAL]

        # Brace depth tracking for f-string expressions.
        # fstring_brace_depth counts open braces inside the current expression.
        # When it drops to 0 we close the expression and return to the fstring
        # text mode. The stack saves/restores depth for nested f-strings.
        self.fstring_brace_depth: int = 0
        self.fstring_brace_depth_stack: list[int] = []

        # Track which fstring modes are "raw" (rf"..." or fr"...").
        # This is a stack of booleans parallel to mode_stack entries that are
        # fstring text modes.
        self.fstring_raw_stack: list[bool] = []

    # ------------------------------------------------------------------
    # Character access helpers
    # ------------------------------------------------------------------

    def current(self) -> str:
        """Return the current character, or '' if at end of source."""
        if self.pos < len(self.source):
            return self.source[self.pos]
        return ""

    def peek(self, offset: int = 1) -> str:
        """Return the character at pos+offset, or '' if out of bounds."""
        idx = self.pos + offset
        if 0 <= idx < len(self.source):
            return self.source[idx]
        return ""

    def advance(self) -> str:
        """Consume and return the current character, updating line/col."""
        if self.pos >= len(self.source):
            return ""
        ch = self.source[self.pos]
        self.pos += 1
        if ch == "\n":
            self.line += 1
            self.col = 1
        else:
            self.col += 1
        return ch

    def at_end(self) -> bool:
        """Return True if pos is at or past end of source."""
        return self.pos >= len(self.source)

    def match_char(self, ch: str) -> bool:
        """If the current character matches *ch*, consume it and return True."""
        if self.pos < len(self.source) and self.source[self.pos] == ch:
            self.advance()
            return True
        return False

    def match_string(self, s: str) -> bool:
        """If the source starting at pos matches *s*, consume it and return True."""
        end = self.pos + len(s)
        if end <= len(self.source) and self.source[self.pos:end] == s:
            for _ in range(len(s)):
                self.advance()
            return True
        return False

    # ------------------------------------------------------------------
    # Mode helpers
    # ------------------------------------------------------------------

    def _current_mode(self) -> str:
        """Return the current lexer mode from the top of the mode stack."""
        return self.mode_stack[-1] if self.mode_stack else _MODE_NORMAL

    def _in_fstring_text_mode(self) -> bool:
        """Return True if the current mode is an f-string text scanning mode."""
        return self._current_mode() in _FSTRING_MODE_INFO

    def _in_fstring_expr_mode(self) -> bool:
        """Return True if we are inside an f-string expression ({...})."""
        return self._current_mode() == _MODE_FSTRING_EXPR

    # ------------------------------------------------------------------
    # Whitespace and comment skipping
    # ------------------------------------------------------------------

    def skip_whitespace_and_comments(self) -> None:
        """Skip over whitespace, line comments (#), and block comments (#*...*#)."""
        while not self.at_end():
            ch = self.current()

            # Whitespace
            if ch in " \t\r\n\f":
                self.advance()
                continue

            # Comment handling
            if ch == "#":
                # Block comment: #* ... *#
                if self.peek() == "*":
                    self.advance()  # consume '#'
                    self.advance()  # consume '*'
                    depth = 1
                    while not self.at_end() and depth > 0:
                        if self.current() == "#" and self.peek() == "*":
                            self.advance()
                            self.advance()
                            depth += 1
                        elif self.current() == "*" and self.peek() == "#":
                            self.advance()
                            self.advance()
                            depth -= 1
                        else:
                            self.advance()
                    continue

                # Line comment: # until end of line
                self.advance()  # consume '#'
                while not self.at_end() and self.current() != "\n":
                    self.advance()
                continue

            # Not whitespace or comment -- stop.
            break

    # ------------------------------------------------------------------
    # Identifier and keyword scanning
    # ------------------------------------------------------------------

    def scan_identifier(self) -> BootstrapToken:
        """Scan an identifier or keyword token.

        After scanning, checks for combined tokens:
          - "not" followed by "in"  -> KW_NIN
          - "is"  followed by "not" -> KW_ISN
        Also checks the KEYWORD_MAP for keyword classification.
        """
        start_pos = self.pos
        start_line = self.line
        start_col = self.col

        # Consume identifier characters: [a-zA-Z_][a-zA-Z0-9_]*
        while not self.at_end() and (self.current().isalnum() or self.current() == "_"):
            self.advance()

        value = self.source[start_pos:self.pos]

        # Check for combined "not in" -> KW_NIN
        if value == "not":
            saved_pos = self.pos
            saved_line = self.line
            saved_col = self.col
            # Skip whitespace (but not comments) to peek at next word
            temp_pos = self.pos
            while temp_pos < len(self.source) and self.source[temp_pos] in " \t\r\n\f":
                temp_pos += 1
            # Check if "in" follows and is a complete word
            if (
                temp_pos + 2 <= len(self.source)
                and self.source[temp_pos:temp_pos + 2] == "in"
                and (
                    temp_pos + 2 >= len(self.source)
                    or not (self.source[temp_pos + 2].isalnum() or self.source[temp_pos + 2] == "_")
                )
            ):
                # Consume whitespace and "in"
                while self.pos < temp_pos:
                    self.advance()
                # Consume "in"
                self.advance()  # 'i'
                self.advance()  # 'n'
                combined_value = self.source[start_pos:self.pos]
                return BootstrapToken(
                    type=Tok.KW_NIN.value,
                    value=combined_value,
                    line=start_line,
                    end_line=self.line,
                    col_start=start_col,
                    col_end=self.col,
                    pos_start=start_pos,
                    pos_end=self.pos,
                )
            # Restore position -- it's just "not"
            self.pos = saved_pos
            self.line = saved_line
            self.col = saved_col

        # Check for combined "is not" -> KW_ISN
        if value == "is":
            saved_pos = self.pos
            saved_line = self.line
            saved_col = self.col
            temp_pos = self.pos
            while temp_pos < len(self.source) and self.source[temp_pos] in " \t\r\n\f":
                temp_pos += 1
            if (
                temp_pos + 3 <= len(self.source)
                and self.source[temp_pos:temp_pos + 3] == "not"
                and (
                    temp_pos + 3 >= len(self.source)
                    or not (self.source[temp_pos + 3].isalnum() or self.source[temp_pos + 3] == "_")
                )
            ):
                while self.pos < temp_pos:
                    self.advance()
                self.advance()  # 'n'
                self.advance()  # 'o'
                self.advance()  # 't'
                combined_value = self.source[start_pos:self.pos]
                return BootstrapToken(
                    type=Tok.KW_ISN.value,
                    value=combined_value,
                    line=start_line,
                    end_line=self.line,
                    col_start=start_col,
                    col_end=self.col,
                    pos_start=start_pos,
                    pos_end=self.pos,
                )
            self.pos = saved_pos
            self.line = saved_line
            self.col = saved_col

        # Check keyword map
        tok_type = KEYWORD_MAP.get(value)
        if tok_type is not None:
            return BootstrapToken(
                type=tok_type.value,
                value=value,
                line=start_line,
                end_line=self.line,
                col_start=start_col,
                col_end=self.col,
                pos_start=start_pos,
                pos_end=self.pos,
            )

        # Plain identifier
        return BootstrapToken(
            type=Tok.NAME.value,
            value=value,
            line=start_line,
            end_line=self.line,
            col_start=start_col,
            col_end=self.col,
            pos_start=start_pos,
            pos_end=self.pos,
        )

    # ------------------------------------------------------------------
    # Number scanning
    # ------------------------------------------------------------------

    def scan_number(self) -> BootstrapToken:
        """Scan an integer, float, hex, binary, or octal literal.

        Supports:
          - 0x/0X hex, 0b/0B binary, 0o/0O octal
          - Decimal integers with optional underscores: 1_000_000
          - Floats: 3.14, .5, 1e10, 2.5e-3
        """
        start_pos = self.pos
        start_line = self.line
        start_col = self.col

        ch = self.current()

        # Leading zero -> check for hex, bin, oct prefixes
        if ch == "0" and self.peek() in "xXbBoO":
            self.advance()  # consume '0'
            prefix = self.advance()  # consume prefix letter

            if prefix in "xX":
                # Hex literal
                while not self.at_end() and (self.current() in "0123456789abcdefABCDEF_"):
                    self.advance()
                return BootstrapToken(
                    type=Tok.HEX.value,
                    value=self.source[start_pos:self.pos],
                    line=start_line,
                    end_line=self.line,
                    col_start=start_col,
                    col_end=self.col,
                    pos_start=start_pos,
                    pos_end=self.pos,
                )
            elif prefix in "bB":
                # Binary literal
                while not self.at_end() and self.current() in "01_":
                    self.advance()
                return BootstrapToken(
                    type=Tok.BIN.value,
                    value=self.source[start_pos:self.pos],
                    line=start_line,
                    end_line=self.line,
                    col_start=start_col,
                    col_end=self.col,
                    pos_start=start_pos,
                    pos_end=self.pos,
                )
            else:
                # Octal literal (prefix in "oO")
                while not self.at_end() and self.current() in "01234567_":
                    self.advance()
                return BootstrapToken(
                    type=Tok.OCT.value,
                    value=self.source[start_pos:self.pos],
                    line=start_line,
                    end_line=self.line,
                    col_start=start_col,
                    col_end=self.col,
                    pos_start=start_pos,
                    pos_end=self.pos,
                )

        # Decimal integer or float.
        # Consume digits (with underscores).
        has_dot = False
        has_exp = False

        # Handle leading dot case (e.g. ".5") -- this is called from next_token
        # when we see a dot followed by a digit, so the dot hasn't been consumed yet
        # Actually, scan_number is called when current() is a digit, so leading dot
        # is handled in next_token by checking '.' followed by digit.

        # Consume leading digits
        while not self.at_end() and (self.current().isdigit() or self.current() == "_"):
            self.advance()

        # Check for decimal point
        if not self.at_end() and self.current() == "." and self.peek() != ".":
            # Make sure it's not "..." (ellipsis)
            # Also check the next char is a digit or the exponent follows
            next_ch = self.peek()
            if next_ch.isdigit() or next_ch in "eE" or next_ch == "_":
                has_dot = True
                self.advance()  # consume '.'
                while not self.at_end() and (self.current().isdigit() or self.current() == "_"):
                    self.advance()
            elif not (next_ch.isalpha() or next_ch == "_"):
                # Bare dot after digits like "3." -- this is a float
                has_dot = True
                self.advance()  # consume '.'

        # Check for exponent
        if not self.at_end() and self.current() in "eE":
            has_exp = True
            self.advance()  # consume 'e'/'E'
            if not self.at_end() and self.current() in "+-":
                self.advance()  # consume sign
            while not self.at_end() and (self.current().isdigit() or self.current() == "_"):
                self.advance()

        value = self.source[start_pos:self.pos]
        tok_type = Tok.FLOAT.value if (has_dot or has_exp) else Tok.INT.value

        return BootstrapToken(
            type=tok_type,
            value=value,
            line=start_line,
            end_line=self.line,
            col_start=start_col,
            col_end=self.col,
            pos_start=start_pos,
            pos_end=self.pos,
        )

    # ------------------------------------------------------------------
    # String scanning (regular strings, not f-strings)
    # ------------------------------------------------------------------

    def scan_string(self, quote: str) -> BootstrapToken:
        """Scan a regular string literal (single, double, or triple quoted).

        Handles escape sequences, raw strings (r prefix), and byte strings (b prefix).
        The quote character (' or ") has NOT been consumed yet.
        Any prefix characters (r, b, rb, br) have already been consumed and
        the pos is at the opening quote.

        Args:
            quote: The quote character (' or ").
        """
        start_pos = self.pos
        start_line = self.line
        start_col = self.col

        # Detect triple quote
        is_triple = False
        triple = quote * 3
        if self.source[self.pos:self.pos + 3] == triple:
            is_triple = True
            self.advance()  # consume first quote
            self.advance()  # consume second quote
            self.advance()  # consume third quote
        else:
            self.advance()  # consume single opening quote

        # Scan string body
        while not self.at_end():
            ch = self.current()

            if ch == "\\" :
                # Escape sequence: consume backslash and next character
                self.advance()
                if not self.at_end():
                    self.advance()
                continue

            if is_triple:
                # Check for closing triple quote
                if (
                    ch == quote
                    and self.peek(1) == quote
                    and self.peek(2) == quote
                ):
                    self.advance()  # first quote
                    self.advance()  # second quote
                    self.advance()  # third quote
                    break
                self.advance()
            else:
                if ch == quote:
                    self.advance()  # consume closing quote
                    break
                if ch == "\n":
                    # Unterminated single-line string -- stop here
                    break
                self.advance()

        return BootstrapToken(
            type=Tok.STRING.value,
            value=self.source[start_pos:self.pos],
            line=start_line,
            end_line=self.line,
            col_start=start_col,
            col_end=self.col,
            pos_start=start_pos,
            pos_end=self.pos,
        )

    # ------------------------------------------------------------------
    # F-string scanning
    # ------------------------------------------------------------------

    def scan_fstring_start(self, is_raw: bool) -> BootstrapToken:
        """Scan the opening delimiter of an f-string and push the fstring mode.

        The prefix characters (f, rf, fr, etc.) have already been consumed.
        The pos is at the opening quote character.

        Returns the F_*_START token.
        """
        start_pos = self.pos
        start_line = self.line
        start_col = self.col

        quote_char = self.current()  # ' or "

        # Detect triple quote
        is_triple = False
        if self.peek(1) == quote_char and self.peek(2) == quote_char:
            is_triple = True
            self.advance()  # first quote
            self.advance()  # second quote
            self.advance()  # third quote
        else:
            self.advance()  # single quote

        # Determine mode and token types
        mode = _FSTRING_QUOTE_TO_MODE[(quote_char, is_triple)]
        info = _FSTRING_MODE_INFO[mode]

        if is_raw:
            # Raw f-string: use RF_* token types
            if is_triple:
                if quote_char == '"':
                    start_tok = Tok.RF_TDQ_START.value
                else:
                    start_tok = Tok.RF_TSQ_START.value
            else:
                if quote_char == '"':
                    start_tok = Tok.RF_DQ_START.value
                else:
                    start_tok = Tok.RF_SQ_START.value
        else:
            start_tok = info[3]  # start token from mode info

        # Push fstring text mode
        self.mode_stack.append(mode)
        self.fstring_raw_stack.append(is_raw)

        return BootstrapToken(
            type=start_tok,
            value=self.source[start_pos:self.pos],
            line=start_line,
            end_line=self.line,
            col_start=start_col,
            col_end=self.col,
            pos_start=start_pos,
            pos_end=self.pos,
        )

    def _scan_fstring_text(self) -> BootstrapToken | None:
        """Scan text content inside an f-string (between expressions).

        Handles escaped braces ({{ and }}), and stops at {, }, or closing quote.
        Returns None if there is no text to consume (we are at a brace or quote).
        """
        mode = self._current_mode()
        info = _FSTRING_MODE_INFO[mode]
        quote_char = info[0]
        is_triple = info[1]
        is_raw = self.fstring_raw_stack[-1] if self.fstring_raw_stack else False

        # Determine the text token type
        if is_raw:
            if is_triple:
                text_tok = Tok.RF_TEXT_TDQ.value if quote_char == '"' else Tok.RF_TEXT_TSQ.value
            else:
                text_tok = Tok.RF_TEXT_DQ.value if quote_char == '"' else Tok.RF_TEXT_SQ.value
        else:
            text_tok = info[5]  # text token from mode info

        start_pos = self.pos
        start_line = self.line
        start_col = self.col

        while not self.at_end():
            ch = self.current()

            # Check for closing quote
            if ch == quote_char:
                if is_triple:
                    if self.peek(1) == quote_char and self.peek(2) == quote_char:
                        break  # Let the caller handle the closing triple quote
                    # Single quote_char inside a triple-quoted fstring is just text
                    self.advance()
                    continue
                else:
                    break  # Let the caller handle the closing single quote

            # Stop at braces (expression boundaries)
            if ch in "{}":
                break

            # Handle escape sequences in non-raw f-strings
            if ch == "\\" and not is_raw:
                self.advance()  # consume backslash
                if not self.at_end():
                    self.advance()  # consume escaped character
                continue

            # Handle newlines in non-triple-quoted strings
            if ch == "\n" and not is_triple:
                break  # Unterminated f-string line

            self.advance()

        if self.pos == start_pos:
            return None  # No text consumed

        return BootstrapToken(
            type=text_tok,
            value=self.source[start_pos:self.pos],
            line=start_line,
            end_line=self.line,
            col_start=start_col,
            col_end=self.col,
            pos_start=start_pos,
            pos_end=self.pos,
        )

    def _scan_fstring_token(self) -> BootstrapToken | None:
        """Dispatch scanning for the next token while in f-string text mode.

        Handles:
          - Closing quote -> F_*_END token, pop mode
          - {{ -> D_LBRACE (escaped brace)
          - }} -> D_RBRACE (escaped brace)
          - {  -> LBRACE, push fstring_expr mode
          - text content -> F_TEXT_* token
        """
        if self.at_end():
            return None

        mode = self._current_mode()
        info = _FSTRING_MODE_INFO[mode]
        quote_char = info[0]
        is_triple = info[1]
        end_tok = info[4]

        ch = self.current()

        # Check for closing quote
        if ch == quote_char:
            if is_triple:
                if self.peek(1) == quote_char and self.peek(2) == quote_char:
                    # Closing triple quote
                    start_pos = self.pos
                    start_line = self.line
                    start_col = self.col
                    self.advance()
                    self.advance()
                    self.advance()
                    self.mode_stack.pop()
                    if self.fstring_raw_stack:
                        self.fstring_raw_stack.pop()
                    return BootstrapToken(
                        type=end_tok,
                        value=self.source[start_pos:self.pos],
                        line=start_line,
                        end_line=self.line,
                        col_start=start_col,
                        col_end=self.col,
                        pos_start=start_pos,
                        pos_end=self.pos,
                    )
                # Not a triple -- fall through to text scanning
            else:
                # Closing single quote
                start_pos = self.pos
                start_line = self.line
                start_col = self.col
                self.advance()
                self.mode_stack.pop()
                if self.fstring_raw_stack:
                    self.fstring_raw_stack.pop()
                return BootstrapToken(
                    type=end_tok,
                    value=self.source[start_pos:self.pos],
                    line=start_line,
                    end_line=self.line,
                    col_start=start_col,
                    col_end=self.col,
                    pos_start=start_pos,
                    pos_end=self.pos,
                )

        # Doubled braces: {{ -> D_LBRACE, }} -> D_RBRACE
        if ch == "{" and self.peek() == "{":
            start_pos = self.pos
            start_line = self.line
            start_col = self.col
            self.advance()
            self.advance()
            return BootstrapToken(
                type=Tok.D_LBRACE.value,
                value="{{",
                line=start_line,
                end_line=self.line,
                col_start=start_col,
                col_end=self.col,
                pos_start=start_pos,
                pos_end=self.pos,
            )

        if ch == "}" and self.peek() == "}":
            start_pos = self.pos
            start_line = self.line
            start_col = self.col
            self.advance()
            self.advance()
            return BootstrapToken(
                type=Tok.D_RBRACE.value,
                value="}}",
                line=start_line,
                end_line=self.line,
                col_start=start_col,
                col_end=self.col,
                pos_start=start_pos,
                pos_end=self.pos,
            )

        # Single open brace: start expression
        if ch == "{":
            start_pos = self.pos
            start_line = self.line
            start_col = self.col
            self.advance()
            # Save current fstring brace depth and start a new expression
            self.fstring_brace_depth_stack.append(self.fstring_brace_depth)
            self.fstring_brace_depth = 1
            self.mode_stack.append(_MODE_FSTRING_EXPR)
            return BootstrapToken(
                type=Tok.LBRACE.value,
                value="{",
                line=start_line,
                end_line=self.line,
                col_start=start_col,
                col_end=self.col,
                pos_start=start_pos,
                pos_end=self.pos,
            )

        # Text content
        text_token = self._scan_fstring_text()
        if text_token is not None:
            return text_token

        # If we get here with no progress, something is wrong.
        # Consume a character to avoid infinite loop.
        if not self.at_end():
            start_pos = self.pos
            start_line = self.line
            start_col = self.col
            ch = self.advance()
            return BootstrapToken(
                type=Tok.STRING.value,
                value=ch,
                line=start_line,
                end_line=self.line,
                col_start=start_col,
                col_end=self.col,
                pos_start=start_pos,
                pos_end=self.pos,
            )

        return None

    # ------------------------------------------------------------------
    # Operator and delimiter scanning
    # ------------------------------------------------------------------

    def scan_operator(self) -> BootstrapToken:
        """Scan an operator or delimiter token using longest-match.

        Handles multi-character operators first, falling back to single-char.
        """
        start_pos = self.pos
        start_line = self.line
        start_col = self.col
        ch = self.current()

        # --- Multi-character operators (longest match first) ---

        # 4-character operators
        four = self.source[self.pos:self.pos + 4] if self.pos + 4 <= len(self.source) else ""
        if four == "<-->":
            for _ in range(4):
                self.advance()
            return self._make_op_token(Tok.ARROW_BI.value, start_pos, start_line, start_col)
        if four == "<++>":
            for _ in range(4):
                self.advance()
            return self._make_op_token(Tok.CARROW_BI.value, start_pos, start_line, start_col)

        # 3-character operators
        three = self.source[self.pos:self.pos + 3] if self.pos + 3 <= len(self.source) else ""

        three_char_ops: dict[str, str] = {
            "**=": Tok.STAR_POW_EQ.value,
            "//=": Tok.FLOOR_DIV_EQ.value,
            "<<=": Tok.LSHIFT_EQ.value,
            ">>=": Tok.RSHIFT_EQ.value,
            "...": Tok.ELLIPSIS.value,
            "-->": Tok.ARROW_R.value,
            "<--": Tok.ARROW_L.value,
            "++>": Tok.CARROW_R.value,
            "<++": Tok.CARROW_L.value,
            "<-:": Tok.ARROW_L_P1.value,
            ":->": Tok.ARROW_R_P2.value,
            ":<-": Tok.ARROW_L_P2.value,
            "->:": Tok.ARROW_R_P1.value,
            "<+:": Tok.CARROW_L_P1.value,
            ":+>": Tok.CARROW_R_P2.value,
            ":<+": Tok.CARROW_L_P2.value,
            "+>:": Tok.CARROW_R_P1.value,
        }

        if three in three_char_ops:
            for _ in range(3):
                self.advance()
            return self._make_op_token(three_char_ops[three], start_pos, start_line, start_col)

        # 2-character operators
        two = self.source[self.pos:self.pos + 2] if self.pos + 2 <= len(self.source) else ""

        two_char_ops: dict[str, str] = {
            "**": Tok.STAR_POW.value,
            "//": Tok.FLOOR_DIV.value,
            "<<": Tok.LSHIFT.value,
            ">>": Tok.RSHIFT.value,
            "->": Tok.RETURN_HINT.value,
            "+=": Tok.ADD_EQ.value,
            "-=": Tok.SUB_EQ.value,
            "*=": Tok.MUL_EQ.value,
            "/=": Tok.DIV_EQ.value,
            "%=": Tok.MOD_EQ.value,
            "&=": Tok.BW_AND_EQ.value,
            "|=": Tok.BW_OR_EQ.value,
            "^=": Tok.BW_XOR_EQ.value,
            "@=": Tok.MATMUL_EQ.value,
            "==": Tok.EE.value,
            "!=": Tok.NE.value,
            "<=": Tok.LTE.value,
            ">=": Tok.GTE.value,
            ":=": Tok.WALRUS_EQ.value,
            "|>": Tok.PIPE_FWD.value,
            "<|": Tok.PIPE_BKWD.value,
            ":>": Tok.A_PIPE_FWD.value,
            "<:": Tok.A_PIPE_BKWD.value,
            ".>": Tok.DOT_FWD.value,
            "<.": Tok.DOT_BKWD.value,
            "&&": Tok.KW_AND.value,
            "||": Tok.KW_OR.value,
        }

        if two in two_char_ops:
            for _ in range(2):
                self.advance()
            return self._make_op_token(two_char_ops[two], start_pos, start_line, start_col)

        # --- Single-character operators and delimiters ---
        single_char_ops: dict[str, str] = {
            "+": Tok.PLUS.value,
            "-": Tok.MINUS.value,
            "*": Tok.STAR_MUL.value,
            "/": Tok.DIV.value,
            "%": Tok.MOD.value,
            "<": Tok.LT.value,
            ">": Tok.GT.value,
            "=": Tok.EQ.value,
            "!": Tok.NOT.value,
            "&": Tok.BW_AND.value,
            "|": Tok.BW_OR.value,
            "^": Tok.BW_XOR.value,
            "~": Tok.BW_NOT.value,
            ".": Tok.DOT.value,
            ",": Tok.COMMA.value,
            ":": Tok.COLON.value,
            ";": Tok.SEMI.value,
            "(": Tok.LPAREN.value,
            ")": Tok.RPAREN.value,
            "{": Tok.LBRACE.value,
            "}": Tok.RBRACE.value,
            "[": Tok.LSQUARE.value,
            "]": Tok.RSQUARE.value,
            "@": Tok.DECOR_OP.value,
            "?": Tok.NULL_OK.value,
            "`": Tok.TYPE_OP.value,
        }

        if ch in single_char_ops:
            self.advance()
            return self._make_op_token(single_char_ops[ch], start_pos, start_line, start_col)

        # Unknown character -- emit as an error token with the character itself
        self.advance()
        return BootstrapToken(
            type="ERROR",
            value=ch,
            line=start_line,
            end_line=self.line,
            col_start=start_col,
            col_end=self.col,
            pos_start=start_pos,
            pos_end=self.pos,
        )

    def _make_op_token(
        self, tok_type: str, start_pos: int, start_line: int, start_col: int
    ) -> BootstrapToken:
        """Helper to construct an operator/delimiter token."""
        return BootstrapToken(
            type=tok_type,
            value=self.source[start_pos:self.pos],
            line=start_line,
            end_line=self.line,
            col_start=start_col,
            col_end=self.col,
            pos_start=start_pos,
            pos_end=self.pos,
        )

    # ------------------------------------------------------------------
    # Inline Python block scanning
    # ------------------------------------------------------------------

    def scan_pynline(self) -> BootstrapToken:
        """Scan a ::py:: ... ::py:: inline Python block."""
        start_pos = self.pos
        start_line = self.line
        start_col = self.col

        # We've already verified that ::py:: is at self.pos.
        # Consume the opening ::py::
        for _ in range(6):  # len("::py::") == 6
            self.advance()

        # Scan until the closing ::py::
        while not self.at_end():
            if (
                self.current() == ":"
                and self.pos + 6 <= len(self.source)
                and self.source[self.pos:self.pos + 6] == "::py::"
            ):
                # Consume closing ::py::
                for _ in range(6):
                    self.advance()
                break
            self.advance()

        return BootstrapToken(
            type=Tok.PYNLINE.value,
            value=self.source[start_pos:self.pos],
            line=start_line,
            end_line=self.line,
            col_start=start_col,
            col_end=self.col,
            pos_start=start_pos,
            pos_end=self.pos,
        )

    # ------------------------------------------------------------------
    # Keyword-escaped name scanning
    # ------------------------------------------------------------------

    def scan_kwesc_name(self) -> BootstrapToken:
        """Scan a keyword-escaped name: <>identifier."""
        start_pos = self.pos
        start_line = self.line
        start_col = self.col

        # Consume '<>'
        self.advance()  # '<'
        self.advance()  # '>'

        # Consume identifier characters
        while not self.at_end() and (self.current().isalnum() or self.current() == "_"):
            self.advance()

        return BootstrapToken(
            type=Tok.KWESC_NAME.value,
            value=self.source[start_pos:self.pos],
            line=start_line,
            end_line=self.line,
            col_start=start_col,
            col_end=self.col,
            pos_start=start_pos,
            pos_end=self.pos,
        )

    # ------------------------------------------------------------------
    # Conversion specifier scanning (for f-strings: !r, !s, !a)
    # ------------------------------------------------------------------

    def scan_conv(self) -> BootstrapToken | None:
        """Scan an f-string conversion specifier: !r, !s, !a, !R, !S, !A.

        Returns None if the current position is not a valid conversion spec.
        """
        if self.current() == "!" and self.peek() in "rRsSaA":
            start_pos = self.pos
            start_line = self.line
            start_col = self.col
            self.advance()  # '!'
            self.advance()  # conversion letter
            return BootstrapToken(
                type=Tok.CONV.value,
                value=self.source[start_pos:self.pos],
                line=start_line,
                end_line=self.line,
                col_start=start_col,
                col_end=self.col,
                pos_start=start_pos,
                pos_end=self.pos,
            )
        return None

    # ------------------------------------------------------------------
    # F-string format text scanning
    # ------------------------------------------------------------------

    def _scan_fformat_text(self) -> BootstrapToken | None:
        """Scan format specification text in f-string after colon.

        Scans text that is not { or }, used for format specs like :.2f
        """
        start_pos = self.pos
        start_line = self.line
        start_col = self.col

        while not self.at_end() and self.current() not in "{}":
            self.advance()

        if self.pos == start_pos:
            return None

        return BootstrapToken(
            type=Tok.F_FORMAT_TEXT.value,
            value=self.source[start_pos:self.pos],
            line=start_line,
            end_line=self.line,
            col_start=start_col,
            col_end=self.col,
            pos_start=start_pos,
            pos_end=self.pos,
        )

    # ------------------------------------------------------------------
    # Main token dispatch
    # ------------------------------------------------------------------

    def next_token(self) -> BootstrapToken | None:
        """Scan and return the next token, or None for skipped content (whitespace/comments).

        Dispatches based on the current lexer mode and character.
        """
        if self.at_end():
            return None

        # --- F-string text mode ---
        if self._in_fstring_text_mode():
            return self._scan_fstring_token()

        # --- F-string expression mode ---
        # In expression mode, we scan normal tokens but track brace depth.
        if self._in_fstring_expr_mode():
            # Skip whitespace and comments inside f-string expressions
            self.skip_whitespace_and_comments()
            if self.at_end():
                return None

            ch = self.current()

            # Check for conversion specifier before processing '!' as NOT operator
            if ch == "!" and self.peek() in "rRsSaA":
                # Could be a conversion spec if we're about to hit } or :
                # We need to check context -- if next-next char is } or :, it's CONV
                peek2 = self.peek(2)
                if peek2 in "}:" or peek2 == "":
                    return self.scan_conv()

            # Closing brace handling for f-string expressions
            if ch == "}":
                self.fstring_brace_depth -= 1
                if self.fstring_brace_depth == 0:
                    # End of f-string expression -- return to fstring text mode
                    start_pos = self.pos
                    start_line = self.line
                    start_col = self.col
                    self.advance()
                    self.mode_stack.pop()  # pop fstring_expr
                    # Restore previous brace depth
                    if self.fstring_brace_depth_stack:
                        self.fstring_brace_depth = self.fstring_brace_depth_stack.pop()
                    return BootstrapToken(
                        type=Tok.RBRACE.value,
                        value="}",
                        line=start_line,
                        end_line=self.line,
                        col_start=start_col,
                        col_end=self.col,
                        pos_start=start_pos,
                        pos_end=self.pos,
                    )
                # Nested brace -- fall through to normal operator scanning

            if ch == "{":
                self.fstring_brace_depth += 1
                # Fall through to normal operator scanning

            # Normal token scanning inside f-string expression
            return self._scan_normal_token()

        # --- Normal mode ---
        self.skip_whitespace_and_comments()
        if self.at_end():
            return None

        return self._scan_normal_token()

    def _scan_normal_token(self) -> BootstrapToken | None:
        """Scan a single token in normal (non-fstring-text) mode.

        This is the core dispatch that handles identifiers, numbers, strings,
        f-strings, operators, and special constructs.
        """
        if self.at_end():
            return None

        ch = self.current()

        # --- Inline Python block: ::py:: ---
        if ch == ":" and self.pos + 6 <= len(self.source) and self.source[self.pos:self.pos + 6] == "::py::":
            return self.scan_pynline()

        # --- Keyword-escaped names: <>name ---
        if ch == "<" and self.peek() == ">" and self.peek(2).isalpha():
            return self.scan_kwesc_name()

        # --- Identifiers and keywords ---
        if ch.isalpha() or ch == "_":
            # Check for string prefixes: r, b, rb, br, f, rf, fr, F, etc.
            # We need to peek ahead to see if this is a string/fstring prefix.
            return self._scan_identifier_or_string_prefix()

        # --- Numbers ---
        if ch.isdigit():
            return self.scan_number()

        # --- Leading dot followed by digit: float literal like .5 ---
        if ch == "." and self.peek().isdigit():
            return self._scan_dot_number()

        # --- String literals (no prefix) ---
        if ch in "\"'":
            # Record the position before the quote for the token start.
            return self.scan_string(ch)

        # --- Operators and delimiters ---
        return self.scan_operator()

    def _scan_identifier_or_string_prefix(self) -> BootstrapToken:
        """Handle an identifier that might be a string or f-string prefix.

        Checks for prefixes: f, F, r, R, b, B, rf, fr, rF, fR, Rf, Fr, RF, FR,
        rb, br, rB, bR, Rb, Br, RB, BR -- followed by a quote character.
        """
        start_pos = self.pos
        start_line = self.line
        start_col = self.col
        ch = self.current()
        ch_lower = ch.lower()

        # Quick check: does this character start a possible string prefix?
        if ch_lower in "frbFRB":
            next_ch = self.peek()
            next_lower = next_ch.lower() if next_ch else ""

            # Single-char prefix: f"...", r"...", b"..."
            if next_ch in "\"'":
                if ch_lower == "f":
                    # F-string
                    self.advance()  # consume 'f'/'F'
                    return self.scan_fstring_start(is_raw=False)
                elif ch_lower in "rb":
                    # Raw or bytes string
                    self.advance()  # consume prefix
                    return self.scan_string(next_ch)

            # Two-char prefix: rf"...", fr"...", rb"...", br"..."
            if next_lower in "frbFRB":
                peek2 = self.peek(2)
                if peek2 in "\"'":
                    combo = ch_lower + next_lower
                    if combo in ("rf", "fr"):
                        # Raw f-string
                        self.advance()  # consume first prefix char
                        self.advance()  # consume second prefix char
                        return self.scan_fstring_start(is_raw=True)
                    elif combo in ("rb", "br"):
                        # Raw bytes string
                        self.advance()  # consume first prefix char
                        self.advance()  # consume second prefix char
                        return self.scan_string(peek2)

        # Not a string prefix -- scan as normal identifier
        return self.scan_identifier()

    def _scan_dot_number(self) -> BootstrapToken:
        """Scan a float literal that starts with a dot, e.g. .5, .123e4."""
        start_pos = self.pos
        start_line = self.line
        start_col = self.col

        self.advance()  # consume '.'

        # Consume digits after the dot
        while not self.at_end() and (self.current().isdigit() or self.current() == "_"):
            self.advance()

        # Check for exponent
        if not self.at_end() and self.current() in "eE":
            self.advance()
            if not self.at_end() and self.current() in "+-":
                self.advance()
            while not self.at_end() and (self.current().isdigit() or self.current() == "_"):
                self.advance()

        return BootstrapToken(
            type=Tok.FLOAT.value,
            value=self.source[start_pos:self.pos],
            line=start_line,
            end_line=self.line,
            col_start=start_col,
            col_end=self.col,
            pos_start=start_pos,
            pos_end=self.pos,
        )

    # ------------------------------------------------------------------
    # Full tokenization
    # ------------------------------------------------------------------

    def tokenize(self) -> list[BootstrapToken]:
        """Tokenize the entire source string and return the token list.

        Appends a synthetic EOF token at the end. The returned list is also
        stored in self.tokens.
        """
        self.tokens = []
        self.pos = 0
        self.line = 1
        self.col = 1
        self.mode_stack = [_MODE_NORMAL]
        self.fstring_brace_depth = 0
        self.fstring_brace_depth_stack = []
        self.fstring_raw_stack = []

        while not self.at_end():
            token = self.next_token()
            if token is not None:
                self.tokens.append(token)

        # Append EOF sentinel
        self.tokens.append(
            BootstrapToken(
                type="EOF",
                value="",
                line=self.line,
                end_line=self.line,
                col_start=self.col,
                col_end=self.col,
                pos_start=self.pos,
                pos_end=self.pos,
            )
        )

        return self.tokens


# =========================================================================
# BOOTSTRAP PARSER
# =========================================================================

# -----------------------------------------------------------------------
# Token value reverse map for gen_token()
# -----------------------------------------------------------------------

_TOKEN_VALUE_MAP: dict[str, str] = {
    # Delimiters
    Tok.LBRACE.value: "{", Tok.RBRACE.value: "}", Tok.LPAREN.value: "(",
    Tok.RPAREN.value: ")", Tok.LSQUARE.value: "[", Tok.RSQUARE.value: "]",
    Tok.COMMA.value: ",", Tok.COLON.value: ":", Tok.SEMI.value: ";",
    Tok.DOT.value: ".", Tok.EQ.value: "=", Tok.RETURN_HINT.value: "->",
    Tok.DECOR_OP.value: "@", Tok.ELLIPSIS.value: "...",
    Tok.NULL_OK.value: "?.", Tok.TYPE_OP.value: "`",
    Tok.WALRUS_EQ.value: ":=",
    # Arithmetic
    Tok.PLUS.value: "+", Tok.MINUS.value: "-", Tok.STAR_MUL.value: "*",
    Tok.DIV.value: "/", Tok.FLOOR_DIV.value: "//", Tok.MOD.value: "%",
    Tok.STAR_POW.value: "**",
    # Bitwise
    Tok.BW_AND.value: "&", Tok.BW_OR.value: "|", Tok.BW_XOR.value: "^",
    Tok.BW_NOT.value: "~", Tok.LSHIFT.value: "<<", Tok.RSHIFT.value: ">>",
    # Comparison
    Tok.EE.value: "==", Tok.NE.value: "!=", Tok.LT.value: "<",
    Tok.GT.value: ">", Tok.LTE.value: "<=", Tok.GTE.value: ">=",
    # Augmented assignment
    Tok.ADD_EQ.value: "+=", Tok.SUB_EQ.value: "-=", Tok.MUL_EQ.value: "*=",
    Tok.DIV_EQ.value: "/=", Tok.MOD_EQ.value: "%=",
    Tok.STAR_POW_EQ.value: "**=", Tok.FLOOR_DIV_EQ.value: "//=",
    Tok.BW_AND_EQ.value: "&=", Tok.BW_OR_EQ.value: "|=",
    Tok.BW_XOR_EQ.value: "^=", Tok.LSHIFT_EQ.value: "<<=",
    Tok.RSHIFT_EQ.value: ">>=", Tok.MATMUL_EQ.value: "@=",
    # Pipe operators
    Tok.PIPE_FWD.value: "|>", Tok.PIPE_BKWD.value: "<|",
    Tok.A_PIPE_FWD.value: ":>", Tok.A_PIPE_BKWD.value: "<:",
    # Keywords
    Tok.KW_IF.value: "if", Tok.KW_ELIF.value: "elif",
    Tok.KW_ELSE.value: "else", Tok.KW_FOR.value: "for",
    Tok.KW_WHILE.value: "while", Tok.KW_IN.value: "in",
    Tok.KW_RETURN.value: "return", Tok.KW_BREAK.value: "break",
    Tok.KW_CONTINUE.value: "continue", Tok.KW_IMPORT.value: "import",
    Tok.KW_FROM.value: "from", Tok.KW_AS.value: "as",
    Tok.KW_INCLUDE.value: "include",
    Tok.KW_OBJECT.value: "obj", Tok.KW_CLASS.value: "class",
    Tok.KW_ENUM.value: "enum", Tok.KW_NODE.value: "node",
    Tok.KW_EDGE.value: "edge", Tok.KW_WALKER.value: "walker",
    Tok.KW_HAS.value: "has", Tok.KW_CAN.value: "can",
    Tok.KW_DEF.value: "def", Tok.KW_GLOBAL.value: "glob",
    Tok.KW_STATIC.value: "static", Tok.KW_OVERRIDE.value: "override",
    Tok.KW_IMPL.value: "impl", Tok.KW_ABSTRACT.value: "abs",
    Tok.KW_TRY.value: "try", Tok.KW_EXCEPT.value: "except",
    Tok.KW_FINALLY.value: "finally", Tok.KW_RAISE.value: "raise",
    Tok.KW_DELETE.value: "del", Tok.KW_ASSERT.value: "assert",
    Tok.KW_WITH.value: "with", Tok.KW_ENTRY.value: "entry",
    Tok.KW_EXIT.value: "exit", Tok.KW_AND.value: "and",
    Tok.KW_OR.value: "or", Tok.NOT.value: "not",
    Tok.KW_IS.value: "is", Tok.KW_NIN.value: "not in",
    Tok.KW_ISN.value: "is not",
    Tok.KW_PUB.value: "pub", Tok.KW_PRIV.value: "priv",
    Tok.KW_PROT.value: "protect",
    Tok.KW_SELF.value: "self", Tok.KW_SUPER.value: "super",
    Tok.KW_HERE.value: "here", Tok.KW_ROOT.value: "root",
    Tok.KW_VISITOR.value: "visitor", Tok.KW_PROPS.value: "props",
    Tok.KW_INIT.value: "init", Tok.KW_POST_INIT.value: "postinit",
    Tok.KW_ASYNC.value: "async", Tok.KW_AWAIT.value: "await",
    Tok.KW_YIELD.value: "yield", Tok.KW_TO.value: "to",
    Tok.KW_BY.value: "by", Tok.KW_LAMBDA.value: "lambda",
    Tok.KW_TEST.value: "test", Tok.KW_SEM.value: "sem",
    Tok.GLOBAL_OP.value: "global", Tok.NONLOCAL_OP.value: "nonlocal",
    Tok.KW_MATCH.value: "match", Tok.KW_CASE.value: "case",
    Tok.KW_SPAWN.value: "spawn", Tok.KW_VISIT.value: "visit",
    Tok.KW_DISENGAGE.value: "disengage",
    Tok.KW_SKIP.value: "skip", Tok.KW_REPORT.value: "report",
    Tok.KW_CLIENT.value: "cl", Tok.KW_SERVER.value: "sv",
    Tok.KW_NATIVE.value: "na",
}

_AUG_ASSIGN_OPS = frozenset({
    Tok.ADD_EQ.value, Tok.SUB_EQ.value, Tok.MUL_EQ.value, Tok.DIV_EQ.value,
    Tok.MOD_EQ.value, Tok.STAR_POW_EQ.value, Tok.FLOOR_DIV_EQ.value,
    Tok.BW_AND_EQ.value, Tok.BW_OR_EQ.value, Tok.BW_XOR_EQ.value,
    Tok.LSHIFT_EQ.value, Tok.RSHIFT_EQ.value, Tok.MATMUL_EQ.value,
})

_COMPARE_OPS = frozenset({
    Tok.EE.value, Tok.NE.value, Tok.LT.value, Tok.GT.value,
    Tok.LTE.value, Tok.GTE.value, Tok.KW_IN.value, Tok.KW_NIN.value,
    Tok.KW_IS.value, Tok.KW_ISN.value,
})

_BUILTIN_TYPE_TOKENS = frozenset({
    Tok.TYP_STRING.value, Tok.TYP_INT.value, Tok.TYP_FLOAT.value,
    Tok.TYP_LIST.value, Tok.TYP_TUPLE.value, Tok.TYP_SET.value,
    Tok.TYP_DICT.value, Tok.TYP_BOOL.value, Tok.TYP_BYTES.value,
    Tok.TYP_ANY.value, Tok.TYP_TYPE.value,
})

_SPECIAL_VAR_TOKENS = frozenset({
    Tok.KW_SELF.value, Tok.KW_SUPER.value, Tok.KW_HERE.value,
    Tok.KW_ROOT.value, Tok.KW_VISITOR.value, Tok.KW_PROPS.value,
    Tok.KW_INIT.value, Tok.KW_POST_INIT.value,
})

_ARCH_TOKENS = frozenset({
    Tok.KW_OBJECT.value, Tok.KW_CLASS.value, Tok.KW_NODE.value,
    Tok.KW_EDGE.value, Tok.KW_WALKER.value,
})

_FSTRING_START_TOKENS = frozenset({
    Tok.F_DQ_START.value, Tok.F_SQ_START.value,
    Tok.F_TDQ_START.value, Tok.F_TSQ_START.value,
    Tok.RF_DQ_START.value, Tok.RF_SQ_START.value,
    Tok.RF_TDQ_START.value, Tok.RF_TSQ_START.value,
})

_FSTRING_END_TOKENS = frozenset({
    Tok.F_DQ_END.value, Tok.F_SQ_END.value,
    Tok.F_TDQ_END.value, Tok.F_TSQ_END.value,
})

_FSTRING_TEXT_TOKENS = frozenset({
    Tok.F_TEXT_DQ.value, Tok.F_TEXT_SQ.value,
    Tok.F_TEXT_TDQ.value, Tok.F_TEXT_TSQ.value,
    Tok.RF_TEXT_DQ.value, Tok.RF_TEXT_SQ.value,
    Tok.RF_TEXT_TDQ.value, Tok.RF_TEXT_TSQ.value,
})


# -----------------------------------------------------------------------
# BootstrapParser
# -----------------------------------------------------------------------


class BootstrapParser:
    """Minimal recursive descent parser for the bootstrap Jac subset.

    Produces jaclang.pycore.unitree AST nodes directly so that existing
    compiler passes (SymTab, PyastGen, BytecodeGen) work unchanged.
    """

    def __init__(
        self,
        tokens: list[BootstrapToken],
        source_str: str,
        file_path: str,
    ) -> None:
        self.tokens = tokens
        self.source_str = source_str
        self.file_path = file_path
        self.pos = 0
        self.src = uni.Source(source=source_str, mod_path=file_path)

    # =================================================================
    # Token access helpers
    # =================================================================

    def cur(self) -> BootstrapToken:
        """Return the current token."""
        if self.pos < len(self.tokens):
            return self.tokens[self.pos]
        return self.tokens[-1]  # EOF

    def peek(self, offset: int = 1) -> BootstrapToken:
        """Return token at pos + offset."""
        idx = self.pos + offset
        if 0 <= idx < len(self.tokens):
            return self.tokens[idx]
        return self.tokens[-1]

    def prev(self) -> BootstrapToken:
        """Return the previous token."""
        if self.pos > 0:
            return self.tokens[self.pos - 1]
        return self.tokens[0]

    def advance(self) -> BootstrapToken:
        """Consume and return the current token."""
        tok = self.cur()
        if tok.type != "EOF":
            self.pos += 1
        return tok

    def at_end(self) -> bool:
        """Check if we've reached EOF."""
        return self.cur().type == "EOF"

    def check(self, *types: str) -> bool:
        """Check if current token matches any of the given types."""
        return self.cur().type in types

    def match(self, *types: str) -> BootstrapToken | None:
        """Consume current token if it matches any of the given types."""
        if self.cur().type in types:
            return self.advance()
        return None

    def expect(self, ttype: str) -> BootstrapToken:
        """Consume current token if it matches, otherwise raise error."""
        if self.cur().type == ttype:
            return self.advance()
        tok = self.cur()
        raise SyntaxError(
            f"Expected {ttype} but got {tok.type} ({tok.value!r}) "
            f"at {self.file_path}:{tok.line}:{tok.col_start}"
        )

    # =================================================================
    # AST node construction helpers
    # =================================================================

    @staticmethod
    def _collect_terminals(kids: list) -> list:
        """Collect all Token leaf nodes from the AST in source order."""
        result: list = []
        stack = list(reversed(kids))
        while stack:
            node = stack.pop()
            if node is None:
                continue
            if isinstance(node, uni.Token):
                result.append(node)
            elif hasattr(node, 'kid'):
                stack.extend(reversed(node.kid))
        result.sort(key=lambda t: (t.loc.first_line, t.loc.col_start))
        return result

    def _tok(self, tok: BootstrapToken, name: str | None = None) -> uni.Token:
        """Convert BootstrapToken to uni.Token."""
        return uni.Token(
            orig_src=self.src, name=name or tok.type, value=tok.value,
            line=tok.line, end_line=tok.end_line,
            col_start=tok.col_start, col_end=tok.col_end,
            pos_start=tok.pos_start, pos_end=tok.pos_end,
        )

    def _name(self, tok: BootstrapToken, is_kwesc: bool = False) -> uni.Name:
        """Convert BootstrapToken to uni.Name."""
        return uni.Name(
            orig_src=self.src, name=tok.type, value=tok.value,
            line=tok.line, end_line=tok.end_line,
            col_start=tok.col_start, col_end=tok.col_end,
            pos_start=tok.pos_start, pos_end=tok.pos_end,
            is_kwesc=is_kwesc,
        )

    def _string(self, tok: BootstrapToken) -> uni.String:
        """Convert BootstrapToken to uni.String."""
        return uni.String(
            orig_src=self.src, name=Tok.STRING.value, value=tok.value,
            line=tok.line, end_line=tok.end_line,
            col_start=tok.col_start, col_end=tok.col_end,
            pos_start=tok.pos_start, pos_end=tok.pos_end,
        )

    def _int(self, tok: BootstrapToken) -> uni.Int:
        """Convert BootstrapToken to uni.Int."""
        return uni.Int(
            orig_src=self.src, name=tok.type, value=tok.value,
            line=tok.line, end_line=tok.end_line,
            col_start=tok.col_start, col_end=tok.col_end,
            pos_start=tok.pos_start, pos_end=tok.pos_end,
        )

    def _float(self, tok: BootstrapToken) -> uni.Float:
        """Convert BootstrapToken to uni.Float."""
        return uni.Float(
            orig_src=self.src, name=Tok.FLOAT.value, value=tok.value,
            line=tok.line, end_line=tok.end_line,
            col_start=tok.col_start, col_end=tok.col_end,
            pos_start=tok.pos_start, pos_end=tok.pos_end,
        )

    def _bool(self, tok: BootstrapToken) -> uni.Bool:
        """Convert BootstrapToken to uni.Bool."""
        return uni.Bool(
            orig_src=self.src, name=Tok.BOOL.value, value=tok.value,
            line=tok.line, end_line=tok.end_line,
            col_start=tok.col_start, col_end=tok.col_end,
            pos_start=tok.pos_start, pos_end=tok.pos_end,
        )

    def _null(self, tok: BootstrapToken) -> uni.Null:
        """Convert BootstrapToken to uni.Null."""
        return uni.Null(
            orig_src=self.src, name=Tok.NULL.value, value=tok.value,
            line=tok.line, end_line=tok.end_line,
            col_start=tok.col_start, col_end=tok.col_end,
            pos_start=tok.pos_start, pos_end=tok.pos_end,
        )

    def _builtin_type(self, tok: BootstrapToken) -> uni.BuiltinType:
        """Convert BootstrapToken to uni.BuiltinType."""
        return uni.BuiltinType(
            orig_src=self.src, name=tok.type, value=tok.value,
            line=tok.line, end_line=tok.end_line,
            col_start=tok.col_start, col_end=tok.col_end,
            pos_start=tok.pos_start, pos_end=tok.pos_end,
        )

    def gen_token(self, tok_type: str, value: str | None = None) -> uni.Token:
        """Create a synthetic token at the current position."""
        if value is None:
            value = _TOKEN_VALUE_MAP.get(tok_type, tok_type)
        ref = self.prev() if self.pos > 0 else self.cur()
        return uni.Token(
            orig_src=self.src, name=tok_type, value=value,
            line=ref.line, end_line=ref.end_line,
            col_start=ref.col_start, col_end=ref.col_end,
            pos_start=ref.pos_start, pos_end=ref.pos_end,
        )

    def make_semi(self) -> uni.Semi:
        """Create a Semi node at the previous token position."""
        ref = self.prev() if self.pos > 0 else self.cur()
        return uni.Semi(
            orig_src=self.src, name=Tok.SEMI.value, value=";",
            line=ref.line, end_line=ref.end_line,
            col_start=ref.col_start, col_end=ref.col_end,
            pos_start=ref.pos_start, pos_end=ref.pos_end,
        )

    def make_empty(self) -> uni.EmptyToken:
        """Create an EmptyToken."""
        return uni.EmptyToken(orig_src=self.src)

    # =================================================================
    # Module-level parsing
    # =================================================================

    def parse(self) -> uni.Module:
        """Parse the entire module and return a Module node."""
        doc = None
        if self.check(Tok.STRING.value) and self.cur().value.startswith(('"""', "'''")):
            doc = self._string(self.advance())

        body: list = []
        while not self.at_end():
            stmt = self.parse_element_stmt()
            if stmt is not None:
                body.append(stmt)

        kid: list = []
        if doc:
            kid.append(doc)
        kid.extend(body)
        if not kid:
            kid.append(self.make_empty())

        # Collect actual Token objects from the AST (not recreated copies)
        # so that comment injection can match by id().
        terminals = self._collect_terminals(kid)

        return uni.Module(
            name=self.file_path, source=self.src, doc=doc,
            body=body, terminals=terminals, kid=kid,
        )

    def parse_element_stmt(self):
        """Parse a top-level statement."""
        if self.match(Tok.SEMI.value):
            return self.make_semi()

        # Check for docstring preceding a declaration
        doc = None
        if self.check(Tok.STRING.value) and self.cur().value.startswith(('"""', "'''")):
            saved = self.pos
            doc_tok = self.advance()
            decl_kws = (
                Tok.KW_IMPORT.value, Tok.KW_INCLUDE.value,
                Tok.KW_OBJECT.value, Tok.KW_CLASS.value, Tok.KW_ENUM.value,
                Tok.KW_NODE.value, Tok.KW_EDGE.value, Tok.KW_WALKER.value,
                Tok.KW_DEF.value, Tok.KW_CAN.value,
                Tok.KW_GLOBAL.value, Tok.KW_IMPL.value,
                Tok.KW_ABSTRACT.value, Tok.KW_STATIC.value,
                Tok.KW_OVERRIDE.value, Tok.KW_ASYNC.value,
                Tok.DECOR_OP.value, Tok.KW_WITH.value, Tok.KW_TEST.value,
            )
            if self.check(*decl_kws):
                doc = self._string(doc_tok)
            else:
                self.pos = saved

        decorators = self._parse_decorators()
        t = self.cur().type

        if t in (Tok.KW_IMPORT.value, Tok.KW_INCLUDE.value):
            return self.parse_import_stmt(doc)
        if t in _ARCH_TOKENS:
            return self.parse_archetype(doc, decorators)
        if t == Tok.KW_ABSTRACT.value and self.peek().type in _ARCH_TOKENS:
            return self.parse_archetype(doc, decorators)
        if t == Tok.KW_ENUM.value:
            return self.parse_enum(doc, decorators)
        if t in (Tok.KW_DEF.value, Tok.KW_CAN.value):
            return self.parse_ability(doc, decorators)
        if t in (Tok.KW_STATIC.value, Tok.KW_OVERRIDE.value, Tok.KW_ASYNC.value):
            nxt = self.peek().type
            if nxt in (Tok.KW_DEF.value, Tok.KW_CAN.value,
                       Tok.KW_STATIC.value, Tok.KW_OVERRIDE.value,
                       Tok.KW_ASYNC.value):
                return self.parse_ability(doc, decorators)
        if t == Tok.KW_IMPL.value:
            return self.parse_impl_def(doc, decorators)
        if t == Tok.KW_GLOBAL.value:
            return self.parse_global_var(doc)
        if t == Tok.KW_WITH.value and self.peek().type in (
            Tok.KW_ENTRY.value, Tok.KW_EXIT.value
        ):
            return self.parse_module_code(doc)
        if t == Tok.KW_TEST.value:
            return self.parse_test_block(doc)

        return self.parse_statement()

    def _parse_decorators(self) -> list:
        """Parse decorator list: @expr @expr ..."""
        decorators = []
        while self.check(Tok.DECOR_OP.value):
            self.advance()
            expr = self.parse_expression()
            decorators.append(expr)
        return decorators

    def parse_access_tag(self):
        """Parse optional access tag: :pub, :priv, :protect"""
        if self.check(Tok.COLON.value) and self.peek().type in (
            Tok.KW_PUB.value, Tok.KW_PRIV.value, Tok.KW_PROT.value
        ):
            colon = self.advance()
            access_tok = self.advance()
            colon_n = self._tok(colon)
            access_n = self._tok(access_tok)
            return uni.SubTag(tag=access_n, kid=[colon_n, access_n])
        return None

    # =================================================================
    # Import statement
    # =================================================================

    def parse_import_stmt(self, doc=None):
        """Parse: import from [.path] { items } ;"""
        kid: list = []
        hint_tok = self.advance()
        is_absorb = hint_tok.type == Tok.KW_INCLUDE.value
        kid.append(self._tok(hint_tok))

        from_loc = None
        items: list = []
        if self.check(Tok.KW_FROM.value):
            from_tok = self.advance()
            kid.append(self._tok(from_tok))
            from_loc = self._parse_module_path()
            kid.append(from_loc)
            if self.check(Tok.LBRACE.value):
                self.advance()
                kid.append(self.gen_token(Tok.LBRACE.value))
                items = self._parse_import_items(kid)
                self.expect(Tok.RBRACE.value)
                kid.append(self.gen_token(Tok.RBRACE.value))
            else:
                items = self._parse_import_items(kid)
        else:
            path = self._parse_module_path()
            items = [path]
            kid.append(path)

        if self.match(Tok.SEMI.value):
            kid.append(self.make_semi())
        return uni.Import(
            from_loc=from_loc, items=items, is_absorb=is_absorb,
            kid=kid, doc=doc,
        )

    def _parse_module_path(self):
        """Parse module path like .tokens, jaclang.pycore.unitree"""
        kid: list = []
        level = 0
        path_names: list = []
        while self.check(Tok.DOT.value):
            kid.append(self._tok(self.advance()))
            level += 1
        if self.check(Tok.NAME.value) or self.cur().type in _BUILTIN_TYPE_TOKENS:
            name = self._name(self.advance())
            path_names.append(name)
            kid.append(name)
            while self.check(Tok.DOT.value):
                kid.append(self._tok(self.advance()))
                name = self._name(self.advance())
                path_names.append(name)
                kid.append(name)
        alias = None
        if self.check(Tok.KW_AS.value):
            self.advance()
            kid.append(self.gen_token(Tok.KW_AS.value))
            alias = self._name(self.expect(Tok.NAME.value))
            kid.append(alias)
        return uni.ModulePath(
            path=path_names or None, level=level, alias=alias, kid=kid,
        )

    def _parse_import_items(self, parent_kid: list) -> list:
        """Parse comma-separated import items."""
        items: list = []
        while not self.check(Tok.RBRACE.value, Tok.SEMI.value) and not self.at_end():
            if items:
                self.expect(Tok.COMMA.value)
                parent_kid.append(self.gen_token(Tok.COMMA.value))
            if self.check(Tok.STAR_MUL.value):
                star = self._tok(self.advance())
                item = uni.ModuleItem(name=star, alias=None, kid=[star])
            else:
                name = self._name(self.advance())
                ikid: list = [name]
                alias = None
                if self.check(Tok.KW_AS.value):
                    self.advance()
                    ikid.append(self.gen_token(Tok.KW_AS.value))
                    alias = self._name(self.expect(Tok.NAME.value))
                    ikid.append(alias)
                item = uni.ModuleItem(name=name, alias=alias, kid=ikid)
            items.append(item)
            parent_kid.append(item)
            if self.check(Tok.COMMA.value) and self.peek().type in (
                Tok.RBRACE.value, Tok.SEMI.value
            ):
                self.advance()
                parent_kid.append(self.gen_token(Tok.COMMA.value))
                break
        return items

    # =================================================================
    # Archetype (obj, class, node, edge, walker)
    # =================================================================

    def parse_archetype(self, doc=None, decorators=None):
        """Parse: [abs] obj [access] Name [(bases)] { body } | ;"""
        kid: list = []
        if decorators:
            for d in decorators:
                kid.append(self.gen_token(Tok.DECOR_OP.value))
                kid.append(d)
        if self.check(Tok.KW_ABSTRACT.value):
            self.advance()
            kid.append(self.gen_token(Tok.KW_ABSTRACT.value))
        arch_tok = self.advance()
        arch_type = self._tok(arch_tok)
        kid.append(arch_type)
        access = self.parse_access_tag()
        if access:
            kid.append(access)
        name = self._name(self.expect(Tok.NAME.value))
        kid.append(name)
        base_classes = None
        if self.check(Tok.LPAREN.value):
            self.advance()
            kid.append(self.gen_token(Tok.LPAREN.value))
            base_classes = []
            while not self.check(Tok.RPAREN.value) and not self.at_end():
                if base_classes:
                    self.expect(Tok.COMMA.value)
                    kid.append(self.gen_token(Tok.COMMA.value))
                base_classes.append(self.parse_expression())
                kid.append(base_classes[-1])
            self.expect(Tok.RPAREN.value)
            kid.append(self.gen_token(Tok.RPAREN.value))
        body = None
        if self.check(Tok.LBRACE.value):
            self.advance()
            kid.append(self.gen_token(Tok.LBRACE.value))
            body = self._parse_arch_body()
            kid.extend(body)
            self.expect(Tok.RBRACE.value)
            kid.append(self.gen_token(Tok.RBRACE.value))
        elif self.match(Tok.SEMI.value):
            kid.append(self.make_semi())
        return uni.Archetype(
            name=name, arch_type=arch_type, access=access,
            base_classes=base_classes, body=body, kid=kid,
            doc=doc, decorators=decorators or None,
        )

    def _parse_arch_body(self) -> list:
        """Parse archetype body."""
        body: list = []
        while not self.check(Tok.RBRACE.value) and not self.at_end():
            doc = None
            if self.check(Tok.STRING.value) and self.cur().value.startswith(('"""', "'''")):
                doc = self._string(self.advance())
            t = self.cur().type
            if t == Tok.KW_HAS.value or (
                t == Tok.KW_STATIC.value and self.peek().type == Tok.KW_HAS.value
            ):
                body.append(self.parse_has_stmt(doc))
            elif t in (Tok.KW_DEF.value, Tok.KW_CAN.value):
                body.append(self.parse_ability(doc, []))
            elif t in (Tok.KW_STATIC.value, Tok.KW_OVERRIDE.value,
                       Tok.KW_ASYNC.value, Tok.KW_ABSTRACT.value):
                body.append(self.parse_ability(doc, []))
            elif t == Tok.DECOR_OP.value:
                decos = self._parse_decorators()
                body.append(self.parse_ability(doc, decos))
            elif self.match(Tok.SEMI.value):
                body.append(self.make_semi())
            else:
                body.append(self.parse_statement())
        return body

    # =================================================================
    # Has statement
    # =================================================================

    def parse_has_stmt(self, doc=None):
        """Parse: [static] has [access] var1: type = val, ...;"""
        kid: list = []
        is_static = False
        if self.check(Tok.KW_STATIC.value):
            self.advance()
            kid.append(self.gen_token(Tok.KW_STATIC.value))
            is_static = True
        is_frozen = False
        self.expect(Tok.KW_HAS.value)
        kid.append(self.gen_token(Tok.KW_HAS.value))
        access = self.parse_access_tag()
        if access:
            kid.append(access)
        vars_list: list = []
        while True:
            if vars_list:
                self.expect(Tok.COMMA.value)
                kid.append(self.gen_token(Tok.COMMA.value))
            var = self._parse_has_var()
            vars_list.append(var)
            kid.append(var)
            if not self.check(Tok.COMMA.value):
                break
        if self.match(Tok.SEMI.value):
            kid.append(self.make_semi())
        return uni.ArchHas(
            is_static=is_static, access=access, vars=vars_list,
            is_frozen=is_frozen, kid=kid, doc=doc,
        )

    def _parse_has_var(self):
        """Parse: name: type [= value]"""
        kid: list = []
        name = self._name(self.expect(Tok.NAME.value))
        kid.append(name)
        colon = self._tok(self.expect(Tok.COLON.value))
        type_expr = self.parse_pipe()
        type_tag = uni.SubTag(tag=type_expr, kid=[colon, type_expr])
        kid.append(type_tag)
        value = None
        if self.check(Tok.EQ.value):
            self.advance()
            kid.append(self.gen_token(Tok.EQ.value))
            value = self.parse_expression()
            kid.append(value)
        defer = False
        if self.check(Tok.KW_BY.value):
            self.advance()
            kid.append(self.gen_token(Tok.KW_BY.value))
            post = self.parse_expression()
            kid.append(post)
            defer = True
        return uni.HasVar(
            name=name, type_tag=type_tag, value=value,
            defer=defer, kid=kid,
        )

    # =================================================================
    # Ability (def / can)
    # =================================================================

    def parse_ability(self, doc=None, decorators=None):
        """Parse: [modifiers] def/can [access] name(params) -> ret { body }"""
        if decorators is None:
            decorators = []
        kid: list = []
        for d in decorators:
            kid.append(self.gen_token(Tok.DECOR_OP.value))
            kid.append(d)
        is_override = is_static = is_async = is_abstract = False
        while self.check(Tok.KW_OVERRIDE.value, Tok.KW_STATIC.value,
                         Tok.KW_ASYNC.value, Tok.KW_ABSTRACT.value):
            mod_tok = self.advance()
            kid.append(self._tok(mod_tok))
            if mod_tok.type == Tok.KW_OVERRIDE.value:
                is_override = True
            elif mod_tok.type == Tok.KW_STATIC.value:
                is_static = True
            elif mod_tok.type == Tok.KW_ASYNC.value:
                is_async = True
            elif mod_tok.type == Tok.KW_ABSTRACT.value:
                is_abstract = True
        ability_tok = self.advance()
        kid.append(self._tok(ability_tok))
        access = self.parse_access_tag()
        if access:
            kid.append(access)
        name_ref = None
        if self.check(Tok.NAME.value, Tok.KWESC_NAME.value):
            ntok = self.advance()
            name_ref = self._name(ntok, is_kwesc=(ntok.type == Tok.KWESC_NAME.value))
            kid.append(name_ref)
        signature = None
        if self.check(Tok.LPAREN.value) or self.check(Tok.RETURN_HINT.value):
            signature = self.parse_func_signature()
            kid.append(signature)
        body = None
        if self.check(Tok.LBRACE.value):
            self.advance()
            kid.append(self.gen_token(Tok.LBRACE.value))
            body = self.parse_code_block()
            kid.extend(body)
            self.expect(Tok.RBRACE.value)
            kid.append(self.gen_token(Tok.RBRACE.value))
        elif self.match(Tok.SEMI.value):
            kid.append(self.make_semi())
        return uni.Ability(
            name_ref=name_ref, is_async=is_async, is_override=is_override,
            is_static=is_static, is_abstract=is_abstract, access=access,
            signature=signature, body=body, kid=kid, doc=doc,
            decorators=decorators or None,
        )

    def parse_func_signature(self):
        """Parse: (params) [-> return_type]"""
        kid: list = []
        params: list = []
        varargs = None
        kwargs = None
        if self.check(Tok.LPAREN.value):
            self.advance()
            kid.append(self.gen_token(Tok.LPAREN.value))
            while not self.check(Tok.RPAREN.value) and not self.at_end():
                if params or varargs or kwargs:
                    self.expect(Tok.COMMA.value)
                    kid.append(self.gen_token(Tok.COMMA.value))
                if self.check(Tok.STAR_MUL.value):
                    star = self._tok(self.advance())
                    if self.check(Tok.NAME.value):
                        nm = self._name(self.advance())
                        pk: list = [star, nm]
                        tt = None
                        if self.check(Tok.COLON.value):
                            c = self._tok(self.advance())
                            tp = self.parse_pipe()
                            tt = uni.SubTag(tag=tp, kid=[c, tp])
                            pk.append(tt)
                        varargs = uni.ParamVar(
                            name=nm, unpack=star,
                            type_tag=tt or uni.SubTag(
                                tag=self.make_empty(), kid=[self.make_empty()]
                            ),
                            value=None, kid=pk,
                        )
                        kid.append(varargs)
                    else:
                        kid.append(star)
                    continue
                if self.check(Tok.STAR_POW.value):
                    star2 = self._tok(self.advance())
                    nm = self._name(self.expect(Tok.NAME.value))
                    pk2: list = [star2, nm]
                    tt2 = None
                    if self.check(Tok.COLON.value):
                        c = self._tok(self.advance())
                        tp = self.parse_pipe()
                        tt2 = uni.SubTag(tag=tp, kid=[c, tp])
                        pk2.append(tt2)
                    kwargs = uni.ParamVar(
                        name=nm, unpack=star2,
                        type_tag=tt2 or uni.SubTag(
                            tag=self.make_empty(), kid=[self.make_empty()]
                        ),
                        value=None, kid=pk2,
                    )
                    kid.append(kwargs)
                    continue
                param = self._parse_param()
                params.append(param)
                kid.append(param)
                if self.check(Tok.COMMA.value) and self.peek().type == Tok.RPAREN.value:
                    self.advance()
                    kid.append(self.gen_token(Tok.COMMA.value))
                    break
            self.expect(Tok.RPAREN.value)
            kid.append(self.gen_token(Tok.RPAREN.value))
        return_type = None
        if self.check(Tok.RETURN_HINT.value):
            self.advance()
            kid.append(self.gen_token(Tok.RETURN_HINT.value))
            return_type = self.parse_pipe()
            kid.append(return_type)
        if not kid:
            kid.append(self.make_empty())
        return uni.FuncSignature(
            posonly_params=[], params=params, varargs=varargs,
            kwonlyargs=[], kwargs=kwargs, return_type=return_type, kid=kid,
        )

    def _parse_param(self):
        """Parse single function parameter: name [: type] [= default]"""
        kid: list = []
        name = self._name(self.expect(Tok.NAME.value))
        kid.append(name)
        type_tag = None
        if self.check(Tok.COLON.value):
            c = self._tok(self.advance())
            tp = self.parse_pipe()
            type_tag = uni.SubTag(tag=tp, kid=[c, tp])
            kid.append(type_tag)
        if type_tag is None:
            type_tag = uni.SubTag(tag=self.make_empty(), kid=[self.make_empty()])
        value = None
        if self.check(Tok.EQ.value):
            self.advance()
            kid.append(self.gen_token(Tok.EQ.value))
            value = self.parse_expression()
            kid.append(value)
        return uni.ParamVar(
            name=name, unpack=None, type_tag=type_tag,
            value=value, kid=kid,
        )

    # =================================================================
    # Enum
    # =================================================================

    def parse_enum(self, doc=None, decorators=None):
        """Parse: enum [access] Name [(bases)] { MEMBER = value, ... }"""
        kid: list = []
        if decorators:
            for d in decorators:
                kid.append(self.gen_token(Tok.DECOR_OP.value))
                kid.append(d)
        self.expect(Tok.KW_ENUM.value)
        kid.append(self.gen_token(Tok.KW_ENUM.value))
        access = self.parse_access_tag()
        if access:
            kid.append(access)
        name = self._name(self.expect(Tok.NAME.value))
        kid.append(name)
        base_classes = None
        if self.check(Tok.LPAREN.value):
            self.advance()
            kid.append(self.gen_token(Tok.LPAREN.value))
            base_classes = []
            while not self.check(Tok.RPAREN.value) and not self.at_end():
                if base_classes:
                    self.expect(Tok.COMMA.value)
                    kid.append(self.gen_token(Tok.COMMA.value))
                base_classes.append(self.parse_expression())
                kid.append(base_classes[-1])
            self.expect(Tok.RPAREN.value)
            kid.append(self.gen_token(Tok.RPAREN.value))
        body = None
        if self.check(Tok.LBRACE.value):
            self.advance()
            kid.append(self.gen_token(Tok.LBRACE.value))
            body = self._parse_enum_body()
            kid.extend(body)
            self.expect(Tok.RBRACE.value)
            kid.append(self.gen_token(Tok.RBRACE.value))
        elif self.match(Tok.SEMI.value):
            kid.append(self.make_semi())
        return uni.Enum(
            name=name, access=access, base_classes=base_classes,
            body=body, kid=kid, doc=doc, decorators=decorators or None,
        )

    def _parse_enum_body(self) -> list:
        """Parse enum body: comma-separated members."""
        members: list = []
        while not self.check(Tok.RBRACE.value) and not self.at_end():
            if self.match(Tok.SEMI.value):
                members.append(self.make_semi())
                continue
            if self.check(Tok.STRING.value) and self.cur().value.startswith(('"""', "'''")):
                self.advance()
                continue
            if self.cur().type == Tok.KW_HAS.value:
                members.append(self.parse_has_stmt())
                continue
            if self.cur().type in (Tok.KW_DEF.value, Tok.KW_CAN.value):
                members.append(self.parse_ability(None, []))
                continue
            if self.check(Tok.NAME.value):
                ntok = self.advance()
                nm = self._name(ntok)
                nm.is_enum_stmt = True
                ekid: list = [nm]
                value = None
                if self.check(Tok.EQ.value):
                    self.advance()
                    ekid.append(self.gen_token(Tok.EQ.value))
                    value = self.parse_expression()
                    ekid.append(value)
                members.append(uni.Assignment(
                    target=[nm], value=value, type_tag=None,
                    kid=ekid, mutable=False, is_enum_stmt=True,
                ))
                if self.match(Tok.COMMA.value):
                    pass
                continue
            break
        return members

    # =================================================================
    # Impl def
    # =================================================================

    def parse_impl_def(self, doc=None, decorators=None):
        """Parse: impl Target.method(params) -> type { body }"""
        kid: list = []
        if decorators:
            for d in decorators:
                kid.append(self.gen_token(Tok.DECOR_OP.value))
                kid.append(d)
        self.expect(Tok.KW_IMPL.value)
        kid.append(self.gen_token(Tok.KW_IMPL.value))
        targets: list = []
        ntok = self.advance()
        nm = self._name(ntok, is_kwesc=(ntok.type == Tok.KWESC_NAME.value))
        targets.append(nm)
        kid.append(nm)
        while self.check(Tok.DOT.value):
            self.advance()
            kid.append(self.gen_token(Tok.DOT.value))
            ntok = self.advance()
            nm = self._name(ntok, is_kwesc=(ntok.type == Tok.KWESC_NAME.value))
            targets.append(nm)
            kid.append(nm)
        spec = None
        if self.check(Tok.LPAREN.value) or self.check(Tok.RETURN_HINT.value):
            spec = self.parse_func_signature()
            kid.append(spec)
        body: list = []
        if self.check(Tok.LBRACE.value):
            self.advance()
            kid.append(self.gen_token(Tok.LBRACE.value))
            body = self.parse_code_block()
            kid.extend(body)
            self.expect(Tok.RBRACE.value)
            kid.append(self.gen_token(Tok.RBRACE.value))
        elif self.match(Tok.SEMI.value):
            kid.append(self.make_semi())
        return uni.ImplDef(
            decorators=decorators or None, target=targets,
            spec=spec, body=body, kid=kid, doc=doc,
        )

    # =================================================================
    # Global variables
    # =================================================================

    def parse_global_var(self, doc=None):
        """Parse: glob [access] name: type = value, ... ;"""
        kid: list = []
        self.expect(Tok.KW_GLOBAL.value)
        kid.append(self.gen_token(Tok.KW_GLOBAL.value))
        is_frozen = False
        access = self.parse_access_tag()
        if access:
            kid.append(access)
        assignments: list = []
        while True:
            if assignments:
                self.expect(Tok.COMMA.value)
                kid.append(self.gen_token(Tok.COMMA.value))
            nm = self._name(self.expect(Tok.NAME.value))
            akid: list = [nm]
            type_tag = None
            if self.check(Tok.COLON.value):
                c = self._tok(self.advance())
                tp = self.parse_pipe()
                type_tag = uni.SubTag(tag=tp, kid=[c, tp])
                akid.append(type_tag)
            value = None
            if self.check(Tok.EQ.value):
                self.advance()
                akid.append(self.gen_token(Tok.EQ.value))
                value = self.parse_expression()
                akid.append(value)
            assignments.append(uni.Assignment(
                target=[nm], value=value, type_tag=type_tag, kid=akid,
            ))
            kid.append(assignments[-1])
            if not self.check(Tok.COMMA.value):
                break
        if self.match(Tok.SEMI.value):
            kid.append(self.make_semi())
        return uni.GlobalVars(
            access=access, assignments=assignments,
            is_frozen=is_frozen, kid=kid, doc=doc,
        )

    # =================================================================
    # Module code (with entry/exit)
    # =================================================================

    def parse_module_code(self, doc=None):
        """Parse: with entry { body }"""
        kid: list = []
        self.expect(Tok.KW_WITH.value)
        kid.append(self.gen_token(Tok.KW_WITH.value))
        nm = self._name(self.advance())
        kid.append(nm)
        if self.check(Tok.COLON.value):
            self.advance()
            kid.append(self.gen_token(Tok.COLON.value))
            kid.append(self._name(self.advance()))
        self.expect(Tok.LBRACE.value)
        kid.append(self.gen_token(Tok.LBRACE.value))
        body = self.parse_code_block()
        kid.extend(body)
        self.expect(Tok.RBRACE.value)
        kid.append(self.gen_token(Tok.RBRACE.value))
        return uni.ModuleCode(name=nm, body=body, kid=kid, doc=doc)

    def parse_test_block(self, doc=None):
        """Parse: test name { body }"""
        kid: list = []
        kid.append(self._tok(self.advance()))
        name_ref = None
        if self.check(Tok.NAME.value, Tok.STRING.value):
            ntok = self.advance()
            if ntok.type == Tok.STRING.value:
                name_ref = self._name(BootstrapToken(
                    type=Tok.NAME.value, value=ntok.value,
                    line=ntok.line, end_line=ntok.end_line,
                    col_start=ntok.col_start, col_end=ntok.col_end,
                    pos_start=ntok.pos_start, pos_end=ntok.pos_end,
                ))
            else:
                name_ref = self._name(ntok)
            kid.append(name_ref)
        body = None
        if self.check(Tok.LBRACE.value):
            self.advance()
            kid.append(self.gen_token(Tok.LBRACE.value))
            body = self.parse_code_block()
            kid.extend(body)
            self.expect(Tok.RBRACE.value)
            kid.append(self.gen_token(Tok.RBRACE.value))
        return uni.Ability(
            name_ref=name_ref, is_async=False, is_override=False,
            is_static=False, is_abstract=False, access=None,
            signature=None, body=body, kid=kid, doc=doc, decorators=None,
        )
    # =================================================================
    # Code block and statement parsing
    # =================================================================

    def parse_code_block(self) -> list:
        """Parse statements until } is found."""
        stmts: list = []
        while not self.check(Tok.RBRACE.value) and not self.at_end():
            stmt = self.parse_statement()
            if stmt is not None:
                stmts.append(stmt)
        return stmts

    def parse_statement(self):
        """Parse a single statement."""
        t = self.cur().type
        if self.match(Tok.SEMI.value):
            return self.make_semi()
        if t == Tok.KW_IF.value:
            return self.parse_if_stmt()
        if t == Tok.KW_WHILE.value:
            return self.parse_while_stmt()
        if t == Tok.KW_FOR.value:
            return self.parse_for_stmt()
        if t == Tok.KW_RETURN.value:
            return self.parse_return_stmt()
        if t == Tok.KW_YIELD.value:
            return self._parse_yield_stmt()
        if t in (Tok.KW_BREAK.value, Tok.KW_CONTINUE.value, Tok.KW_SKIP.value):
            ctrl = self._tok(self.advance())
            kid: list = [ctrl]
            if self.match(Tok.SEMI.value):
                kid.append(self.make_semi())
            return uni.CtrlStmt(ctrl=ctrl, kid=kid)
        if t == Tok.KW_TRY.value:
            return self.parse_try_stmt()
        if t == Tok.KW_WITH.value and self.peek().type not in (
            Tok.KW_ENTRY.value, Tok.KW_EXIT.value
        ):
            return self.parse_with_stmt()
        if t == Tok.KW_RAISE.value:
            return self.parse_raise_stmt()
        if t == Tok.KW_ASSERT.value:
            return self.parse_assert_stmt()
        if t == Tok.KW_DELETE.value:
            return self.parse_delete_stmt()
        if t in (Tok.GLOBAL_OP.value, Tok.NONLOCAL_OP.value):
            return self._parse_scope_stmt()
        if t == Tok.KW_MATCH.value:
            return self.parse_match_stmt()
        return self.parse_assignment_or_expr()

    # =================================================================
    # Match / case
    # =================================================================

    def parse_match_stmt(self):
        """Parse: match expr { case pattern: body ... }"""
        kid: list = []
        self.expect(Tok.KW_MATCH.value)
        kid.append(self.gen_token(Tok.KW_MATCH.value))
        target = self.parse_expression()
        kid.append(target)
        self.expect(Tok.LBRACE.value)
        kid.append(self.gen_token(Tok.LBRACE.value))
        cases: list = []
        while self.check(Tok.KW_CASE.value) and not self.at_end():
            mc = self._parse_match_case()
            cases.append(mc)
            kid.append(mc)
        self.expect(Tok.RBRACE.value)
        kid.append(self.gen_token(Tok.RBRACE.value))
        return uni.MatchStmt(target=target, cases=cases, kid=kid)

    def _parse_match_case(self):
        """Parse: case pattern [if guard]: body_stmts"""
        kid: list = []
        self.expect(Tok.KW_CASE.value)
        kid.append(self.gen_token(Tok.KW_CASE.value))
        pattern = self._parse_match_pattern()
        kid.append(pattern)
        # Optional guard
        guard = None
        if self.check(Tok.KW_IF.value):
            self.advance()
            kid.append(self.gen_token(Tok.KW_IF.value))
            guard = self.parse_expression()
            kid.append(guard)
        self.expect(Tok.COLON.value)
        kid.append(self.gen_token(Tok.COLON.value))
        # Body: statements until next case or }
        body: list = []
        while (
            not self.check(Tok.KW_CASE.value)
            and not self.check(Tok.RBRACE.value)
            and not self.at_end()
        ):
            stmt = self.parse_statement()
            if stmt is not None:
                body.append(stmt)
                kid.append(stmt)
        return uni.MatchCase(pattern=pattern, guard=guard, body=body, kid=kid)

    def _parse_match_pattern(self):
        """Parse a match pattern (simplified for bootstrap subset)."""
        # Wildcard _
        if (
            self.cur().type == Tok.NAME.value
            and self.cur().value == "_"
        ):
            name_node = self._name(self.advance())
            return uni.MatchWild(kid=[name_node])
        # Value pattern: parse expression (handles literals, dotted names, etc.)
        expr = self.parse_expression()
        return uni.MatchValue(value=expr, kid=[expr])

    # =================================================================
    # If / elif / else
    # =================================================================

    def parse_if_stmt(self):
        """Parse: if condition { body } [elif ...] [else { body }]"""
        kid: list = []
        self.expect(Tok.KW_IF.value)
        kid.append(self.gen_token(Tok.KW_IF.value))
        cond = self.parse_expression()
        kid.append(cond)
        self.expect(Tok.LBRACE.value)
        kid.append(self.gen_token(Tok.LBRACE.value))
        body = self.parse_code_block()
        kid.extend(body)
        self.expect(Tok.RBRACE.value)
        kid.append(self.gen_token(Tok.RBRACE.value))
        else_body = self._parse_else_chain()
        if else_body:
            kid.append(else_body)
        return uni.IfStmt(condition=cond, body=body, else_body=else_body, kid=kid)

    def _parse_else_chain(self):
        """Parse optional elif/else chain."""
        if self.check(Tok.KW_ELIF.value):
            return self._parse_elif()
        if self.check(Tok.KW_ELSE.value):
            return self._parse_else()
        return None

    def _parse_elif(self):
        """Parse: elif condition { body } [elif ...] [else { body }]"""
        kid: list = []
        self.expect(Tok.KW_ELIF.value)
        kid.append(self.gen_token(Tok.KW_ELIF.value))
        cond = self.parse_expression()
        kid.append(cond)
        self.expect(Tok.LBRACE.value)
        kid.append(self.gen_token(Tok.LBRACE.value))
        body = self.parse_code_block()
        kid.extend(body)
        self.expect(Tok.RBRACE.value)
        kid.append(self.gen_token(Tok.RBRACE.value))
        else_body = self._parse_else_chain()
        if else_body:
            kid.append(else_body)
        return uni.ElseIf(condition=cond, body=body, else_body=else_body, kid=kid)

    def _parse_else(self):
        """Parse: else { body }"""
        kid: list = []
        self.expect(Tok.KW_ELSE.value)
        kid.append(self.gen_token(Tok.KW_ELSE.value))
        self.expect(Tok.LBRACE.value)
        kid.append(self.gen_token(Tok.LBRACE.value))
        body = self.parse_code_block()
        kid.extend(body)
        self.expect(Tok.RBRACE.value)
        kid.append(self.gen_token(Tok.RBRACE.value))
        return uni.ElseStmt(body=body, kid=kid)

    # =================================================================
    # While statement
    # =================================================================

    def parse_while_stmt(self):
        """Parse: while condition { body } [else { body }]"""
        kid: list = []
        self.expect(Tok.KW_WHILE.value)
        kid.append(self.gen_token(Tok.KW_WHILE.value))
        cond = self.parse_expression()
        kid.append(cond)
        self.expect(Tok.LBRACE.value)
        kid.append(self.gen_token(Tok.LBRACE.value))
        body = self.parse_code_block()
        kid.extend(body)
        self.expect(Tok.RBRACE.value)
        kid.append(self.gen_token(Tok.RBRACE.value))
        else_body = None
        if self.check(Tok.KW_ELSE.value):
            else_body = self._parse_else()
            kid.append(else_body)
        return uni.WhileStmt(
            condition=cond, body=body, else_body=else_body, kid=kid,
        )

    # =================================================================
    # For statement
    # =================================================================

    def parse_for_stmt(self):
        """Parse: for target in collection { body }
                  for i = start to end by step { body }"""
        kid: list = []
        self.expect(Tok.KW_FOR.value)
        kid.append(self.gen_token(Tok.KW_FOR.value))
        target = self.parse_atomic_chain()
        kid.append(target)

        if self.check(Tok.KW_IN.value):
            self.advance()
            kid.append(self.gen_token(Tok.KW_IN.value))
            collection = self.parse_expression()
            kid.append(collection)
            self.expect(Tok.LBRACE.value)
            kid.append(self.gen_token(Tok.LBRACE.value))
            body = self.parse_code_block()
            kid.extend(body)
            self.expect(Tok.RBRACE.value)
            kid.append(self.gen_token(Tok.RBRACE.value))
            else_body = None
            if self.check(Tok.KW_ELSE.value):
                else_body = self._parse_else()
                kid.append(else_body)
            return uni.InForStmt(
                target=target, is_async=False, collection=collection,
                body=body, else_body=else_body, kid=kid,
            )
        elif self.check(Tok.EQ.value):
            self.advance()
            kid.append(self.gen_token(Tok.EQ.value))
            start_val = self.parse_expression()
            kid.append(start_val)
            init_assign = uni.Assignment(
                target=[target], value=start_val, type_tag=None,
                kid=[target, self.gen_token(Tok.EQ.value), start_val],
            )
            self.expect(Tok.KW_TO.value)
            kid.append(self.gen_token(Tok.KW_TO.value))
            end_val = self.parse_expression()
            kid.append(end_val)
            self.expect(Tok.KW_BY.value)
            kid.append(self.gen_token(Tok.KW_BY.value))
            step_target = self.parse_atomic_chain()
            kid.append(step_target)
            aug_tok = self.advance()
            aug_op = self._tok(aug_tok)
            kid.append(aug_op)
            step_val = self.parse_expression()
            kid.append(step_val)
            count_by = uni.Assignment(
                target=[step_target], value=step_val, type_tag=None,
                kid=[step_target, aug_op, step_val], aug_op=aug_op,
            )
            self.expect(Tok.LBRACE.value)
            kid.append(self.gen_token(Tok.LBRACE.value))
            body = self.parse_code_block()
            kid.extend(body)
            self.expect(Tok.RBRACE.value)
            kid.append(self.gen_token(Tok.RBRACE.value))
            else_body = None
            if self.check(Tok.KW_ELSE.value):
                else_body = self._parse_else()
                kid.append(else_body)
            return uni.IterForStmt(
                iter=init_assign, is_async=False, condition=end_val,
                count_by=count_by, body=body, else_body=else_body, kid=kid,
            )
        else:
            raise SyntaxError(
                f"Expected 'in' or '=' in for statement at "
                f"{self.file_path}:{self.cur().line}:{self.cur().col_start}"
            )

    # =================================================================
    # Return / yield
    # =================================================================

    def parse_return_stmt(self):
        """Parse: return [expr] ;"""
        kid: list = []
        self.expect(Tok.KW_RETURN.value)
        kid.append(self.gen_token(Tok.KW_RETURN.value))
        expr = None
        if not self.check(Tok.SEMI.value, Tok.RBRACE.value) and not self.at_end():
            expr = self.parse_expression()
            kid.append(expr)
        if self.match(Tok.SEMI.value):
            kid.append(self.make_semi())
        return uni.ReturnStmt(expr=expr, kid=kid)

    def _parse_yield_stmt(self):
        """Parse: yield [from] [expr] ;"""
        kid: list = []
        self.expect(Tok.KW_YIELD.value)
        kid.append(self.gen_token(Tok.KW_YIELD.value))
        with_from = False
        if self.check(Tok.KW_FROM.value):
            self.advance()
            kid.append(self.gen_token(Tok.KW_FROM.value))
            with_from = True
        expr = None
        if not self.check(Tok.SEMI.value, Tok.RBRACE.value) and not self.at_end():
            expr = self.parse_expression()
            kid.append(expr)
        if self.match(Tok.SEMI.value):
            kid.append(self.make_semi())
        yld = uni.YieldExpr(expr=expr, with_from=with_from, kid=kid)
        return uni.ExprStmt(expr=yld, in_fstring=False, kid=[yld, self.make_semi()])

    # =================================================================
    # Try / except / finally
    # =================================================================

    def parse_try_stmt(self):
        """Parse: try { body } except ExcType [as name] { handler }..."""
        kid: list = []
        self.expect(Tok.KW_TRY.value)
        kid.append(self.gen_token(Tok.KW_TRY.value))
        self.expect(Tok.LBRACE.value)
        kid.append(self.gen_token(Tok.LBRACE.value))
        body = self.parse_code_block()
        kid.extend(body)
        self.expect(Tok.RBRACE.value)
        kid.append(self.gen_token(Tok.RBRACE.value))
        excepts: list = []
        while self.check(Tok.KW_EXCEPT.value):
            exc = self._parse_except()
            excepts.append(exc)
            kid.append(exc)
        else_body = None
        if self.check(Tok.KW_ELSE.value):
            else_body = self._parse_else()
            kid.append(else_body)
        finally_body = None
        if self.check(Tok.KW_FINALLY.value):
            finally_body = self._parse_finally()
            kid.append(finally_body)
        return uni.TryStmt(
            body=body, excepts=excepts, else_body=else_body,
            finally_body=finally_body, kid=kid,
        )

    def _parse_except(self):
        """Parse: except ExcType [as name] { body }"""
        kid: list = []
        self.expect(Tok.KW_EXCEPT.value)
        kid.append(self.gen_token(Tok.KW_EXCEPT.value))
        ex_type = self.parse_expression()
        kid.append(ex_type)
        name = None
        if self.check(Tok.KW_AS.value):
            self.advance()
            kid.append(self.gen_token(Tok.KW_AS.value))
            name = self._name(self.expect(Tok.NAME.value))
            kid.append(name)
        self.expect(Tok.LBRACE.value)
        kid.append(self.gen_token(Tok.LBRACE.value))
        body = self.parse_code_block()
        kid.extend(body)
        self.expect(Tok.RBRACE.value)
        kid.append(self.gen_token(Tok.RBRACE.value))
        return uni.Except(ex_type=ex_type, name=name, body=body, kid=kid)

    def _parse_finally(self):
        """Parse: finally { body }"""
        kid: list = []
        self.expect(Tok.KW_FINALLY.value)
        kid.append(self.gen_token(Tok.KW_FINALLY.value))
        self.expect(Tok.LBRACE.value)
        kid.append(self.gen_token(Tok.LBRACE.value))
        body = self.parse_code_block()
        kid.extend(body)
        self.expect(Tok.RBRACE.value)
        kid.append(self.gen_token(Tok.RBRACE.value))
        return uni.FinallyStmt(body=body, kid=kid)

    # =================================================================
    # With statement
    # =================================================================

    def parse_with_stmt(self):
        """Parse: with expr [as alias], ... { body }"""
        kid: list = []
        self.expect(Tok.KW_WITH.value)
        kid.append(self.gen_token(Tok.KW_WITH.value))
        exprs: list = []
        while True:
            if exprs:
                self.expect(Tok.COMMA.value)
                kid.append(self.gen_token(Tok.COMMA.value))
            expr = self.parse_expression()
            ekid: list = [expr]
            alias = None
            if self.check(Tok.KW_AS.value):
                self.advance()
                ekid.append(self.gen_token(Tok.KW_AS.value))
                alias = self.parse_expression()
                ekid.append(alias)
            exprs.append(uni.ExprAsItem(expr=expr, alias=alias, kid=ekid))
            kid.append(exprs[-1])
            if not self.check(Tok.COMMA.value):
                break
        self.expect(Tok.LBRACE.value)
        kid.append(self.gen_token(Tok.LBRACE.value))
        body = self.parse_code_block()
        kid.extend(body)
        self.expect(Tok.RBRACE.value)
        kid.append(self.gen_token(Tok.RBRACE.value))
        return uni.WithStmt(is_async=False, exprs=exprs, body=body, kid=kid)

    # =================================================================
    # Raise / Assert / Delete
    # =================================================================

    def parse_raise_stmt(self):
        """Parse: raise [expr] [from expr] ;"""
        kid: list = []
        self.expect(Tok.KW_RAISE.value)
        kid.append(self.gen_token(Tok.KW_RAISE.value))
        cause = from_target = None
        if not self.check(Tok.SEMI.value, Tok.RBRACE.value) and not self.at_end():
            cause = self.parse_expression()
            kid.append(cause)
            if self.check(Tok.KW_FROM.value):
                self.advance()
                kid.append(self.gen_token(Tok.KW_FROM.value))
                from_target = self.parse_expression()
                kid.append(from_target)
        if self.match(Tok.SEMI.value):
            kid.append(self.make_semi())
        return uni.RaiseStmt(cause=cause, from_target=from_target, kid=kid)

    def parse_assert_stmt(self):
        """Parse: assert test [, msg] ;"""
        kid: list = []
        self.expect(Tok.KW_ASSERT.value)
        kid.append(self.gen_token(Tok.KW_ASSERT.value))
        cond = self.parse_expression()
        kid.append(cond)
        error_msg = None
        if self.check(Tok.COMMA.value):
            self.advance()
            kid.append(self.gen_token(Tok.COMMA.value))
            error_msg = self.parse_expression()
            kid.append(error_msg)
        if self.match(Tok.SEMI.value):
            kid.append(self.make_semi())
        return uni.AssertStmt(condition=cond, error_msg=error_msg, kid=kid)

    def parse_delete_stmt(self):
        """Parse: del target ;"""
        kid: list = []
        self.expect(Tok.KW_DELETE.value)
        kid.append(self.gen_token(Tok.KW_DELETE.value))
        target = self.parse_expression()
        kid.append(target)
        if self.match(Tok.SEMI.value):
            kid.append(self.make_semi())
        return uni.DeleteStmt(target=target, kid=kid)

    def _parse_scope_stmt(self):
        """Parse: global/nonlocal name1, name2, ... ;"""
        tok = self._tok(self.advance())
        kid: list = [tok]
        while self.check(Tok.NAME.value):
            kid.append(self._name(self.advance()))
            if not self.match(Tok.COMMA.value):
                break
            kid.append(self.gen_token(Tok.COMMA.value))
        if self.match(Tok.SEMI.value):
            kid.append(self.make_semi())
        return uni.ExprStmt(expr=tok, in_fstring=False, kid=kid)

    # =================================================================
    # Assignment or expression statement
    # =================================================================

    def parse_assignment_or_expr(self):
        """Parse assignment or expression statement."""
        expr = self.parse_expression()

        # Type annotation
        type_tag = None
        if self.check(Tok.COLON.value) and not isinstance(
            expr, (uni.FuncCall, uni.IndexSlice)
        ):
            c = self._tok(self.advance())
            tp = self.parse_pipe()
            type_tag = uni.SubTag(tag=tp, kid=[c, tp])

        # Regular assignment
        if self.check(Tok.EQ.value):
            targets = [expr]
            kid: list = [expr]
            if type_tag:
                kid.append(type_tag)
            self.advance()
            kid.append(self.gen_token(Tok.EQ.value))
            value = self.parse_expression()
            while self.check(Tok.EQ.value):
                targets.append(value)
                kid.append(value)
                self.advance()
                kid.append(self.gen_token(Tok.EQ.value))
                value = self.parse_expression()
            kid.append(value)
            if self.match(Tok.SEMI.value):
                kid.append(self.make_semi())
            return uni.Assignment(
                target=targets, value=value, type_tag=type_tag, kid=kid,
            )

        # Augmented assignment
        if self.cur().type in _AUG_ASSIGN_OPS:
            aug_op = self._tok(self.advance())
            value = self.parse_expression()
            kid = [expr]
            if type_tag:
                kid.append(type_tag)
            kid.extend([aug_op, value])
            if self.match(Tok.SEMI.value):
                kid.append(self.make_semi())
            return uni.Assignment(
                target=[expr], value=value, type_tag=type_tag,
                kid=kid, aug_op=aug_op,
            )

        # Walrus — represented as BinaryExpr with WALRUS_EQ op
        if self.check(Tok.WALRUS_EQ.value):
            self.advance()
            op_tok = self.gen_token(Tok.WALRUS_EQ.value)
            value = self.parse_expression()
            kid = [expr, op_tok, value]
            if self.match(Tok.SEMI.value):
                kid.append(self.make_semi())
            return uni.BinaryExpr(
                left=expr, right=value, op=op_tok, kid=kid,
            )

        # Type annotation without assignment
        if type_tag is not None:
            kid = [expr, type_tag]
            if self.match(Tok.SEMI.value):
                kid.append(self.make_semi())
            return uni.Assignment(
                target=[expr], value=None, type_tag=type_tag, kid=kid,
            )

        # Plain expression statement
        kid = [expr]
        if self.match(Tok.SEMI.value):
            kid.append(self.make_semi())
        return uni.ExprStmt(expr=expr, in_fstring=False, kid=kid)
    # =================================================================
    # Expression parsing — Precedence hierarchy
    # =================================================================

    def parse_expression(self):
        """Parse a full expression (top-level)."""
        return self.parse_ternary()

    def parse_pipe(self):
        """Parse type expression (for union types X | Y)."""
        return self.parse_bitor()

    def parse_ternary(self):
        """Parse: value if condition else alt_value"""
        value = self.parse_or_expr()
        if self.check(Tok.KW_IF.value):
            self.advance()
            cond = self.parse_or_expr()
            self.expect(Tok.KW_ELSE.value)
            else_val = self.parse_ternary()
            kid = [value, self.gen_token(Tok.KW_IF.value), cond,
                   self.gen_token(Tok.KW_ELSE.value), else_val]
            return uni.IfElseExpr(
                condition=cond, value=value, else_value=else_val, kid=kid,
            )
        return value

    def parse_or_expr(self):
        """Parse: expr or expr or ..."""
        left = self.parse_and_expr()
        if self.check(Tok.KW_OR.value):
            values = [left]
            kid: list = [left]
            op = None
            while self.check(Tok.KW_OR.value):
                self.advance()
                op_tok = self.gen_token(Tok.KW_OR.value)
                if op is None:
                    op = op_tok
                kid.append(op_tok)
                val = self.parse_and_expr()
                values.append(val)
                kid.append(val)
            return uni.BoolExpr(op=op, values=values, kid=kid)
        return left

    def parse_and_expr(self):
        """Parse: expr and expr and ..."""
        left = self.parse_not_expr()
        if self.check(Tok.KW_AND.value):
            values = [left]
            kid: list = [left]
            op = None
            while self.check(Tok.KW_AND.value):
                self.advance()
                op_tok = self.gen_token(Tok.KW_AND.value)
                if op is None:
                    op = op_tok
                kid.append(op_tok)
                val = self.parse_not_expr()
                values.append(val)
                kid.append(val)
            return uni.BoolExpr(op=op, values=values, kid=kid)
        return left

    def parse_not_expr(self):
        """Parse: not expr"""
        if self.check(Tok.NOT.value):
            op = self._tok(self.advance())
            operand = self.parse_not_expr()
            return uni.UnaryExpr(operand=operand, op=op, kid=[op, operand])
        return self.parse_compare()

    def parse_compare(self):
        """Parse: expr <op> expr <op> expr ..."""
        left = self.parse_bitor()
        if self.cur().type in _COMPARE_OPS:
            ops: list = []
            rights: list = []
            kid: list = [left]
            while self.cur().type in _COMPARE_OPS:
                op = self._tok(self.advance())
                ops.append(op)
                kid.append(op)
                right = self.parse_bitor()
                rights.append(right)
                kid.append(right)
            return uni.CompareExpr(left=left, rights=rights, ops=ops, kid=kid)
        return left

    def parse_bitor(self):
        """Parse: expr | expr"""
        left = self.parse_bitxor()
        while self.check(Tok.BW_OR.value):
            op = self._tok(self.advance())
            right = self.parse_bitxor()
            left = uni.BinaryExpr(
                left=left, right=right, op=op, kid=[left, op, right],
            )
        return left

    def parse_bitxor(self):
        """Parse: expr ^ expr"""
        left = self.parse_bitand()
        while self.check(Tok.BW_XOR.value):
            op = self._tok(self.advance())
            right = self.parse_bitand()
            left = uni.BinaryExpr(
                left=left, right=right, op=op, kid=[left, op, right],
            )
        return left

    def parse_bitand(self):
        """Parse: expr & expr"""
        left = self.parse_shift()
        while self.check(Tok.BW_AND.value):
            op = self._tok(self.advance())
            right = self.parse_shift()
            left = uni.BinaryExpr(
                left=left, right=right, op=op, kid=[left, op, right],
            )
        return left

    def parse_shift(self):
        """Parse: expr << expr, expr >> expr"""
        left = self.parse_arith()
        while self.check(Tok.LSHIFT.value, Tok.RSHIFT.value):
            op = self._tok(self.advance())
            right = self.parse_arith()
            left = uni.BinaryExpr(
                left=left, right=right, op=op, kid=[left, op, right],
            )
        return left

    def parse_arith(self):
        """Parse: expr + expr, expr - expr"""
        left = self.parse_term()
        while self.check(Tok.PLUS.value, Tok.MINUS.value):
            op = self._tok(self.advance())
            right = self.parse_term()
            left = uni.BinaryExpr(
                left=left, right=right, op=op, kid=[left, op, right],
            )
        return left

    def parse_term(self):
        """Parse: expr * expr, expr / expr, expr // expr, expr % expr"""
        left = self.parse_factor()
        while self.check(Tok.STAR_MUL.value, Tok.DIV.value,
                         Tok.FLOOR_DIV.value, Tok.MOD.value):
            op = self._tok(self.advance())
            right = self.parse_factor()
            left = uni.BinaryExpr(
                left=left, right=right, op=op, kid=[left, op, right],
            )
        return left

    def parse_factor(self):
        """Parse unary: +expr, -expr, ~expr"""
        if self.check(Tok.PLUS.value, Tok.MINUS.value, Tok.BW_NOT.value):
            op = self._tok(self.advance())
            operand = self.parse_factor()
            return uni.UnaryExpr(operand=operand, op=op, kid=[op, operand])
        return self.parse_power()

    def parse_power(self):
        """Parse: base ** exponent (right-associative)"""
        base = self.parse_atomic_chain()
        if self.check(Tok.STAR_POW.value):
            op = self._tok(self.advance())
            exp = self.parse_factor()
            return uni.BinaryExpr(
                left=base, right=exp, op=op, kid=[base, op, exp],
            )
        return base

    # =================================================================
    # Atomic chain: atom + trailers
    # =================================================================

    def parse_atomic_chain(self):
        """Parse: atom [.attr | (args) | [index] | ?.attr]"""
        expr = self.parse_atom()
        while True:
            if self.check(Tok.DOT.value):
                self.advance()
                attr_tok = self.advance()
                if attr_tok.type in (Tok.NAME.value, Tok.KWESC_NAME.value):
                    attr = self._name(
                        attr_tok,
                        is_kwesc=(attr_tok.type == Tok.KWESC_NAME.value),
                    )
                elif attr_tok.type in _BUILTIN_TYPE_TOKENS:
                    attr = self._builtin_type(attr_tok)
                elif attr_tok.type in _SPECIAL_VAR_TOKENS:
                    attr = uni.SpecialVarRef(var=self._name(attr_tok))
                else:
                    attr = self._name(attr_tok)
                kid = [expr, self.gen_token(Tok.DOT.value), attr]
                expr = uni.AtomTrailer(
                    target=expr, right=attr, is_attr=True,
                    is_null_ok=False, kid=kid,
                )
                continue

            if self.check(Tok.NULL_OK.value):
                self.advance()  # consume ?
                if self.check(Tok.DOT.value):
                    self.advance()  # consume . after ?
                attr_tok = self.advance()
                attr = self._name(attr_tok)
                kid = [expr, self.gen_token(Tok.NULL_OK.value), attr]
                expr = uni.AtomTrailer(
                    target=expr, right=attr, is_attr=True,
                    is_null_ok=True, kid=kid,
                )
                continue

            if self.check(Tok.LPAREN.value):
                self.advance()
                kid: list = [expr, self.gen_token(Tok.LPAREN.value)]
                args = self._parse_call_args(kid)
                self.expect(Tok.RPAREN.value)
                kid.append(self.gen_token(Tok.RPAREN.value))
                expr = uni.FuncCall(
                    target=expr, params=args, genai_call=None, kid=kid,
                )
                continue

            if self.check(Tok.LSQUARE.value):
                self.advance()
                idx_kid: list = [self.gen_token(Tok.LSQUARE.value)]
                slices, is_range = self._parse_index_slices(idx_kid)
                self.expect(Tok.RSQUARE.value)
                idx_kid.append(self.gen_token(Tok.RSQUARE.value))
                index = uni.IndexSlice(
                    slices=slices, is_range=is_range, kid=idx_kid,
                )
                kid2 = [expr, index]
                expr = uni.AtomTrailer(
                    target=expr, right=index, is_attr=False,
                    is_null_ok=False, kid=kid2,
                )
                continue

            break
        return expr

    def _parse_call_args(self, kid: list) -> list:
        """Parse function call arguments."""
        args: list = []
        while not self.check(Tok.RPAREN.value) and not self.at_end():
            if args:
                self.expect(Tok.COMMA.value)
                kid.append(self.gen_token(Tok.COMMA.value))
            # **kwargs spread
            if self.check(Tok.STAR_POW.value):
                star2 = self._tok(self.advance())
                val = self.parse_expression()
                kw = uni.KWPair(key=None, value=val, kid=[star2, val])
                args.append(kw)
                kid.append(kw)
                continue
            # *args spread
            if self.check(Tok.STAR_MUL.value):
                star = self._tok(self.advance())
                val = self.parse_expression()
                kw = uni.KWPair(key=None, value=val, kid=[star, val])
                args.append(kw)
                kid.append(kw)
                continue
            # keyword argument: name=value
            if (self.check(Tok.NAME.value)
                    and self.peek().type == Tok.EQ.value
                    and self.peek(2).type != Tok.EQ.value):
                nm = self._name(self.advance())
                self.advance()  # consume =
                val = self.parse_expression()
                kw = uni.KWPair(
                    key=nm, value=val,
                    kid=[nm, self.gen_token(Tok.EQ.value), val],
                )
                args.append(kw)
                kid.append(kw)
                continue
            arg = self.parse_expression()
            args.append(arg)
            kid.append(arg)
            # Trailing comma
            if self.check(Tok.COMMA.value) and self.peek().type == Tok.RPAREN.value:
                self.advance()
                kid.append(self.gen_token(Tok.COMMA.value))
                break
        return args

    def _parse_index_slices(self, kid: list):
        """Parse index or slice expressions inside [...]."""
        slices: list = []
        is_range = False
        while not self.check(Tok.RSQUARE.value) and not self.at_end():
            if slices:
                self.expect(Tok.COMMA.value)
                kid.append(self.gen_token(Tok.COMMA.value))
            start = stop = step = None
            if self.check(Tok.COLON.value):
                is_range = True
            else:
                start = self.parse_expression()
                kid.append(start)
            if self.check(Tok.COLON.value):
                is_range = True
                self.advance()
                kid.append(self.gen_token(Tok.COLON.value))
                if not self.check(Tok.COLON.value, Tok.RSQUARE.value, Tok.COMMA.value):
                    stop = self.parse_expression()
                    kid.append(stop)
                if self.check(Tok.COLON.value):
                    self.advance()
                    kid.append(self.gen_token(Tok.COLON.value))
                    if not self.check(Tok.RSQUARE.value, Tok.COMMA.value):
                        step = self.parse_expression()
                        kid.append(step)
            slices.append(uni.IndexSlice.Slice(start=start, stop=stop, step=step))
        return slices, is_range

    # =================================================================
    # Atom parsing
    # =================================================================

    def _is_fstring_start(self) -> bool:
        """Check if current token starts an f-string."""
        return self.cur().type in _FSTRING_START_TOKENS

    def parse_atom(self):
        """Parse an atomic expression."""
        t = self.cur().type

        # Integer literals
        if t in (Tok.INT.value, Tok.HEX.value, Tok.BIN.value, Tok.OCT.value):
            return self._int(self.advance())

        # Float literal
        if t == Tok.FLOAT.value:
            return self._float(self.advance())

        # String literal (with implicit concatenation)
        if t == Tok.STRING.value:
            first = self._string(self.advance())
            if self.check(Tok.STRING.value) or self._is_fstring_start():
                strings: list = [first]
                while self.check(Tok.STRING.value) or self._is_fstring_start():
                    if self.check(Tok.STRING.value):
                        strings.append(self._string(self.advance()))
                    else:
                        strings.append(self.parse_fstring())
                return uni.MultiString(strings=strings, kid=list(strings))
            return first

        # Bool literal
        if t == Tok.BOOL.value:
            return self._bool(self.advance())

        # Null literal
        if t == Tok.NULL.value:
            return self._null(self.advance())

        # Ellipsis
        if t == Tok.ELLIPSIS.value:
            tok = self.advance()
            return uni.Ellipsis(
                orig_src=self.src, name=Tok.ELLIPSIS.value, value="...",
                line=tok.line, end_line=tok.end_line,
                col_start=tok.col_start, col_end=tok.col_end,
                pos_start=tok.pos_start, pos_end=tok.pos_end,
            )

        # Builtin type
        if t in _BUILTIN_TYPE_TOKENS:
            return self._builtin_type(self.advance())

        # Special variables
        if t in _SPECIAL_VAR_TOKENS:
            return uni.SpecialVarRef(var=self._name(self.advance()))

        # Name or keyword-escaped name
        if t in (Tok.NAME.value, Tok.KWESC_NAME.value):
            tok = self.advance()
            return self._name(tok, is_kwesc=(tok.type == Tok.KWESC_NAME.value))

        # Parenthesized expression or tuple
        if t == Tok.LPAREN.value:
            return self._parse_paren_or_tuple()

        # List literal
        if t == Tok.LSQUARE.value:
            return self._parse_list_val()

        # Dict/set literal
        if t == Tok.LBRACE.value:
            return self._parse_dict_or_set()

        # F-string
        if self._is_fstring_start():
            first = self.parse_fstring()
            if self.check(Tok.STRING.value) or self._is_fstring_start():
                strings = [first]
                while self.check(Tok.STRING.value) or self._is_fstring_start():
                    if self.check(Tok.STRING.value):
                        strings.append(self._string(self.advance()))
                    else:
                        strings.append(self.parse_fstring())
                return uni.MultiString(strings=strings, kid=list(strings))
            return first

        # Await
        if t == Tok.KW_AWAIT.value:
            op = self._tok(self.advance())
            operand = self.parse_factor()
            return uni.UnaryExpr(operand=operand, op=op, kid=[op, operand])

        # Lambda
        if t == Tok.KW_LAMBDA.value:
            return self._parse_lambda()

        # PYNLINE (inline Python)
        if t == Tok.PYNLINE.value:
            return self._tok(self.advance())

        # Keywords used as identifiers in expression context (soft keywords)
        if t.startswith("KW_"):
            return self._name(self.advance())

        raise SyntaxError(
            f"Unexpected token {t} ({self.cur().value!r}) at "
            f"{self.file_path}:{self.cur().line}:{self.cur().col_start}"
        )

    # =================================================================
    # Compound atom helpers
    # =================================================================

    def _parse_paren_or_tuple(self):
        """Parse: () | (expr) | (expr, ...) | (name := expr) """
        self.advance()  # consume (
        kid: list = [self.gen_token(Tok.LPAREN.value)]
        if self.check(Tok.RPAREN.value):
            self.advance()
            kid.append(self.gen_token(Tok.RPAREN.value))
            return uni.TupleVal(values=[], kid=kid)
        first = self.parse_expression()
        # Walrus operator inside parens: (name := expr) → BinaryExpr
        if self.check(Tok.WALRUS_EQ.value):
            self.advance()
            op_tok = self.gen_token(Tok.WALRUS_EQ.value)
            value = self.parse_expression()
            walrus_kid = [first, op_tok, value]
            walrus = uni.BinaryExpr(
                left=first, right=value, op=op_tok, kid=walrus_kid,
            )
            kid.append(walrus)
            self.expect(Tok.RPAREN.value)
            kid.append(self.gen_token(Tok.RPAREN.value))
            return uni.AtomUnit(value=walrus, kid=kid)
        if self.check(Tok.COMMA.value):
            # Tuple
            values = [first]
            kid.append(first)
            while self.check(Tok.COMMA.value):
                self.advance()
                kid.append(self.gen_token(Tok.COMMA.value))
                if self.check(Tok.RPAREN.value):
                    break
                values.append(self.parse_expression())
                kid.append(values[-1])
            self.expect(Tok.RPAREN.value)
            kid.append(self.gen_token(Tok.RPAREN.value))
            return uni.TupleVal(values=values, kid=kid)
        # Simple parenthesized expression
        kid.append(first)
        self.expect(Tok.RPAREN.value)
        kid.append(self.gen_token(Tok.RPAREN.value))
        return uni.AtomUnit(value=first, kid=kid)

    def _parse_list_val(self):
        """Parse: [] | [expr, expr, ...]"""
        self.advance()  # consume [
        kid: list = [self.gen_token(Tok.LSQUARE.value)]
        values: list = []
        while not self.check(Tok.RSQUARE.value) and not self.at_end():
            if values:
                self.expect(Tok.COMMA.value)
                kid.append(self.gen_token(Tok.COMMA.value))
            values.append(self.parse_expression())
            kid.append(values[-1])
            # Trailing comma
            if self.check(Tok.COMMA.value) and self.peek().type == Tok.RSQUARE.value:
                self.advance()
                kid.append(self.gen_token(Tok.COMMA.value))
                break
        self.expect(Tok.RSQUARE.value)
        kid.append(self.gen_token(Tok.RSQUARE.value))
        return uni.ListVal(values=values, kid=kid)

    def _parse_dict_or_set(self):
        """Parse: {} | {k: v, ...} | {**spread, ...}"""
        self.advance()  # consume {
        kid: list = [self.gen_token(Tok.LBRACE.value)]
        if self.check(Tok.RBRACE.value):
            self.advance()
            kid.append(self.gen_token(Tok.RBRACE.value))
            return uni.DictVal(kv_pairs=[], kid=kid)

        # Check if this is a dict (has :) or set (no :)
        kv_pairs: list = []
        first_key = None

        # Check for **spread
        if self.check(Tok.STAR_POW.value):
            star2 = self._tok(self.advance())
            val = self.parse_expression()
            kv_pairs.append(uni.KVPair(key=None, value=val, kid=[star2, val]))
            kid.append(kv_pairs[-1])
        else:
            first_expr = self.parse_expression()
            if self.check(Tok.COLON.value):
                # Dict
                self.advance()
                first_key = first_expr
                val = self.parse_expression()
                pkid: list = [first_key, self.gen_token(Tok.COLON.value), val]
                kv_pairs.append(uni.KVPair(key=first_key, value=val, kid=pkid))
                kid.append(kv_pairs[-1])
            else:
                # Could be a set, but we'll treat as dict with key-only for now
                # Actually for the bootstrap subset, we mostly see dict literals
                # Let's just handle it as a set value wrapped in a simple container
                # For bootstrap purposes, sets aren't used — treat as error or fallback
                kid.append(first_expr)
                # Check if it's a single-element expression in braces (set-like)
                values: list = [first_expr]
                while self.check(Tok.COMMA.value):
                    self.advance()
                    kid.append(self.gen_token(Tok.COMMA.value))
                    if self.check(Tok.RBRACE.value):
                        break
                    val = self.parse_expression()
                    values.append(val)
                    kid.append(val)
                self.expect(Tok.RBRACE.value)
                kid.append(self.gen_token(Tok.RBRACE.value))
                # Return as TupleVal (approximation for set in bootstrap)
                return uni.TupleVal(values=values, kid=kid)

        # Continue parsing dict pairs
        while self.check(Tok.COMMA.value):
            self.advance()
            kid.append(self.gen_token(Tok.COMMA.value))
            if self.check(Tok.RBRACE.value):
                break
            if self.check(Tok.STAR_POW.value):
                star2 = self._tok(self.advance())
                val = self.parse_expression()
                kv_pairs.append(
                    uni.KVPair(key=None, value=val, kid=[star2, val])
                )
            else:
                key = self.parse_expression()
                self.expect(Tok.COLON.value)
                val = self.parse_expression()
                pkid2: list = [key, self.gen_token(Tok.COLON.value), val]
                kv_pairs.append(uni.KVPair(key=key, value=val, kid=pkid2))
            kid.append(kv_pairs[-1])

        self.expect(Tok.RBRACE.value)
        kid.append(self.gen_token(Tok.RBRACE.value))
        return uni.DictVal(kv_pairs=kv_pairs, kid=kid)

    # =================================================================
    # F-string parsing
    # =================================================================

    def parse_fstring(self):
        """Parse an f-string: f"text{expr}text" """
        start_tok = self.advance()  # consume F_*_START
        start = self._tok(start_tok)
        parts: list = []
        kid: list = [start]

        while not self.at_end():
            t = self.cur().type
            # F-string end
            if t in _FSTRING_END_TOKENS:
                end_tok = self.advance()
                end = self._tok(end_tok)
                kid.append(end)
                return uni.FString(
                    start=start, parts=parts, end=end, kid=kid,
                )
            # F-string text
            if t in _FSTRING_TEXT_TOKENS:
                text_tok = self.advance()
                s = self._string(text_tok)
                parts.append(s)
                kid.append(s)
                continue
            # Expression opening brace
            if t == Tok.LBRACE.value:
                self.advance()  # consume {
                if self.check(Tok.RBRACE.value):
                    # Empty expression (shouldn't happen but handle gracefully)
                    self.advance()
                    continue
                expr = self.parse_expression()
                # Check for conversion (!r, !s, !a)
                conversion = -1
                if self.cur().type == Tok.NOT.value or (
                    self.cur().value == "!" and self.cur().type == Tok.NAME.value
                ):
                    # Handle !r, !s, !a
                    pass  # Skip for bootstrap — not commonly used in parser source

                # Check for format spec (:...)
                format_spec = None
                if self.check(Tok.COLON.value):
                    self.advance()  # consume :
                    # Collect format spec as text until }
                    if self.check(Tok.RBRACE.value):
                        pass  # empty format spec
                    elif self.cur().type in _FSTRING_TEXT_TOKENS:
                        fmt_tok = self.advance()
                        format_spec = self._string(fmt_tok)
                    else:
                        format_spec = self.parse_expression()

                self.expect(Tok.RBRACE.value)  # consume }
                fv_kid: list = [self.gen_token(Tok.LBRACE.value), expr]
                if format_spec:
                    fv_kid.append(self.gen_token(Tok.COLON.value))
                    fv_kid.append(format_spec)
                fv_kid.append(self.gen_token(Tok.RBRACE.value))
                fv = uni.FormattedValue(
                    format_part=expr, conversion=conversion,
                    format_spec=format_spec, kid=fv_kid,
                )
                parts.append(fv)
                kid.append(fv)
                continue

            # Unexpected token — break out
            break

        # If we get here without finding end, create FString anyway
        return uni.FString(start=start, parts=parts, end=None, kid=kid)

    def _parse_lambda(self):
        """Parse: lambda [params]: expr"""
        self.advance()  # consume lambda
        kid: list = [self.gen_token(Tok.KW_LAMBDA.value)]
        # Parse params (simplified — just names separated by commas)
        params: list = []
        while not self.check(Tok.COLON.value) and not self.at_end():
            if params:
                self.expect(Tok.COMMA.value)
                kid.append(self.gen_token(Tok.COMMA.value))
            param = self._parse_param()
            params.append(param)
            kid.append(param)
        self.expect(Tok.COLON.value)
        kid.append(self.gen_token(Tok.COLON.value))
        body_expr = self.parse_expression()
        kid.append(body_expr)
        sig = uni.FuncSignature(
            posonly_params=[], params=params, varargs=None,
            kwonlyargs=[], kwargs=None, return_type=None,
            kid=[self.make_empty()],
        )
        return uni.LambdaExpr(
            body=body_expr, kid=kid, signature=sig,
        )


# =========================================================================
# Entry point
# =========================================================================


def bootstrap_parse(source_str: str, file_path: str) -> uni.Module:
    """Parse Jac source code and return a unitree Module.

    This is the main entry point for the bootstrap parser.
    """
    lexer = BootstrapLexer(source_str, file_path)
    tokens = lexer.tokenize()
    parser = BootstrapParser(tokens, source_str, file_path)
    return parser.parse()
