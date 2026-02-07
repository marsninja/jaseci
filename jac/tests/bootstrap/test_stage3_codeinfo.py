"""Tests for Stage 3: codeinfo.jac compiled by Layer 1.

Verifies that codeinfo.jac (the Jac port of codeinfo.py) can be:
1. Parsed by the Layer 1 parser
2. Compiled to valid Python by the Layer 1 codegen
3. Executed to produce equivalent classes with correct behavior
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

CODEINFO_JAC = "jac/jaclang/pycore/stage3/codeinfo.jac"


def _compile_codeinfo_jac() -> dict:
    """Parse and compile codeinfo.jac, return the exec'd namespace."""
    with open(CODEINFO_JAC) as f:
        source = f.read()
    p = Parser(tokens=[], pos=0, filename="codeinfo.jac")
    mod = p.parse_module(source, "codeinfo.jac")
    cg = Codegen()
    py = cg.generate(mod)
    code = compile(py, "codeinfo.jac", "exec")
    ns: dict = {}
    exec(code, ns)
    return ns


# Compile once for all tests
_ns = _compile_codeinfo_jac()


class _MockToken:
    """Mock token for CodeLocInfo tests."""

    def __init__(  # noqa: ANN204
        self,
        line_no: int = 1,
        c_start: int = 0,
        c_end: int = 5,
        pos_start: int = 0,
        pos_end: int = 5,
        end_line: int = 1,
        file_path: str = "test.jac",
    ):
        self.line_no = line_no
        self.c_start = c_start
        self.c_end = c_end
        self.pos_start = pos_start
        self.pos_end = pos_end
        self.end_line = end_line
        self.orig_src = type("Source", (), {"file_path": file_path})()


# =============================================================================
# Compile Tests
# =============================================================================


class TestCodeinfoJacCompiles(unittest.TestCase):
    """Verify codeinfo.jac can be parsed and compiled."""

    def test_parse_succeeds(self) -> None:
        with open(CODEINFO_JAC) as f:
            source = f.read()
        p = Parser(tokens=[], pos=0, filename="codeinfo.jac")
        mod = p.parse_module(source, "codeinfo.jac")
        self.assertGreater(len(mod.body), 5)

    def test_codegen_produces_valid_python(self) -> None:
        with open(CODEINFO_JAC) as f:
            source = f.read()
        p = Parser(tokens=[], pos=0, filename="codeinfo.jac")
        mod = p.parse_module(source, "codeinfo.jac")
        cg = Codegen()
        py = cg.generate(mod)
        code = compile(py, "codeinfo.jac", "exec")
        self.assertIsNotNone(code)

    def test_all_classes_present(self) -> None:
        self.assertIn("ClientManifest", _ns)
        self.assertIn("InteropContext", _ns)
        self.assertIn("NativeFunctionInfo", _ns)
        self.assertIn("NativeModuleInfo", _ns)
        self.assertIn("InteropBinding", _ns)
        self.assertIn("InteropManifest", _ns)
        self.assertIn("CodeGenTarget", _ns)
        self.assertIn("CodeLocInfo", _ns)


# =============================================================================
# ClientManifest Tests
# =============================================================================


class TestClientManifest(unittest.TestCase):
    """Test ClientManifest obj."""

    def test_default_values(self) -> None:
        cm = _ns["ClientManifest"]()
        self.assertEqual(cm.exports, [])
        self.assertEqual(cm.globals, [])
        self.assertEqual(cm.params, {})
        self.assertFalse(cm.has_client)

    def test_mutable_defaults_not_shared(self) -> None:
        cm1 = _ns["ClientManifest"]()
        cm2 = _ns["ClientManifest"]()
        cm1.exports.append("test")
        self.assertEqual(cm1.exports, ["test"])
        self.assertEqual(cm2.exports, [])

    def test_constructor_kwargs(self) -> None:
        cm = _ns["ClientManifest"](has_client=True, exports=["a", "b"])
        self.assertTrue(cm.has_client)
        self.assertEqual(cm.exports, ["a", "b"])


# =============================================================================
# InteropContext Tests
# =============================================================================


class TestInteropContext(unittest.TestCase):
    """Test InteropContext enum."""

    def test_member_count(self) -> None:
        self.assertEqual(len(_ns["InteropContext"]), 3)

    def test_values(self) -> None:
        ic = _ns["InteropContext"]
        self.assertEqual(ic.SERVER.value, "server")
        self.assertEqual(ic.NATIVE.value, "native")
        self.assertEqual(ic.CLIENT.value, "client")


# =============================================================================
# NativeFunctionInfo Tests
# =============================================================================


class TestNativeFunctionInfo(unittest.TestCase):
    """Test NativeFunctionInfo obj."""

    def test_defaults(self) -> None:
        nfi = _ns["NativeFunctionInfo"]()
        self.assertEqual(nfi.name, "")
        self.assertEqual(nfi.ret_type, "int")
        self.assertEqual(nfi.param_types, [])

    def test_constructor(self) -> None:
        nfi = _ns["NativeFunctionInfo"](name="add", ret_type="float")
        self.assertEqual(nfi.name, "add")
        self.assertEqual(nfi.ret_type, "float")


# =============================================================================
# InteropBinding Tests
# =============================================================================


class TestInteropBinding(unittest.TestCase):
    """Test InteropBinding obj with properties."""

    def test_is_direct(self) -> None:
        ic = _ns["InteropContext"]
        ib = _ns["InteropBinding"](name="fn", route=[ic.SERVER, ic.NATIVE])
        self.assertTrue(ib.is_direct)
        self.assertFalse(ib.is_composed)

    def test_is_composed(self) -> None:
        ic = _ns["InteropContext"]
        ib = _ns["InteropBinding"](name="fn", route=[ic.CLIENT, ic.SERVER, ic.NATIVE])
        self.assertFalse(ib.is_direct)
        self.assertTrue(ib.is_composed)

    def test_is_cross_module(self) -> None:
        ib1 = _ns["InteropBinding"](name="fn")
        self.assertFalse(ib1.is_cross_module)
        ib2 = _ns["InteropBinding"](name="fn", source_module="/test.jac")
        self.assertTrue(ib2.is_cross_module)

    def test_callers_set(self) -> None:
        ic = _ns["InteropContext"]
        ib = _ns["InteropBinding"](name="fn", callers={ic.NATIVE, ic.CLIENT})
        self.assertIn(ic.NATIVE, ib.callers)
        self.assertIn(ic.CLIENT, ib.callers)

    def test_mutable_defaults_not_shared(self) -> None:
        ib1 = _ns["InteropBinding"](name="a")
        ib2 = _ns["InteropBinding"](name="b")
        ib1.param_types.append("int")
        self.assertEqual(ib1.param_types, ["int"])
        self.assertEqual(ib2.param_types, [])


# =============================================================================
# InteropManifest Tests
# =============================================================================


class TestInteropManifest(unittest.TestCase):
    """Test InteropManifest with filtered property queries."""

    def test_defaults(self) -> None:
        im = _ns["InteropManifest"]()
        self.assertEqual(im.bindings, {})
        self.assertIn("int", im.JAC_TO_CTYPES)
        self.assertEqual(im.JAC_TO_CTYPES["int"], "ctypes.c_int64")

    def test_native_imports_filter(self) -> None:
        ic = _ns["InteropContext"]
        im = _ns["InteropManifest"]()
        im.bindings["sv_fn"] = _ns["InteropBinding"](
            name="sv_fn", source_context=ic.SERVER, callers={ic.NATIVE}
        )
        im.bindings["na_fn"] = _ns["InteropBinding"](
            name="na_fn", source_context=ic.NATIVE, callers={ic.SERVER}
        )
        imports = im.native_imports
        self.assertEqual(len(imports), 1)
        self.assertEqual(imports[0].name, "sv_fn")

    def test_native_exports_filter(self) -> None:
        ic = _ns["InteropContext"]
        im = _ns["InteropManifest"]()
        im.bindings["na_fn"] = _ns["InteropBinding"](
            name="na_fn", source_context=ic.NATIVE, callers={ic.SERVER}
        )
        exports = im.native_exports
        self.assertEqual(len(exports), 1)
        self.assertEqual(exports[0].name, "na_fn")


# =============================================================================
# CodeGenTarget Tests
# =============================================================================


class TestCodeGenTarget(unittest.TestCase):
    """Test CodeGenTarget obj."""

    def test_default_values(self) -> None:
        cgt = _ns["CodeGenTarget"]()
        self.assertEqual(cgt.py, "")
        self.assertEqual(cgt.jac, "")
        self.assertEqual(cgt.js, "")
        self.assertEqual(cgt.py_ast, [])
        self.assertIsNone(cgt.py_bytecode)
        self.assertIsNone(cgt.es_ast)

    def test_doc_ir_property_setter(self) -> None:
        cgt = _ns["CodeGenTarget"]()
        cgt.doc_ir = "test_doc"
        self.assertEqual(cgt.doc_ir, "test_doc")

    def test_mutable_defaults_not_shared(self) -> None:
        cgt1 = _ns["CodeGenTarget"]()
        cgt2 = _ns["CodeGenTarget"]()
        cgt1.py_ast.append("node")
        self.assertEqual(cgt1.py_ast, ["node"])
        self.assertEqual(cgt2.py_ast, [])


# =============================================================================
# CodeLocInfo Tests
# =============================================================================


class TestCodeLocInfo(unittest.TestCase):
    """Test CodeLocInfo obj with property accessors."""

    def setUp(self) -> None:
        self.ft = _MockToken(line_no=1, c_start=0, c_end=5, pos_start=0, pos_end=5)
        self.lt = _MockToken(
            line_no=3, c_start=2, c_end=10, pos_start=20, pos_end=30, end_line=3
        )
        self.cli = _ns["CodeLocInfo"](first_tok=self.ft, last_tok=self.lt)

    def test_first_line(self) -> None:
        self.assertEqual(self.cli.first_line, 1)

    def test_last_line(self) -> None:
        self.assertEqual(self.cli.last_line, 3)

    def test_col_start(self) -> None:
        self.assertEqual(self.cli.col_start, 0)

    def test_col_end(self) -> None:
        self.assertEqual(self.cli.col_end, 10)

    def test_pos_start(self) -> None:
        self.assertEqual(self.cli.pos_start, 0)

    def test_pos_end(self) -> None:
        self.assertEqual(self.cli.pos_end, 30)

    def test_mod_path(self) -> None:
        self.assertEqual(self.cli.mod_path, "test.jac")

    def test_tok_range(self) -> None:
        first, last = self.cli.tok_range
        self.assertIs(first, self.ft)
        self.assertIs(last, self.lt)

    def test_first_token(self) -> None:
        self.assertIs(self.cli.first_token, self.ft)

    def test_last_token(self) -> None:
        self.assertIs(self.cli.last_token, self.lt)

    def test_update_token_range(self) -> None:
        new_ft = _MockToken(line_no=10)
        new_lt = _MockToken(line_no=20, end_line=20)
        self.cli.update_token_range(new_ft, new_lt)
        self.assertEqual(self.cli.first_line, 10)
        self.assertEqual(self.cli.last_line, 20)

    def test_update_first_token(self) -> None:
        new_ft = _MockToken(line_no=99)
        self.cli.update_first_token(new_ft)
        self.assertEqual(self.cli.first_line, 99)

    def test_update_last_token(self) -> None:
        new_lt = _MockToken(end_line=50)
        self.cli.update_last_token(new_lt)
        self.assertEqual(self.cli.last_line, 50)

    def test_str(self) -> None:
        result = str(self.cli)
        self.assertEqual(result, "1:0 - 3:10")


if __name__ == "__main__":
    unittest.main()
