"""Jac Bootstrap Seed Compiler (Layer 0).

Direct Jac-subset -> Python AST -> compile() -> bytecode.
No passes. No symbol table. No unitree dependency.

This compiler handles ONLY the restricted Jac subset used by Layer 1
bootstrap files. It is deliberately minimal.
"""

import ast
import marshal
import types
from dataclasses import dataclass
from typing import TypeVar

_T = TypeVar("_T", bound=ast.AST)

# ============================================================================
# Token
# ============================================================================


@dataclass
class Token:
    kind: str
    value: str
    line: int
    col: int

    def __repr__(self) -> str:
        return f"Token({self.kind}, {self.value!r}, {self.line}:{self.col})"


# ============================================================================
# Keywords and operators
# ============================================================================

KEYWORDS = {
    "obj": "KW_OBJ",
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
}

# Two-char operators (checked first)
TWO_CHAR_OPS = {
    "==": "EQEQ",
    "!=": "NEQ",
    "<=": "LTE",
    ">=": "GTE",
    "+=": "PLUS_EQ",
    "-=": "MINUS_EQ",
    "*=": "STAR_EQ",
    "/=": "SLASH_EQ",
    "//": "DSLASH",
    "->": "ARROW",
}

# Single-char operators
SINGLE_CHAR_OPS = {
    "(": "LPAREN",
    ")": "RPAREN",
    "[": "LBRACKET",
    "]": "RBRACKET",
    "{": "LBRACE",
    "}": "RBRACE",
    ",": "COMMA",
    ":": "COLON",
    ";": "SEMI",
    ".": "DOT",
    "=": "EQ",
    "+": "PLUS",
    "-": "MINUS",
    "*": "STAR",
    "/": "SLASH",
    "%": "PERCENT",
    "<": "LT",
    ">": "GT",
    "|": "PIPE",
    "@": "AT",
}


# ============================================================================
# Lexer
# ============================================================================


class Lexer:
    """Tokenize the Layer 0 Jac subset."""

    def __init__(self, source: str, filename: str = "<seed>") -> None:
        self.source = source
        self.filename = filename
        self.pos = 0
        self.line = 1
        self.col = 1
        self.tokens: list[Token] = []

    def error(self, msg: str) -> None:
        raise SyntaxError(f"{self.filename}:{self.line}:{self.col}: {msg}")

    def peek(self, offset: int = 0) -> str:
        p = self.pos + offset
        if p < len(self.source):
            return self.source[p]
        return ""

    def advance(self) -> str:
        ch = self.source[self.pos]
        self.pos += 1
        if ch == "\n":
            self.line += 1
            self.col = 1
        else:
            self.col += 1
        return ch

    def skip_whitespace_and_comments(self) -> None:
        while self.pos < len(self.source):
            ch = self.source[self.pos]
            if ch in " \t\r\n":
                self.advance()
            elif ch == "#":
                while self.pos < len(self.source) and self.source[self.pos] != "\n":
                    self.advance()
            elif ch == "/" and self.peek(1) == "*":
                self.advance()  # /
                self.advance()  # *
                while self.pos < len(self.source):
                    if self.source[self.pos] == "*" and self.peek(1) == "/":
                        self.advance()  # *
                        self.advance()  # /
                        break
                    self.advance()
            else:
                break

    def read_string(self, quote: str) -> Token:
        """Read a single or triple-quoted string."""
        start_line, start_col = self.line, self.col
        # Check for triple quote
        triple = False
        if self.peek(1) == quote and self.peek(2) == quote:
            triple = True
            self.advance()  # first quote
            self.advance()  # second quote
            self.advance()  # third quote
            _ = quote * 3  # triple-quoted
        else:
            self.advance()  # opening quote

        chars: list[str] = []
        while self.pos < len(self.source):
            if triple:
                if (
                    self.source[self.pos] == quote
                    and self.peek(1) == quote
                    and self.peek(2) == quote
                ):
                    self.advance()
                    self.advance()
                    self.advance()
                    return Token(
                        "STRING",
                        quote * 3 + "".join(chars) + quote * 3,
                        start_line,
                        start_col,
                    )
            else:
                if self.source[self.pos] == quote:
                    self.advance()
                    return Token(
                        "STRING", quote + "".join(chars) + quote, start_line, start_col
                    )
                if self.source[self.pos] == "\n":
                    self.error("Unterminated string literal")

            if self.source[self.pos] == "\\":
                chars.append(self.advance())  # backslash
                if self.pos < len(self.source):
                    chars.append(self.advance())  # escaped char
            else:
                chars.append(self.advance())

        self.error("Unterminated string literal")
        return Token("EOF", "", self.line, self.col)  # unreachable

    def read_fstring(self, quote: str) -> Token:
        """Read an f-string as a single FSTRING token."""
        start_line, start_col = self.line, self.col
        self.advance()  # skip 'f'
        self.advance()  # skip opening quote
        chars: list[str] = ["f", quote]
        depth = 0
        while self.pos < len(self.source):
            ch = self.source[self.pos]
            if ch == "{" and self.peek(1) == "{" or ch == "}" and self.peek(1) == "}":
                chars.append(self.advance())
                chars.append(self.advance())
            elif ch == "{":
                depth += 1
                chars.append(self.advance())
            elif ch == "}":
                depth -= 1
                chars.append(self.advance())
            elif ch == quote and depth == 0:
                chars.append(self.advance())
                return Token("FSTRING", "".join(chars), start_line, start_col)
            elif ch == "\\":
                chars.append(self.advance())
                if self.pos < len(self.source):
                    chars.append(self.advance())
            elif ch == "\n":
                self.error("Unterminated f-string")
            else:
                chars.append(self.advance())
        self.error("Unterminated f-string")
        return Token("EOF", "", self.line, self.col)

    def read_number(self) -> Token:
        start_line, start_col = self.line, self.col
        chars: list[str] = []
        is_float = False
        while self.pos < len(self.source) and (
            self.source[self.pos].isdigit() or self.source[self.pos] == "_"
        ):
            chars.append(self.advance())
        if self.pos < len(self.source) and self.source[self.pos] == ".":
            nxt = self.peek(1)
            if nxt.isdigit():
                is_float = True
                chars.append(self.advance())  # dot
                while self.pos < len(self.source) and (
                    self.source[self.pos].isdigit() or self.source[self.pos] == "_"
                ):
                    chars.append(self.advance())
        val = "".join(chars)
        kind = "FLOAT" if is_float else "INT"
        return Token(kind, val, start_line, start_col)

    def read_name(self) -> Token:
        start_line, start_col = self.line, self.col
        chars: list[str] = []
        while self.pos < len(self.source) and (
            self.source[self.pos].isalnum() or self.source[self.pos] == "_"
        ):
            chars.append(self.advance())
        val = "".join(chars)
        kind = KEYWORDS.get(val, "NAME")
        return Token(kind, val, start_line, start_col)

    def tokenize(self) -> list[Token]:
        """Tokenize the full source and return token list."""
        while True:
            self.skip_whitespace_and_comments()
            if self.pos >= len(self.source):
                self.tokens.append(Token("EOF", "", self.line, self.col))
                break

            ch = self.source[self.pos]
            start_line, start_col = self.line, self.col

            # F-strings
            if (
                ch == "f"
                and self.pos + 1 < len(self.source)
                and self.source[self.pos + 1] in ('"', "'")
            ):
                self.tokens.append(self.read_fstring(self.source[self.pos + 1]))
                continue

            # Strings
            if ch in ('"', "'"):
                self.tokens.append(self.read_string(ch))
                continue

            # Numbers
            if ch.isdigit():
                self.tokens.append(self.read_number())
                continue

            # Names and keywords
            if ch.isalpha() or ch == "_":
                self.tokens.append(self.read_name())
                continue

            # Two-char operators
            two = self.source[self.pos : self.pos + 2]
            if two in TWO_CHAR_OPS:
                self.advance()
                self.advance()
                self.tokens.append(Token(TWO_CHAR_OPS[two], two, start_line, start_col))
                continue

            # Single-char operators
            if ch in SINGLE_CHAR_OPS:
                self.advance()
                self.tokens.append(
                    Token(SINGLE_CHAR_OPS[ch], ch, start_line, start_col)
                )
                continue

            self.error(f"Unexpected character: {ch!r}")

        return self.tokens


# ============================================================================
# SeedCompiler — Parser + Python AST emitter
# ============================================================================


class SeedCompiler:
    """Parse Layer 0 Jac subset and emit Python ast nodes directly."""

    def __init__(self, filename: str = "<seed>") -> None:
        self.filename = filename
        self.tokens: list[Token] = []
        self.pos = 0
        self._in_class = False  # True when parsing methods inside obj body

    # ── Token helpers ──────────────────────────────────────────────────

    def error(self, msg: str) -> None:
        tok = self.current()
        raise SyntaxError(
            f"{self.filename}:{tok.line}:{tok.col}: {msg} (got {tok.kind} {tok.value!r})"
        )

    def current(self) -> Token:
        if self.pos < len(self.tokens):
            return self.tokens[self.pos]
        return Token("EOF", "", 0, 0)

    def at_end(self) -> bool:
        return self.current().kind == "EOF"

    def check(self, kind: str) -> bool:
        return self.current().kind == kind

    def check_value(self, kind: str, value: str) -> bool:
        t = self.current()
        return t.kind == kind and t.value == value

    def advance(self) -> Token:
        tok = self.current()
        self.pos += 1
        return tok

    def expect(self, kind: str) -> Token:
        tok = self.current()
        if tok.kind != kind:
            self.error(f"Expected {kind}")
        self.pos += 1
        return tok

    def expect_value(self, kind: str, value: str) -> Token:
        tok = self.current()
        if tok.kind != kind or tok.value != value:
            self.error(f"Expected {kind} {value!r}")
        self.pos += 1
        return tok

    def match(self, kind: str) -> Token | None:
        if self.current().kind == kind:
            return self.advance()
        return None

    def match_value(self, kind: str, value: str) -> Token | None:
        t = self.current()
        if t.kind == kind and t.value == value:
            return self.advance()
        return None

    def _loc(self, node: _T, tok: Token | None = None) -> _T:
        """Set line/col on an AST node."""
        if tok:
            node.lineno = tok.line  # type: ignore[attr-defined]
            node.col_offset = tok.col - 1  # type: ignore[attr-defined]
        else:
            node.lineno = 1  # type: ignore[attr-defined]
            node.col_offset = 0  # type: ignore[attr-defined]
        node.end_lineno = getattr(node, "lineno", 1)  # type: ignore[attr-defined]
        node.end_col_offset = getattr(node, "col_offset", 0)  # type: ignore[attr-defined]
        return node

    # ── Entry point ────────────────────────────────────────────────────

    def compile_module(self, source: str, filename: str = "<seed>") -> types.CodeType:
        """Compile Jac source to Python code object."""
        self.filename = filename
        lexer = Lexer(source, filename)
        self.tokens = lexer.tokenize()
        self.pos = 0
        body = self._parse_module_body()
        # Prepend runtime imports
        body.insert(0, self._future_annotations())
        body.insert(1, self._jaclib_import())
        body.insert(2, self._enum_import())
        mod = ast.Module(body=body, type_ignores=[])
        ast.fix_missing_locations(mod)
        return compile(mod, filename, "exec")

    def compile_to_bytecode(self, source: str, filename: str = "<seed>") -> bytes:
        """Compile Jac source to marshalled bytecode bytes."""
        code = self.compile_module(source, filename)
        return marshal.dumps(code)

    def _future_annotations(self) -> ast.stmt:
        """from __future__ import annotations"""
        return self._loc(
            ast.ImportFrom(
                module="__future__",
                names=[ast.alias(name="annotations")],
                level=0,
            )
        )

    def _jaclib_import(self) -> ast.stmt:
        """from jaclang.pycore.jaclib import Obj, field"""
        return self._loc(
            ast.ImportFrom(
                module="jaclang.pycore.jaclib",
                names=[ast.alias(name="Obj"), ast.alias(name="field")],
                level=0,
            )
        )

    def _enum_import(self) -> ast.stmt:
        """from enum import Enum"""
        return self._loc(
            ast.ImportFrom(
                module="enum",
                names=[ast.alias(name="Enum")],
                level=0,
            )
        )

    # ── Module body ────────────────────────────────────────────────────

    def _parse_module_body(self) -> list[ast.stmt]:
        stmts: list[ast.stmt] = []
        while not self.at_end():
            if self.check("KW_OBJ"):
                stmts.extend(self._parse_obj())
            elif self.check("KW_ENUM"):
                stmts.append(self._parse_enum())
            elif self.check("KW_IMPL"):
                stmts.extend(self._parse_impl())
            elif self.check("KW_DEF") or self.check("KW_CAN"):
                stmts.append(self._parse_function(is_method=False))
            elif self.check("KW_GLOB"):
                stmts.extend(self._parse_glob())
            elif self.check("KW_IMPORT"):
                stmts.append(self._parse_import())
            else:
                stmts.append(self._parse_stmt())
        return stmts

    # ── obj declaration ────────────────────────────────────────────────

    def _parse_obj(self) -> list[ast.stmt]:
        """Parse obj declaration.

        obj Foo(Bar) { has x: int = 0; }
        -> class Foo(Bar, Obj): x: int = 0
        """
        tok = self.expect("KW_OBJ")
        name = self.expect("NAME").value
        bases: list[ast.expr] = []
        if self.match("LPAREN"):
            bases.append(self._parse_dotted_name_expr())
            self.expect("RPAREN")
        # Always add Obj as base
        bases.append(self._loc(ast.Name(id="Obj", ctx=ast.Load()), tok))
        self.expect("LBRACE")
        self._in_class = True
        body = self._parse_class_body()
        self._in_class = False
        self.expect("RBRACE")
        if not body:
            body = [self._loc(ast.Pass(), tok)]
        return [
            self._loc(
                ast.ClassDef(
                    name=name,
                    bases=bases,
                    keywords=[],
                    body=body,
                    decorator_list=[],
                    type_params=[],
                ),
                tok,
            )
        ]

    def _parse_class_body(self) -> list[ast.stmt]:
        """Parse body of an obj: has fields and method definitions."""
        stmts: list[ast.stmt] = []
        while not self.check("RBRACE") and not self.at_end():
            if self.check("KW_HAS"):
                stmts.extend(self._parse_has())
            elif self.check("KW_DEF") or self.check("KW_CAN"):
                stmts.append(self._parse_function(is_method=True))
            else:
                self.error("Expected 'has', 'def', or 'can' inside obj body")
        return stmts

    def _parse_has(self) -> list[ast.stmt]:
        """Parse has field declarations.

        has x: int = 0, y: str = "";
        Mutable defaults ([]{}) get wrapped in field(factory=lambda: ...).
        """
        self.expect("KW_HAS")
        fields: list[ast.stmt] = []
        while True:
            fname_tok = self.expect("NAME")
            fname = fname_tok.value
            self.expect("COLON")
            ftype = self._parse_type_expr()
            default = None
            if self.match("EQ"):
                default = self._parse_expr()
                # Wrap mutable defaults
                if self._is_mutable_literal(default):
                    default = self._wrap_mutable_default(default)
            ann = self._loc(
                ast.AnnAssign(
                    target=self._loc(ast.Name(id=fname, ctx=ast.Store()), fname_tok),
                    annotation=ftype,
                    value=default,
                    simple=1,
                ),
                fname_tok,
            )
            fields.append(ann)
            if not self.match("COMMA"):
                break
        self.expect("SEMI")
        return fields

    def _is_mutable_literal(self, node: ast.expr) -> bool:
        """Check if an AST node is a mutable literal (list, dict, set)."""
        return isinstance(node, (ast.List, ast.Dict, ast.Set))

    def _wrap_mutable_default(self, node: ast.expr) -> ast.expr:
        """Wrap mutable default: [] -> field(factory=lambda: [])"""
        return self._loc(
            ast.Call(
                func=self._loc(ast.Name(id="field", ctx=ast.Load())),
                args=[],
                keywords=[
                    ast.keyword(
                        arg="factory",
                        value=self._loc(
                            ast.Lambda(
                                args=ast.arguments(
                                    posonlyargs=[],
                                    args=[],
                                    vararg=None,
                                    kwonlyargs=[],
                                    kw_defaults=[],
                                    kwarg=None,
                                    defaults=[],
                                ),
                                body=node,
                            )
                        ),
                    )
                ],
            )
        )

    # ── enum declaration ───────────────────────────────────────────────

    def _parse_enum(self) -> ast.stmt:
        """Parse enum declaration.

        enum Color { RED = "red", BLUE = "blue" }
        -> class Color(Enum): RED = "red"; BLUE = "blue"
        """
        tok = self.expect("KW_ENUM")
        name = self.expect("NAME").value
        self.expect("LBRACE")
        body: list[ast.stmt] = []
        while not self.check("RBRACE") and not self.at_end():
            member_tok = self.expect("NAME")
            member_name = member_tok.value
            if self.match("EQ"):
                val = self._parse_expr()
            else:
                val = self._loc(
                    ast.Call(
                        func=self._loc(
                            ast.Attribute(
                                value=self._loc(ast.Name(id="_auto", ctx=ast.Load())),
                                attr="auto",
                                ctx=ast.Load(),
                            )
                        ),
                        args=[],
                        keywords=[],
                    )
                )
            body.append(
                self._loc(
                    ast.Assign(
                        targets=[
                            self._loc(
                                ast.Name(id=member_name, ctx=ast.Store()), member_tok
                            )
                        ],
                        value=val,
                    ),
                    member_tok,
                )
            )
            self.match("COMMA")  # trailing comma optional
        self.expect("RBRACE")
        if not body:
            body = [self._loc(ast.Pass(), tok)]
        return self._loc(
            ast.ClassDef(
                name=name,
                bases=[self._loc(ast.Name(id="Enum", ctx=ast.Load()), tok)],
                keywords=[],
                body=body,
                decorator_list=[],
                type_params=[],
            ),
            tok,
        )

    # ── impl block ─────────────────────────────────────────────────────

    def _parse_impl(self) -> list[ast.stmt]:
        """Parse impl block using post-hoc injection.

        Two forms supported:
        1. impl Foo { can bar(x: int) -> int { ... } }
           -> def _impl_Foo_bar(self, x: int) -> int: ...
              Foo.bar = _impl_Foo_bar

        2. impl Foo.bar(x: int) -> int { ... }
           -> def _impl_Foo_bar(self, x: int) -> int: ...
              Foo.bar = _impl_Foo_bar
        """
        tok = self.expect("KW_IMPL")

        # Parse target name (could be dotted: Foo or Foo.bar)
        target = self.expect("NAME").value

        # Check for Foo.method_name form (single-method impl)
        if self.check("DOT"):
            self.advance()
            method_name = self.expect("NAME").value
            return self._parse_single_impl_method(target, method_name, tok)

        # Block form: impl Foo { ... }
        self.expect("LBRACE")
        stmts: list[ast.stmt] = []
        while not self.check("RBRACE") and not self.at_end():
            if self.check("KW_DEF") or self.check("KW_CAN"):
                func = self._parse_function(is_method=True)
                method_name = func.name
                mangled = f"_impl_{target}_{method_name}"
                func.name = mangled
                stmts.append(func)
                # Foo.bar = _impl_Foo_bar
                stmts.append(
                    self._loc(
                        ast.Assign(
                            targets=[
                                self._loc(
                                    ast.Attribute(
                                        value=self._loc(
                                            ast.Name(id=target, ctx=ast.Load()), tok
                                        ),
                                        attr=method_name,
                                        ctx=ast.Store(),
                                    ),
                                    tok,
                                )
                            ],
                            value=self._loc(ast.Name(id=mangled, ctx=ast.Load()), tok),
                        ),
                        tok,
                    )
                )
            else:
                self.error("Expected 'def' or 'can' inside impl block")
        self.expect("RBRACE")
        return stmts

    def _parse_single_impl_method(
        self, target: str, method_name: str, tok: Token
    ) -> list[ast.stmt]:
        """Parse impl Foo.bar(...) -> Type { body }"""
        self.expect("LPAREN")
        params = self._parse_params(is_method=True)
        self.expect("RPAREN")
        returns = None
        if self.match("ARROW"):
            returns = self._parse_type_expr()
        self.expect("LBRACE")
        body = self._parse_block()
        self.expect("RBRACE")
        if not body:
            body = [self._loc(ast.Pass(), tok)]
        mangled = f"_impl_{target}_{method_name}"
        func = self._loc(
            ast.FunctionDef(
                name=mangled,
                args=params,
                body=body,
                decorator_list=[],
                returns=returns,
                type_params=[],
            ),
            tok,
        )
        assign = self._loc(
            ast.Assign(
                targets=[
                    self._loc(
                        ast.Attribute(
                            value=self._loc(ast.Name(id=target, ctx=ast.Load()), tok),
                            attr=method_name,
                            ctx=ast.Store(),
                        ),
                        tok,
                    )
                ],
                value=self._loc(ast.Name(id=mangled, ctx=ast.Load()), tok),
            ),
            tok,
        )
        return [func, assign]

    # ── function/method definition ─────────────────────────────────────

    def _parse_function(self, is_method: bool = False) -> ast.FunctionDef:
        """Parse def/can function.

        def foo(x: int) -> str { body }
        -> def foo(self?, x: int) -> str: body
        """
        tok = self.advance()  # KW_DEF or KW_CAN
        name = self.expect("NAME").value
        self.expect("LPAREN")
        params = self._parse_params(is_method=is_method)
        self.expect("RPAREN")
        returns = None
        if self.match("ARROW"):
            returns = self._parse_type_expr()

        # Abstract method (semicolon instead of body)
        if self.match("SEMI"):
            body: list[ast.stmt] = [
                self._loc(
                    ast.Expr(
                        value=self._loc(ast.Constant(value=...), tok),
                    ),
                    tok,
                )
            ]
        else:
            self.expect("LBRACE")
            body = self._parse_block()
            self.expect("RBRACE")
            if not body:
                body = [self._loc(ast.Pass(), tok)]

        return self._loc(
            ast.FunctionDef(
                name=name,
                args=params,
                body=body,
                decorator_list=[],
                returns=returns,
                type_params=[],
            ),
            tok,
        )

    def _parse_params(self, is_method: bool = False) -> ast.arguments:
        """Parse function parameters. Auto-adds self for methods."""
        args: list[ast.arg] = []
        defaults: list[ast.expr] = []

        # Check if first param is explicitly 'self'
        has_explicit_self = False
        if is_method and self.check("KW_SELF"):
            has_explicit_self = True
            tok = self.advance()
            args.append(self._loc(ast.arg(arg="self", annotation=None), tok))
            if self.check("COMMA"):
                self.advance()

        if is_method and not has_explicit_self:
            args.append(ast.arg(arg="self", annotation=None))

        while not self.check("RPAREN") and not self.at_end():
            pname_tok = self.expect("NAME")
            annotation = None
            if self.match("COLON"):
                annotation = self._parse_type_expr()
            arg_node = self._loc(
                ast.arg(arg=pname_tok.value, annotation=annotation), pname_tok
            )
            default = None
            if self.match("EQ"):
                default = self._parse_expr()
            args.append(arg_node)
            if default is not None:
                defaults.append(default)
            if not self.match("COMMA"):
                break

        return ast.arguments(
            posonlyargs=[],
            args=args,
            vararg=None,
            kwonlyargs=[],
            kw_defaults=[],
            kwarg=None,
            defaults=defaults,
        )

    # ── import statement ───────────────────────────────────────────────

    def _parse_import(self) -> ast.stmt:
        """Parse import statement.

        import from foo.bar { Baz, Quux as Q }
        -> from foo.bar import Baz, Quux as Q

        import foo.bar;
        -> import foo.bar
        """
        tok = self.expect("KW_IMPORT")

        if self.match("KW_FROM"):
            # import from dotted.path { names }
            module = self._parse_dotted_name()
            self.expect("LBRACE")
            names: list[ast.alias] = []
            while not self.check("RBRACE") and not self.at_end():
                n = self.expect("NAME").value
                alias = None
                if self.match("KW_AS"):
                    alias = self.expect("NAME").value
                names.append(ast.alias(name=n, asname=alias))
                self.match("COMMA")
            self.expect("RBRACE")
            return self._loc(
                ast.ImportFrom(
                    module=module,
                    names=names,
                    level=0,
                ),
                tok,
            )
        else:
            # import foo.bar;
            module = self._parse_dotted_name()
            self.expect("SEMI")
            return self._loc(
                ast.Import(
                    names=[ast.alias(name=module, asname=None)],
                ),
                tok,
            )

    # ── glob declaration ───────────────────────────────────────────────

    def _parse_glob(self) -> list[ast.stmt]:
        """Parse glob declaration.

        glob x: int = 5;
        -> x: int = 5

        glob x = expr;
        -> x = expr
        """
        self.expect("KW_GLOB")
        stmts: list[ast.stmt] = []
        while True:
            name_tok = self.expect("NAME")
            name = name_tok.value
            if self.match("COLON"):
                type_ann = self._parse_type_expr()
                self.expect("EQ")
                value = self._parse_expr()
                stmts.append(
                    self._loc(
                        ast.AnnAssign(
                            target=self._loc(
                                ast.Name(id=name, ctx=ast.Store()), name_tok
                            ),
                            annotation=type_ann,
                            value=value,
                            simple=1,
                        ),
                        name_tok,
                    )
                )
            elif self.match("EQ"):
                value = self._parse_expr()
                stmts.append(
                    self._loc(
                        ast.Assign(
                            targets=[
                                self._loc(ast.Name(id=name, ctx=ast.Store()), name_tok)
                            ],
                            value=value,
                        ),
                        name_tok,
                    )
                )
            else:
                self.error("Expected ':' or '=' after glob name")
            if not self.match("COMMA"):
                break
        self.expect("SEMI")
        return stmts

    # ── Statement parsing ──────────────────────────────────────────────

    def _parse_block(self) -> list[ast.stmt]:
        """Parse a block of statements until RBRACE."""
        stmts: list[ast.stmt] = []
        while not self.check("RBRACE") and not self.at_end():
            stmts.append(self._parse_stmt())
        return stmts

    def _parse_stmt(self) -> ast.stmt:
        """Parse a single statement."""
        if self.check("KW_IF"):
            return self._parse_if()
        if self.check("KW_WHILE"):
            return self._parse_while()
        if self.check("KW_FOR"):
            return self._parse_for()
        if self.check("KW_RETURN"):
            return self._parse_return()
        if self.check("KW_BREAK"):
            tok = self.advance()
            self.expect("SEMI")
            return self._loc(ast.Break(), tok)
        if self.check("KW_CONTINUE"):
            tok = self.advance()
            self.expect("SEMI")
            return self._loc(ast.Continue(), tok)
        return self._parse_expr_or_assign()

    def _parse_if(self) -> ast.stmt:
        """Parse if/elif/else."""
        tok = self.expect("KW_IF")
        test = self._parse_expr()
        self.expect("LBRACE")
        body = self._parse_block()
        self.expect("RBRACE")
        orelse: list[ast.stmt] = []
        if self.match("KW_ELIF"):
            # Push back and parse as if
            self.pos -= 1
            # Change the token kind to KW_IF for recursive parsing
            saved = self.tokens[self.pos]
            self.tokens[self.pos] = Token("KW_IF", "if", saved.line, saved.col)
            orelse = [self._parse_if()]
            self.tokens[self.pos - 1] = saved  # won't matter, already consumed
        elif self.match("KW_ELSE"):
            self.expect("LBRACE")
            orelse = self._parse_block()
            self.expect("RBRACE")
        if not body:
            body = [self._loc(ast.Pass(), tok)]
        return self._loc(ast.If(test=test, body=body, orelse=orelse), tok)

    def _parse_while(self) -> ast.stmt:
        """Parse while loop."""
        tok = self.expect("KW_WHILE")
        test = self._parse_expr()
        self.expect("LBRACE")
        body = self._parse_block()
        self.expect("RBRACE")
        if not body:
            body = [self._loc(ast.Pass(), tok)]
        return self._loc(ast.While(test=test, body=body, orelse=[]), tok)

    def _parse_for(self) -> ast.stmt:
        """Parse for loop.

        for x in expr { body }
        for (a, b) in expr { body }
        """
        tok = self.expect("KW_FOR")
        # Parse target - could be name or tuple (a, b)
        if self.match("LPAREN"):
            targets: list[ast.expr] = []
            while not self.check("RPAREN") and not self.at_end():
                t = self.expect("NAME")
                targets.append(self._loc(ast.Name(id=t.value, ctx=ast.Store()), t))
                self.match("COMMA")
            self.expect("RPAREN")
            target: ast.expr = self._loc(ast.Tuple(elts=targets, ctx=ast.Store()), tok)
        else:
            t = self.expect("NAME")
            target = self._loc(ast.Name(id=t.value, ctx=ast.Store()), t)

        self.expect("KW_IN")
        iter_expr = self._parse_expr()
        self.expect("LBRACE")
        body = self._parse_block()
        self.expect("RBRACE")
        if not body:
            body = [self._loc(ast.Pass(), tok)]
        return self._loc(
            ast.For(
                target=target,
                iter=iter_expr,
                body=body,
                orelse=[],
            ),
            tok,
        )

    def _parse_return(self) -> ast.stmt:
        tok = self.expect("KW_RETURN")
        value = None
        if not self.check("SEMI"):
            value = self._parse_expr()
        self.expect("SEMI")
        return self._loc(ast.Return(value=value), tok)

    def _parse_expr_or_assign(self) -> ast.stmt:
        """Parse expression statement, assignment, or augmented assignment."""
        tok = self.current()
        expr = self._parse_expr()

        # Type-annotated assignment: name: Type = expr;
        if self.check("COLON") and isinstance(expr, ast.Name):
            self.advance()  # :
            type_ann = self._parse_type_expr()
            value = None
            if self.match("EQ"):
                value = self._parse_expr()
            self.expect("SEMI")
            return self._loc(
                ast.AnnAssign(
                    target=self._loc(ast.Name(id=expr.id, ctx=ast.Store()), tok),
                    annotation=type_ann,
                    value=value,
                    simple=1,
                ),
                tok,
            )

        # Simple assignment: target = expr;
        if self.match("EQ"):
            value = self._parse_expr()
            self.expect("SEMI")
            target = self._convert_to_store(expr)
            return self._loc(
                ast.Assign(
                    targets=[target],
                    value=value,
                ),
                tok,
            )

        # Augmented assignment: x += 1, x -= 1, etc.
        aug_ops = {
            "PLUS_EQ": ast.Add(),
            "MINUS_EQ": ast.Sub(),
            "STAR_EQ": ast.Mult(),
            "SLASH_EQ": ast.Div(),
        }
        for tok_kind, op in aug_ops.items():
            if self.match(tok_kind):
                value = self._parse_expr()
                self.expect("SEMI")
                target = self._convert_to_store(expr)
                return self._loc(
                    ast.AugAssign(
                        target=target,  # type: ignore[arg-type]
                        op=op,
                        value=value,
                    ),
                    tok,
                )

        # Expression statement
        self.expect("SEMI")
        return self._loc(ast.Expr(value=expr), tok)

    def _convert_to_store(self, node: ast.expr) -> ast.expr:
        """Convert a Load-context expr to Store-context for assignment."""
        if isinstance(node, (ast.Name, ast.Attribute, ast.Subscript)):
            node.ctx = ast.Store()
        elif isinstance(node, ast.Tuple):
            node.ctx = ast.Store()
            for elt in node.elts:
                self._convert_to_store(elt)
        return node

    # ── Expression parsing (precedence climbing) ──────────────────────

    def _parse_expr(self) -> ast.expr:
        return self._parse_ternary()

    def _parse_ternary(self) -> ast.expr:
        """a if cond else b"""
        expr = self._parse_or()
        if self.match("KW_IF"):
            test = self._parse_or()
            self.expect("KW_ELSE")
            orelse = self._parse_ternary()
            return self._loc(ast.IfExp(test=test, body=expr, orelse=orelse))
        return expr

    def _parse_or(self) -> ast.expr:
        left = self._parse_and()
        while self.match("KW_OR"):
            right = self._parse_and()
            left = self._loc(ast.BoolOp(op=ast.Or(), values=[left, right]))
        return left

    def _parse_and(self) -> ast.expr:
        left = self._parse_not()
        while self.match("KW_AND"):
            right = self._parse_not()
            left = self._loc(ast.BoolOp(op=ast.And(), values=[left, right]))
        return left

    def _parse_not(self) -> ast.expr:
        if self.match("KW_NOT"):
            operand = self._parse_not()
            return self._loc(ast.UnaryOp(op=ast.Not(), operand=operand))
        return self._parse_comparison()

    def _parse_comparison(self) -> ast.expr:
        """Chained comparisons: a < b <= c"""
        left = self._parse_addition()
        ops: list[ast.cmpop] = []
        comparators: list[ast.expr] = []

        while True:
            op = self._match_cmp_op()
            if op is None:
                break
            ops.append(op)
            comparators.append(self._parse_addition())

        if ops:
            return self._loc(
                ast.Compare(
                    left=left,
                    ops=ops,
                    comparators=comparators,
                )
            )
        return left

    def _match_cmp_op(self) -> ast.cmpop | None:
        if self.match("EQEQ"):
            return ast.Eq()
        if self.match("NEQ"):
            return ast.NotEq()
        if self.match("LTE"):
            return ast.LtE()
        if self.match("GTE"):
            return ast.GtE()
        if self.match("LT"):
            return ast.Lt()
        if self.match("GT"):
            return ast.Gt()
        if (
            self.check("KW_NOT")
            and self.pos + 1 < len(self.tokens)
            and self.tokens[self.pos + 1].kind == "KW_IN"
        ):
            self.advance()  # not
            self.advance()  # in
            return ast.NotIn()
        if self.match("KW_IN"):
            return ast.In()
        if self.check("KW_IS"):
            self.advance()
            if self.match("KW_NOT"):
                return ast.IsNot()
            return ast.Is()
        return None

    def _parse_addition(self) -> ast.expr:
        left = self._parse_multiplication()
        while True:
            if self.match("PLUS"):
                right = self._parse_multiplication()
                left = self._loc(ast.BinOp(left=left, op=ast.Add(), right=right))
            elif self.match("MINUS"):
                right = self._parse_multiplication()
                left = self._loc(ast.BinOp(left=left, op=ast.Sub(), right=right))
            else:
                break
        return left

    def _parse_multiplication(self) -> ast.expr:
        left = self._parse_unary()
        while True:
            if self.match("STAR"):
                right = self._parse_unary()
                left = self._loc(ast.BinOp(left=left, op=ast.Mult(), right=right))
            elif self.match("SLASH"):
                right = self._parse_unary()
                left = self._loc(ast.BinOp(left=left, op=ast.Div(), right=right))
            elif self.match("DSLASH"):
                right = self._parse_unary()
                left = self._loc(ast.BinOp(left=left, op=ast.FloorDiv(), right=right))
            elif self.match("PERCENT"):
                right = self._parse_unary()
                left = self._loc(ast.BinOp(left=left, op=ast.Mod(), right=right))
            else:
                break
        return left

    def _parse_unary(self) -> ast.expr:
        if self.match("MINUS"):
            operand = self._parse_unary()
            return self._loc(ast.UnaryOp(op=ast.USub(), operand=operand))
        if self.match("PLUS"):
            return self._parse_unary()
        return self._parse_postfix()

    def _parse_postfix(self) -> ast.expr:
        """Parse postfix operations: x.y, x[i], x(args)"""
        expr = self._parse_atom()
        while True:
            if self.match("DOT"):
                attr_tok = self.expect("NAME")
                expr = self._loc(
                    ast.Attribute(
                        value=expr,
                        attr=attr_tok.value,
                        ctx=ast.Load(),
                    ),
                    attr_tok,
                )
            elif self.match("LBRACKET"):
                index = self._parse_slice_or_index()
                self.expect("RBRACKET")
                expr = self._loc(
                    ast.Subscript(
                        value=expr,
                        slice=index,
                        ctx=ast.Load(),
                    )
                )
            elif self.match("LPAREN"):
                expr = self._parse_call_args(expr)
            else:
                break
        return expr

    def _parse_slice_or_index(self) -> ast.expr:
        """Parse subscript: could be index or slice (a:b:c)."""
        if self.check("COLON"):
            return self._parse_slice(None)
        first = self._parse_expr()
        if self.check("COLON"):
            return self._parse_slice(first)
        return first

    def _parse_slice(self, lower: ast.expr | None) -> ast.Slice:
        """Parse slice: [lower:upper:step]."""
        self.expect("COLON")
        upper = None
        if not self.check("RBRACKET") and not self.check("COLON"):
            upper = self._parse_expr()
        step = None
        if self.match("COLON") and not self.check("RBRACKET"):
            step = self._parse_expr()
        return self._loc(ast.Slice(lower=lower, upper=upper, step=step))

    def _parse_call_args(self, func: ast.expr) -> ast.Call:
        """Parse function call arguments."""
        args: list[ast.expr] = []
        keywords: list[ast.keyword] = []
        while not self.check("RPAREN") and not self.at_end():
            # Check for keyword argument: name=expr
            if (
                self.check("NAME")
                and self.pos + 1 < len(self.tokens)
                and self.tokens[self.pos + 1].kind == "EQ"
            ):
                kw_name = self.advance().value
                self.advance()  # =
                kw_val = self._parse_expr()
                keywords.append(ast.keyword(arg=kw_name, value=kw_val))
            else:
                args.append(self._parse_expr())
            if not self.match("COMMA"):
                break
        self.expect("RPAREN")
        return self._loc(ast.Call(func=func, args=args, keywords=keywords))

    def _parse_atom(self) -> ast.expr:
        """Parse atomic expressions."""
        tok = self.current()

        # Integer literal
        if tok.kind == "INT":
            self.advance()
            return self._loc(ast.Constant(value=int(tok.value.replace("_", ""))), tok)

        # Float literal
        if tok.kind == "FLOAT":
            self.advance()
            return self._loc(ast.Constant(value=float(tok.value.replace("_", ""))), tok)

        # String literal
        if tok.kind == "STRING":
            self.advance()
            return self._loc(ast.Constant(value=self._eval_string(tok.value)), tok)

        # F-string
        if tok.kind == "FSTRING":
            self.advance()
            return self._parse_fstring_value(tok)

        # Boolean / None
        if tok.kind == "KW_TRUE":
            self.advance()
            return self._loc(ast.Constant(value=True), tok)
        if tok.kind == "KW_FALSE":
            self.advance()
            return self._loc(ast.Constant(value=False), tok)
        if tok.kind == "KW_NONE":
            self.advance()
            return self._loc(ast.Constant(value=None), tok)

        # Self
        if tok.kind == "KW_SELF":
            self.advance()
            return self._loc(ast.Name(id="self", ctx=ast.Load()), tok)

        # Name
        if tok.kind == "NAME":
            self.advance()
            return self._loc(ast.Name(id=tok.value, ctx=ast.Load()), tok)

        # Parenthesized expression or tuple
        if tok.kind == "LPAREN":
            self.advance()
            if self.check("RPAREN"):
                self.advance()
                return self._loc(ast.Tuple(elts=[], ctx=ast.Load()), tok)
            first = self._parse_expr()
            if self.match("COMMA"):
                # Tuple
                elts = [first]
                while not self.check("RPAREN") and not self.at_end():
                    elts.append(self._parse_expr())
                    if not self.match("COMMA"):
                        break
                self.expect("RPAREN")
                return self._loc(ast.Tuple(elts=elts, ctx=ast.Load()), tok)
            self.expect("RPAREN")
            return first

        # List literal
        if tok.kind == "LBRACKET":
            self.advance()
            list_elts: list[ast.expr] = []
            while not self.check("RBRACKET") and not self.at_end():
                list_elts.append(self._parse_expr())
                if not self.match("COMMA"):
                    break
            self.expect("RBRACKET")
            return self._loc(ast.List(elts=list_elts, ctx=ast.Load()), tok)

        # Dict literal
        if tok.kind == "LBRACE":
            self.advance()
            keys: list[ast.expr | None] = []
            values: list[ast.expr] = []
            while not self.check("RBRACE") and not self.at_end():
                k = self._parse_expr()
                self.expect("COLON")
                v = self._parse_expr()
                keys.append(k)
                values.append(v)
                if not self.match("COMMA"):
                    break
            self.expect("RBRACE")
            return self._loc(ast.Dict(keys=keys, values=values), tok)

        self.error(f"Unexpected token in expression: {tok.kind}")
        return self._loc(ast.Constant(value=None))  # unreachable

    # ── F-string parsing ───────────────────────────────────────────────

    def _parse_fstring_value(self, tok: Token) -> ast.JoinedStr:
        """Parse an f-string token into ast.JoinedStr."""
        raw = tok.value
        # Strip f prefix and quotes
        inner = raw[2:-1]  # f"..." -> ...
        values: list[ast.expr] = []
        i = 0
        text_chars: list[str] = []

        while i < len(inner):
            ch = inner[i]
            if ch == "{" and i + 1 < len(inner) and inner[i + 1] == "{":
                text_chars.append("{")
                i += 2
            elif ch == "}" and i + 1 < len(inner) and inner[i + 1] == "}":
                text_chars.append("}")
                i += 2
            elif ch == "{":
                # Flush text
                if text_chars:
                    values.append(
                        self._loc(ast.Constant(value="".join(text_chars)), tok)
                    )
                    text_chars = []
                # Find matching }
                depth = 1
                start = i + 1
                i += 1
                while i < len(inner) and depth > 0:
                    if inner[i] == "{":
                        depth += 1
                    elif inner[i] == "}":
                        depth -= 1
                    i += 1
                expr_str = inner[start : i - 1]
                # Parse the expression
                sub_lexer = Lexer(expr_str, self.filename)
                sub_tokens = sub_lexer.tokenize()
                sub_compiler = SeedCompiler(self.filename)
                sub_compiler.tokens = sub_tokens
                sub_compiler.pos = 0
                expr_node = sub_compiler._parse_expr()
                values.append(
                    self._loc(
                        ast.FormattedValue(
                            value=expr_node, conversion=-1, format_spec=None
                        ),
                        tok,
                    )
                )
            elif ch == "\\":
                text_chars.append(ch)
                i += 1
                if i < len(inner):
                    text_chars.append(inner[i])
                    i += 1
            else:
                text_chars.append(ch)
                i += 1

        if text_chars:
            values.append(self._loc(ast.Constant(value="".join(text_chars)), tok))

        return self._loc(ast.JoinedStr(values=values), tok)

    # ── Type expression parsing ────────────────────────────────────────

    def _parse_type_expr(self) -> ast.expr:
        """Parse type expression: int, str, list[int], dict[K,V], T | None"""
        left = self._parse_type_atom()
        # Handle union: Type | None
        if self.match("PIPE"):
            right = self._parse_type_expr()
            return self._loc(ast.BinOp(left=left, op=ast.BitOr(), right=right))
        return left

    def _parse_type_atom(self) -> ast.expr:
        """Parse a single type: int, list[int], dict[K,V], tuple[...]"""
        tok = self.current()
        if tok.kind == "KW_NONE":
            self.advance()
            return self._loc(ast.Constant(value=None), tok)
        if tok.kind != "NAME":
            self.error("Expected type name")
        name = self._parse_dotted_name_expr()
        # Generic: list[T], dict[K, V]
        if self.match("LBRACKET"):
            args: list[ast.expr] = []
            while not self.check("RBRACKET") and not self.at_end():
                args.append(self._parse_type_expr())
                self.match("COMMA")
            self.expect("RBRACKET")
            return self._loc(
                ast.Subscript(
                    value=name,
                    slice=args[0]
                    if len(args) == 1
                    else ast.Tuple(elts=args, ctx=ast.Load()),
                    ctx=ast.Load(),
                )
            )
        return name

    # ── Helpers ────────────────────────────────────────────────────────

    def _parse_dotted_name(self) -> str:
        """Parse dotted.name.path"""
        parts = [self.expect("NAME").value]
        while self.match("DOT"):
            parts.append(self.expect("NAME").value)
        return ".".join(parts)

    def _parse_dotted_name_expr(self) -> ast.expr:
        """Parse dotted name as AST attribute chain."""
        tok = self.current()
        name = self.expect("NAME").value
        node: ast.expr = self._loc(ast.Name(id=name, ctx=ast.Load()), tok)
        while self.match("DOT"):
            attr = self.expect("NAME").value
            node = self._loc(ast.Attribute(value=node, attr=attr, ctx=ast.Load()))
        return node

    def _eval_string(self, raw: str) -> str:
        """Evaluate a string literal, handling escape sequences."""
        # Triple-quoted
        if raw.startswith('"""') or raw.startswith("'''"):
            inner = raw[3:-3]
        else:
            inner = raw[1:-1]
        # Process basic escape sequences
        result: list[str] = []
        i = 0
        while i < len(inner):
            if inner[i] == "\\" and i + 1 < len(inner):
                nxt = inner[i + 1]
                if nxt == "n":
                    result.append("\n")
                elif nxt == "t":
                    result.append("\t")
                elif nxt == "r":
                    result.append("\r")
                elif nxt == "\\":
                    result.append("\\")
                elif nxt == "'":
                    result.append("'")
                elif nxt == '"':
                    result.append('"')
                elif nxt == "0":
                    result.append("\0")
                else:
                    result.append("\\")
                    result.append(nxt)
                i += 2
            else:
                result.append(inner[i])
                i += 1
        return "".join(result)


# ============================================================================
# Public API
# ============================================================================


def seed_compile(source: str, filename: str = "<seed>") -> types.CodeType:
    """Compile Jac source (Layer 0 subset) to Python code object."""
    compiler = SeedCompiler(filename)
    return compiler.compile_module(source, filename)


def seed_compile_file(path: str) -> types.CodeType:
    """Compile a Jac file (Layer 0 subset) to Python code object."""
    with open(path) as f:
        source = f.read()
    return seed_compile(source, path)


def seed_exec(
    source: str, filename: str = "<seed>", globals_dict: dict | None = None
) -> dict:
    """Compile and execute Jac source, returning the resulting namespace."""
    code = seed_compile(source, filename)
    ns = globals_dict if globals_dict is not None else {}
    exec(code, ns)
    return ns
