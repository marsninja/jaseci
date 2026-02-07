"""Tests for Stage 3: modresolver.jac compiled by Layer 1.

Verifies that modresolver.jac (the Jac port of modresolver.py) can be:
1. Parsed by the Layer 1 parser
2. Compiled to valid Python by the Layer 1 codegen
3. Executed to produce equivalent functions with correct behavior
"""

import os
import shutil
import sys
import tempfile
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

MODRESOLVER_JAC = "jac/jaclang/pycore/stage3/modresolver.jac"


def _compile_modresolver_jac() -> dict:
    """Parse and compile modresolver.jac, return the exec'd namespace."""
    with open(MODRESOLVER_JAC) as f:
        source = f.read()
    p = Parser(tokens=[], pos=0, filename="modresolver.jac")
    mod = p.parse_module(source, "modresolver.jac")
    cg = Codegen()
    py = cg.generate(mod)
    code = compile(py, "modresolver.jac", "exec")
    ns: dict = {"__builtins__": __builtins__, "__file__": MODRESOLVER_JAC}
    exec(code, ns)
    return ns


# Compile once for all tests
_ns = _compile_modresolver_jac()


# =============================================================================
# Compile Tests
# =============================================================================


class TestModresolverJacCompiles(unittest.TestCase):
    """Verify modresolver.jac can be parsed and compiled."""

    def test_parse_succeeds(self) -> None:
        with open(MODRESOLVER_JAC) as f:
            source = f.read()
        p = Parser(tokens=[], pos=0, filename="modresolver.jac")
        mod = p.parse_module(source, "modresolver.jac")
        self.assertGreater(len(mod.body), 5)

    def test_codegen_produces_valid_python(self) -> None:
        with open(MODRESOLVER_JAC) as f:
            source = f.read()
        p = Parser(tokens=[], pos=0, filename="modresolver.jac")
        mod = p.parse_module(source, "modresolver.jac")
        cg = Codegen()
        py = cg.generate(mod)
        code = compile(py, "modresolver.jac", "exec")
        self.assertIsNotNone(code)

    def test_all_functions_present(self) -> None:
        for name in [
            "get_jac_search_paths",
            "get_py_search_paths",
            "_candidate_from",
            "resolve_module",
            "infer_language",
            "resolve_relative_path",
            "convert_to_js_import_path",
            "get_typeshed_paths",
            "_candidate_from_typeshed",
        ]:
            self.assertIn(name, _ns, f"{name} not found in namespace")


# =============================================================================
# convert_to_js_import_path Tests
# =============================================================================


class TestConvertToJsImportPath(unittest.TestCase):
    """Test JavaScript import path conversion."""

    def test_single_dot_relative(self) -> None:
        self.assertEqual(_ns["convert_to_js_import_path"](".utils"), "./utils.js")

    def test_double_dot_relative(self) -> None:
        self.assertEqual(_ns["convert_to_js_import_path"]("..lib"), "../lib.js")

    def test_triple_dot_relative(self) -> None:
        self.assertEqual(
            _ns["convert_to_js_import_path"]("...config"), "../../config.js"
        )

    def test_already_js_format_dot_slash(self) -> None:
        self.assertEqual(_ns["convert_to_js_import_path"]("./already"), "./already")

    def test_already_js_format_dotdot_slash(self) -> None:
        self.assertEqual(_ns["convert_to_js_import_path"]("../already"), "../already")

    def test_empty_string(self) -> None:
        self.assertEqual(_ns["convert_to_js_import_path"](""), "")

    def test_no_dots(self) -> None:
        self.assertEqual(_ns["convert_to_js_import_path"]("module"), "module")

    def test_relative_with_js_extension(self) -> None:
        self.assertEqual(_ns["convert_to_js_import_path"](".file.js"), "./file.js")

    def test_relative_with_css_extension(self) -> None:
        self.assertEqual(
            _ns["convert_to_js_import_path"](".styles.css"), "./styles.css"
        )

    def test_single_dot(self) -> None:
        self.assertEqual(_ns["convert_to_js_import_path"]("."), ".")

    def test_double_dot_only(self) -> None:
        self.assertEqual(_ns["convert_to_js_import_path"](".."), "..")


# =============================================================================
# _candidate_from Tests
# =============================================================================


class TestCandidateFrom(unittest.TestCase):
    """Test file candidate resolution."""

    def setUp(self) -> None:
        self.td = tempfile.mkdtemp()
        # Create directory with __init__.jac
        os.makedirs(os.path.join(self.td, "mymod"))
        with open(os.path.join(self.td, "mymod", "__init__.jac"), "w") as f:
            f.write("# test")
        # Create directory with __init__.py
        os.makedirs(os.path.join(self.td, "pymod"))
        with open(os.path.join(self.td, "pymod", "__init__.py"), "w") as f:
            f.write("# test")
        # Create .jac file
        with open(os.path.join(self.td, "simple.jac"), "w") as f:
            f.write("# test")
        # Create .py file
        with open(os.path.join(self.td, "helper.py"), "w") as f:
            f.write("# test")
        # Create .js file
        with open(os.path.join(self.td, "frontend.js"), "w") as f:
            f.write("// test")

    def tearDown(self) -> None:
        shutil.rmtree(self.td)

    def test_dir_with_init_jac(self) -> None:
        result = _ns["_candidate_from"](self.td, ["mymod"])
        self.assertIsNotNone(result)
        self.assertEqual(result[1], "jac")
        self.assertTrue(result[0].endswith("__init__.jac"))

    def test_dir_with_init_py(self) -> None:
        result = _ns["_candidate_from"](self.td, ["pymod"])
        self.assertIsNotNone(result)
        self.assertEqual(result[1], "py")
        self.assertTrue(result[0].endswith("__init__.py"))

    def test_jac_file(self) -> None:
        result = _ns["_candidate_from"](self.td, ["simple"])
        self.assertIsNotNone(result)
        self.assertEqual(result[1], "jac")
        self.assertTrue(result[0].endswith("simple.jac"))

    def test_py_file(self) -> None:
        result = _ns["_candidate_from"](self.td, ["helper"])
        self.assertIsNotNone(result)
        self.assertEqual(result[1], "py")

    def test_js_file(self) -> None:
        result = _ns["_candidate_from"](self.td, ["frontend"])
        self.assertIsNotNone(result)
        self.assertEqual(result[1], "js")

    def test_nonexistent(self) -> None:
        result = _ns["_candidate_from"](self.td, ["nonexistent"])
        self.assertIsNone(result)


# =============================================================================
# Search Path Tests
# =============================================================================


class TestSearchPaths(unittest.TestCase):
    """Test search path construction."""

    def test_jac_search_paths_not_empty(self) -> None:
        paths = _ns["get_jac_search_paths"]()
        self.assertGreater(len(paths), 0)

    def test_jac_search_paths_includes_cwd(self) -> None:
        paths = _ns["get_jac_search_paths"]()
        self.assertIn(os.getcwd(), paths)

    def test_jac_search_paths_with_base(self) -> None:
        paths = _ns["get_jac_search_paths"]("/tmp/testbase")
        self.assertEqual(paths[0], "/tmp/testbase")

    def test_jac_search_paths_no_duplicates(self) -> None:
        paths = _ns["get_jac_search_paths"]()
        self.assertEqual(len(paths), len(set(paths)))

    def test_py_search_paths_not_empty(self) -> None:
        paths = _ns["get_py_search_paths"]()
        self.assertGreater(len(paths), 0)

    def test_py_search_paths_with_base(self) -> None:
        paths = _ns["get_py_search_paths"]("/tmp/pybase")
        self.assertIn("/tmp/pybase", paths)


# =============================================================================
# resolve_module Tests
# =============================================================================


class TestResolveModule(unittest.TestCase):
    """Test module resolution."""

    def test_resolve_stdlib_module(self) -> None:
        path, lang = _ns["resolve_module"]("os", "/tmp/test.py")
        self.assertIn(lang, ("py", "pyi"))

    def test_resolve_stdlib_json(self) -> None:
        path, lang = _ns["resolve_module"]("json", "/tmp/test.py")
        self.assertIn(lang, ("py", "pyi"))

    def test_infer_language_os(self) -> None:
        lang = _ns["infer_language"]("os", "/tmp/test.py")
        self.assertIn(lang, ("py", "pyi"))

    def test_resolve_relative_path(self) -> None:
        path = _ns["resolve_relative_path"]("os", "/tmp/test.py")
        self.assertTrue(path.endswith((".py", ".pyi")))

    def test_resolve_with_temp_jac_file(self) -> None:
        td = tempfile.mkdtemp()
        jac_file = os.path.join(td, "mymod.jac")
        with open(jac_file, "w") as f:
            f.write("# test")
        base = os.path.join(td, "main.jac")
        path, lang = _ns["resolve_module"]("mymod", base)
        self.assertEqual(lang, "jac")
        self.assertTrue(path.endswith("mymod.jac"))
        shutil.rmtree(td)


if __name__ == "__main__":
    unittest.main()
