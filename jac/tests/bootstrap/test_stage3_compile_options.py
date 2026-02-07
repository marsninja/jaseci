"""Tests for Stage 3: compile_options.jac compiled by Layer 1.

Verifies that compile_options.jac (the Jac port of compile_options.py) can be:
1. Parsed by the Layer 1 parser
2. Compiled to valid Python by the Layer 1 codegen
3. Executed to produce equivalent dataclass with correct behavior
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

COMPILE_OPTIONS_JAC = "jac/jaclang/pycore/stage3/compile_options.jac"


def _compile_compile_options_jac() -> dict:
    """Parse and compile compile_options.jac, return the exec'd namespace."""
    with open(COMPILE_OPTIONS_JAC) as f:
        source = f.read()
    p = Parser(tokens=[], pos=0, filename="compile_options.jac")
    mod = p.parse_module(source, "compile_options.jac")
    cg = Codegen()
    py = cg.generate(mod)
    code = compile(py, "compile_options.jac", "exec")
    ns: dict = {}
    exec(code, ns)
    return ns


# Compile once for all tests
_ns = _compile_compile_options_jac()


# =============================================================================
# Compile Tests
# =============================================================================


class TestCompileOptionsJacCompiles(unittest.TestCase):
    """Verify compile_options.jac can be parsed and compiled."""

    def test_parse_succeeds(self) -> None:
        with open(COMPILE_OPTIONS_JAC) as f:
            source = f.read()
        p = Parser(tokens=[], pos=0, filename="compile_options.jac")
        mod = p.parse_module(source, "compile_options.jac")
        self.assertGreater(len(mod.body), 2)

    def test_codegen_produces_valid_python(self) -> None:
        with open(COMPILE_OPTIONS_JAC) as f:
            source = f.read()
        p = Parser(tokens=[], pos=0, filename="compile_options.jac")
        mod = p.parse_module(source, "compile_options.jac")
        cg = Codegen()
        py = cg.generate(mod)
        code = compile(py, "compile_options.jac", "exec")
        self.assertIsNotNone(code)

    def test_class_present(self) -> None:
        self.assertIn("CompileOptions", _ns)

    def test_default_options_present(self) -> None:
        self.assertIn("DEFAULT_OPTIONS", _ns)


# =============================================================================
# CompileOptions Tests
# =============================================================================


class TestCompileOptions(unittest.TestCase):
    """Test CompileOptions obj."""

    def test_default_values(self) -> None:
        opts = _ns["CompileOptions"]()
        self.assertFalse(opts.minimal)
        self.assertFalse(opts.type_check)
        self.assertFalse(opts.symtab_ir_only)
        self.assertFalse(opts.no_cgen)
        self.assertFalse(opts.skip_native_engine)
        self.assertIsNone(opts.cancel_token)

    def test_constructor_kwargs(self) -> None:
        opts = _ns["CompileOptions"](minimal=True, type_check=True)
        self.assertTrue(opts.minimal)
        self.assertTrue(opts.type_check)
        self.assertFalse(opts.no_cgen)

    def test_with_skip_native_engine_true(self) -> None:
        opts = _ns["CompileOptions"](minimal=True)
        new_opts = opts.with_skip_native_engine(True)
        self.assertTrue(new_opts.skip_native_engine)
        self.assertTrue(new_opts.minimal)
        self.assertFalse(opts.skip_native_engine)

    def test_with_skip_native_engine_false(self) -> None:
        opts = _ns["CompileOptions"](skip_native_engine=True)
        new_opts = opts.with_skip_native_engine(False)
        self.assertFalse(new_opts.skip_native_engine)

    def test_with_skip_preserves_all_fields(self) -> None:
        opts = _ns["CompileOptions"](
            minimal=True,
            type_check=True,
            symtab_ir_only=True,
            no_cgen=True,
            cancel_token="tok",
        )
        new_opts = opts.with_skip_native_engine(True)
        self.assertTrue(new_opts.minimal)
        self.assertTrue(new_opts.type_check)
        self.assertTrue(new_opts.symtab_ir_only)
        self.assertTrue(new_opts.no_cgen)
        self.assertTrue(new_opts.skip_native_engine)
        self.assertEqual(new_opts.cancel_token, "tok")

    def test_default_options_instance(self) -> None:
        default = _ns["DEFAULT_OPTIONS"]
        self.assertFalse(default.minimal)
        self.assertFalse(default.type_check)
        self.assertIsNone(default.cancel_token)

    def test_instances_independent(self) -> None:
        opts1 = _ns["CompileOptions"]()
        opts2 = _ns["CompileOptions"]()
        opts1.minimal = True
        self.assertTrue(opts1.minimal)
        self.assertFalse(opts2.minimal)


if __name__ == "__main__":
    unittest.main()
