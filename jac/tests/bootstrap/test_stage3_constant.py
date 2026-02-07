"""Tests for Stage 3: constant.jac compiled by Layer 1.

Verifies that constant.jac (the Jac port of constant.py) can be:
1. Parsed by the Layer 1 parser
2. Compiled to valid Python by the Layer 1 codegen
3. Executed to produce the same classes, enums, and values as constant.py
"""

import sys
import types
import unittest

sys.path.insert(0, "/home/marsninja/repos/j3/jac")

from jaclang.bootstrap.seed_compiler import seed_compile_file


def _load_module(name: str, path: str) -> dict:
    """Compile a .jac file with the seed and make it importable."""
    code = seed_compile_file(path)
    ns = {"__builtins__": __builtins__}
    exec(code, ns)
    mod = types.ModuleType(name)
    for k, v in ns.items():
        if not k.startswith("_"):
            setattr(mod, k, v)
    sys.modules[name] = mod
    return ns


# Load Layer 1 modules
_ast_ns = _load_module(
    "jaclang.bootstrap.bootstrap_ast",
    "jac/jaclang/bootstrap/bootstrap_ast.jac",
)
_lex_ns = _load_module(
    "jaclang.bootstrap.bootstrap_lexer",
    "jac/jaclang/bootstrap/bootstrap_lexer.jac",
)
_parser_ns = _load_module(
    "jaclang.bootstrap.bootstrap_parser",
    "jac/jaclang/bootstrap/bootstrap_parser.jac",
)
_codegen_ns = _load_module(
    "jaclang.bootstrap.bootstrap_codegen",
    "jac/jaclang/bootstrap/bootstrap_codegen.jac",
)

Parser = _parser_ns["BootstrapParser"]
Codegen = _codegen_ns["BootstrapCodegen"]

CONSTANT_JAC = "jac/jaclang/pycore/stage3/constant.jac"


def _compile_constant_jac() -> dict:
    """Parse and compile constant.jac, return the exec'd namespace."""
    with open(CONSTANT_JAC) as f:
        source = f.read()
    p = Parser(tokens=[], pos=0, filename="constant.jac")
    mod = p.parse_module(source, "constant.jac")
    cg = Codegen()
    py = cg.generate(mod)
    code = compile(py, "constant.jac", "exec")
    ns: dict = {}
    exec(code, ns)
    return ns


# Compile once for all tests
_ns = _compile_constant_jac()


# =============================================================================
# Parse and Compile Tests
# =============================================================================


class TestConstantJacCompiles(unittest.TestCase):
    """Verify constant.jac can be parsed and compiled."""

    def test_parse_succeeds(self) -> None:
        with open(CONSTANT_JAC) as f:
            source = f.read()
        p = Parser(tokens=[], pos=0, filename="constant.jac")
        mod = p.parse_module(source, "constant.jac")
        self.assertGreater(len(mod.body), 10)

    def test_codegen_produces_valid_python(self) -> None:
        with open(CONSTANT_JAC) as f:
            source = f.read()
        p = Parser(tokens=[], pos=0, filename="constant.jac")
        mod = p.parse_module(source, "constant.jac")
        cg = Codegen()
        py = cg.generate(mod)
        code = compile(py, "constant.jac", "exec")
        self.assertIsNotNone(code)

    def test_exec_succeeds(self) -> None:
        self.assertIn("SymbolType", _ns)
        self.assertIn("Tokens", _ns)
        self.assertIn("TsTokens", _ns)


# =============================================================================
# SymbolType Tests
# =============================================================================


class TestSymbolType(unittest.TestCase):
    """Test SymbolType enum."""

    def test_member_count(self) -> None:
        self.assertEqual(len(_ns["SymbolType"]), 24)

    def test_values(self) -> None:
        st = _ns["SymbolType"]
        self.assertEqual(st.MODULE.value, "module")
        self.assertEqual(st.VAR.value, "variable")
        self.assertEqual(st.ABILITY.value, "ability")
        self.assertEqual(st.OBJECT_ARCH.value, "object")
        self.assertEqual(st.UNKNOWN.value, "unknown")

    def test_str(self) -> None:
        st = _ns["SymbolType"]
        self.assertEqual(str(st.MODULE), "module")
        self.assertEqual(str(st.HAS_VAR), "field")


# =============================================================================
# JacSemTokenType Tests
# =============================================================================


class TestJacSemTokenType(unittest.TestCase):
    """Test JacSemTokenType (IntEnum)."""

    def test_member_count(self) -> None:
        self.assertEqual(len(_ns["JacSemTokenType"]), 22)

    def test_integer_values(self) -> None:
        t = _ns["JacSemTokenType"]
        self.assertEqual(int(t.NAMESPACE), 0)
        self.assertEqual(int(t.TYPE), 1)
        self.assertEqual(int(t.OPERATOR), 21)

    def test_as_str_list(self) -> None:
        t = _ns["JacSemTokenType"]
        result = t.as_str_list()
        self.assertEqual(len(result), 22)
        self.assertEqual(result[0], "namespace")
        self.assertEqual(result[2], "class")


# =============================================================================
# JacSemTokenModifier Tests
# =============================================================================


class TestJacSemTokenModifier(unittest.TestCase):
    """Test JacSemTokenModifier (IntFlag)."""

    def test_member_count(self) -> None:
        self.assertEqual(len(_ns["JacSemTokenModifier"]), 10)

    def test_flag_values(self) -> None:
        m = _ns["JacSemTokenModifier"]
        self.assertEqual(int(m.DECLARATION), 1)
        self.assertEqual(int(m.DEFINITION), 2)
        self.assertEqual(int(m.READONLY), 4)
        self.assertEqual(int(m.STATIC), 8)
        self.assertEqual(int(m.DEFAULT_LIBRARY), 512)

    def test_bitwise_or(self) -> None:
        m = _ns["JacSemTokenModifier"]
        combined = m.DECLARATION | m.STATIC
        self.assertEqual(int(combined), 9)

    def test_as_str_list(self) -> None:
        m = _ns["JacSemTokenModifier"]
        result = m.as_str_list()
        self.assertIn("declaration", result)
        self.assertIn("static", result)


# =============================================================================
# Constants Tests
# =============================================================================


class TestConstants(unittest.TestCase):
    """Test Constants (StrEnum)."""

    def test_member_count(self) -> None:
        self.assertEqual(len(_ns["Constants"]), 5)

    def test_values(self) -> None:
        c = _ns["Constants"]
        self.assertEqual(c.HERE.value, "here")
        self.assertEqual(c.ROOT.value, "root")
        self.assertEqual(c.VISITOR.value, "visitor")
        self.assertEqual(c.JAC_CHECK.value, "_check")

    def test_str(self) -> None:
        c = _ns["Constants"]
        self.assertEqual(str(c.HERE), "here")


# =============================================================================
# CodeContext Tests
# =============================================================================


class TestCodeContext(unittest.TestCase):
    """Test CodeContext enum with @property methods."""

    def test_member_count(self) -> None:
        self.assertEqual(len(_ns["CodeContext"]), 3)

    def test_values(self) -> None:
        cc = _ns["CodeContext"]
        self.assertEqual(cc.SERVER.value, "server")
        self.assertEqual(cc.CLIENT.value, "client")
        self.assertEqual(cc.NATIVE.value, "native")

    def test_str(self) -> None:
        cc = _ns["CodeContext"]
        self.assertEqual(str(cc.SERVER), "server")

    def test_is_server_property(self) -> None:
        cc = _ns["CodeContext"]
        self.assertTrue(cc.SERVER.is_server)
        self.assertFalse(cc.CLIENT.is_server)
        self.assertFalse(cc.NATIVE.is_server)

    def test_is_client_property(self) -> None:
        cc = _ns["CodeContext"]
        self.assertFalse(cc.SERVER.is_client)
        self.assertTrue(cc.CLIENT.is_client)

    def test_is_native_property(self) -> None:
        cc = _ns["CodeContext"]
        self.assertFalse(cc.SERVER.is_native)
        self.assertTrue(cc.NATIVE.is_native)


# =============================================================================
# EdgeDir Tests
# =============================================================================


class TestEdgeDir(unittest.TestCase):
    """Test EdgeDir enum."""

    def test_member_count(self) -> None:
        self.assertEqual(len(_ns["EdgeDir"]), 3)

    def test_values(self) -> None:
        e = _ns["EdgeDir"]
        self.assertEqual(e.IN.value, 1)
        self.assertEqual(e.OUT.value, 2)
        self.assertEqual(e.ANY.value, 3)


# =============================================================================
# SymbolAccess Tests
# =============================================================================


class TestSymbolAccess(unittest.TestCase):
    """Test SymbolAccess enum."""

    def test_member_count(self) -> None:
        self.assertEqual(len(_ns["SymbolAccess"]), 3)

    def test_str(self) -> None:
        sa = _ns["SymbolAccess"]
        self.assertEqual(str(sa.PUBLIC), "public")
        self.assertEqual(str(sa.PRIVATE), "private")
        self.assertEqual(str(sa.PROTECTED), "protected")


# =============================================================================
# Tokens Tests
# =============================================================================


class TestTokens(unittest.TestCase):
    """Test Tokens enum (str, Enum)."""

    def test_member_count(self) -> None:
        self.assertEqual(len(_ns["Tokens"]), 202)

    def test_values(self) -> None:
        tok = _ns["Tokens"]
        self.assertEqual(tok.FLOAT.value, "FLOAT")
        self.assertEqual(tok.KW_IF.value, "KW_IF")
        self.assertEqual(tok.LPAREN.value, "LPAREN")

    def test_str(self) -> None:
        tok = _ns["Tokens"]
        self.assertEqual(str(tok.FLOAT), "FLOAT")


# =============================================================================
# DELIM_MAP Tests
# =============================================================================


class TestDelimMap(unittest.TestCase):
    """Test DELIM_MAP dict."""

    def test_size(self) -> None:
        self.assertEqual(len(_ns["DELIM_MAP"]), 14)

    def test_values(self) -> None:
        tok = _ns["Tokens"]
        dm = _ns["DELIM_MAP"]
        self.assertEqual(dm[tok.COMMA], ",")
        self.assertEqual(dm[tok.SEMI], ";")
        self.assertEqual(dm[tok.LPAREN], "(")
        self.assertEqual(dm[tok.RETURN_HINT], "->")


# =============================================================================
# Colors Tests
# =============================================================================


class TestColors(unittest.TestCase):
    """Test colors list."""

    def test_count(self) -> None:
        self.assertEqual(len(_ns["colors"]), 25)

    def test_first_color(self) -> None:
        self.assertEqual(_ns["colors"][0], "#FFE9E9")


# =============================================================================
# TsTokens Tests
# =============================================================================


class TestTsTokens(unittest.TestCase):
    """Test TsTokens enum."""

    def test_member_count(self) -> None:
        self.assertEqual(len(_ns["TsTokens"]), 154)

    def test_values(self) -> None:
        tok = _ns["TsTokens"]
        self.assertEqual(tok.KW_IF.value, "KW_IF")
        self.assertEqual(tok.ARROW.value, "ARROW")


# =============================================================================
# TS_TOKEN_VALUES Tests
# =============================================================================


class TestTsTokenValues(unittest.TestCase):
    """Test TS_TOKEN_VALUES dict."""

    def test_keywords(self) -> None:
        tok = _ns["TsTokens"]
        tv = _ns["TS_TOKEN_VALUES"]
        self.assertEqual(tv[tok.KW_IF], "if")
        self.assertEqual(tv[tok.KW_CLASS], "class")
        self.assertEqual(tv[tok.KW_FUNCTION], "function")

    def test_operators(self) -> None:
        tok = _ns["TsTokens"]
        tv = _ns["TS_TOKEN_VALUES"]
        self.assertEqual(tv[tok.PLUS], "+")
        self.assertEqual(tv[tok.ARROW], "=>")


# =============================================================================
# TsSymbolType and TsModifier Tests
# =============================================================================


class TestTsSymbolType(unittest.TestCase):
    """Test TsSymbolType (StrEnum)."""

    def test_member_count(self) -> None:
        self.assertEqual(len(_ns["TsSymbolType"]), 17)

    def test_values(self) -> None:
        t = _ns["TsSymbolType"]
        self.assertEqual(t.VARIABLE.value, "variable")
        self.assertEqual(t.FUNCTION.value, "function")


class TestTsModifier(unittest.TestCase):
    """Test TsModifier (StrEnum)."""

    def test_member_count(self) -> None:
        self.assertEqual(len(_ns["TsModifier"]), 12)

    def test_values(self) -> None:
        t = _ns["TsModifier"]
        self.assertEqual(t.PUBLIC.value, "public")
        self.assertEqual(t.STATIC.value, "static")


if __name__ == "__main__":
    unittest.main()
