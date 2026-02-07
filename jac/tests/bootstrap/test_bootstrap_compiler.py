"""Tests for the bootstrap compiler orchestration (Layer 1).

Tests the full pipeline: read source -> parse -> discover impls -> merge
-> symtab -> codegen -> Python. Also tests bytecode caching, module
compilation, and self-compilation of all Layer 1 .jac files.
"""

import os
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


# Load all Layer 1 modules in dependency order
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
_symtab_ns = _load_module(
    "jaclang.bootstrap.bootstrap_symtab",
    "jac/jaclang/bootstrap/bootstrap_symtab.jac",
)
_compiler_ns = _load_module(
    "jaclang.bootstrap.bootstrap_compiler",
    "jac/jaclang/bootstrap/bootstrap_compiler.jac",
)

BootstrapCompiler = _compiler_ns["BootstrapCompiler"]
BootstrapBytecodeCache = _compiler_ns["BootstrapBytecodeCache"]
CacheEntry = _compiler_ns["CacheEntry"]

JAC_BOOTSTRAP_DIR = "jac/jaclang/bootstrap"


# =============================================================================
# Module Load Tests
# =============================================================================


class TestCompilerModuleLoads(unittest.TestCase):
    """Verify the compiler module loaded successfully via seed."""

    def test_compiler_class_loaded(self) -> None:
        self.assertIn("BootstrapCompiler", _compiler_ns)

    def test_cache_class_loaded(self) -> None:
        self.assertIn("BootstrapBytecodeCache", _compiler_ns)

    def test_cache_entry_loaded(self) -> None:
        self.assertIn("CacheEntry", _compiler_ns)

    def test_public_api_loaded(self) -> None:
        self.assertIn("get_compiler", _compiler_ns)
        self.assertIn("bootstrap_compile", _compiler_ns)
        self.assertIn("bootstrap_exec", _compiler_ns)


# =============================================================================
# Compiler Pipeline Tests
# =============================================================================


class TestBootstrapCompilerPipeline(unittest.TestCase):
    """Test the compile_file pipeline with real Jac source files."""

    def setUp(self) -> None:
        self.tmpdir = tempfile.mkdtemp()
        self.compiler = BootstrapCompiler()

    def tearDown(self) -> None:
        import shutil

        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def _write_jac(self, name: str, content: str) -> str:
        path = os.path.join(self.tmpdir, name)
        with open(path, "w") as f:
            f.write(content)
        return path

    def test_compile_simple_obj(self) -> None:
        path = self._write_jac("simple.jac", "obj Foo { has x: int = 0; }")
        py = self.compiler.compile_file(path)
        self.assertIn("class Foo", py)
        self.assertIn("x: int = 0", py)

    def test_compile_function(self) -> None:
        path = self._write_jac(
            "func.jac", "def add(a: int, b: int) -> int { return a + b; }"
        )
        py = self.compiler.compile_file(path)
        self.assertIn("def add(a: int, b: int) -> int:", py)

    def test_compile_with_impl(self) -> None:
        path = self._write_jac(
            "impl_test.jac",
            "obj Foo { has x: int = 0; }\n"
            "impl Foo { def get() -> int { return self.x; } }",
        )
        py = self.compiler.compile_file(path)
        self.assertIn("class Foo", py)
        self.assertIn("Foo.get = _impl_Foo_get", py)

    def test_compile_enum(self) -> None:
        path = self._write_jac(
            "enum_test.jac", 'enum Color { RED = "red", BLUE = "blue" }'
        )
        py = self.compiler.compile_file(path)
        self.assertIn("class Color", py)
        self.assertIn('RED = "red"', py)

    def test_compile_caches_result(self) -> None:
        path = self._write_jac("cached.jac", "obj Foo { has x: int = 0; }")
        py1 = self.compiler.compile_file(path)
        py2 = self.compiler.compile_file(path)
        self.assertEqual(py1, py2)
        # Second call should return from compiled_modules cache
        abs_path = os.path.abspath(path)
        self.assertIn(abs_path, self.compiler.compiled_modules)

    def test_compile_generates_valid_python(self) -> None:
        path = self._write_jac(
            "valid.jac",
            'obj Foo { has x: int = 0, y: str = "hello"; }\n'
            "impl Foo { def greet() -> str { return self.y; } }\n"
            "def main() -> None { pass; }",
        )
        py = self.compiler.compile_file(path)
        # Should compile as valid Python
        code = compile(py, "<test>", "exec")
        self.assertIsNotNone(code)

    def test_compile_and_exec(self) -> None:
        path = self._write_jac(
            "exec_test.jac",
            "obj Point { has x: int = 0, y: int = 0; }\nglob p = Point(x=3, y=4);",
        )
        ns = self.compiler.compile_and_exec(path, None)
        self.assertEqual(ns["p"].x, 3)
        self.assertEqual(ns["p"].y, 4)

    def test_compile_to_code(self) -> None:
        path = self._write_jac("code_test.jac", "glob x: int = 42;")
        code_obj = self.compiler.compile_to_code(path)
        self.assertIsNotNone(code_obj)
        ns: dict = {}
        exec(code_obj, ns)
        self.assertEqual(ns["x"], 42)


# =============================================================================
# Impl File Integration Tests
# =============================================================================


class TestImplFileIntegration(unittest.TestCase):
    """Test compile_file with separate .impl.jac files."""

    def setUp(self) -> None:
        self.tmpdir = tempfile.mkdtemp()
        self.compiler = BootstrapCompiler()

    def tearDown(self) -> None:
        import shutil

        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def _write(self, name: str, content: str) -> str:
        path = os.path.join(self.tmpdir, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(content)
        return path

    def test_same_dir_impl_file(self) -> None:
        src = self._write("foo.jac", "obj Foo { has x: int = 0; }")
        self._write("foo.impl.jac", "impl Foo { def get() -> int { return self.x; } }")
        py = self.compiler.compile_file(src)
        self.assertIn("Foo.get = _impl_Foo_get", py)

    def test_module_folder_impl_file(self) -> None:
        src = self._write("bar.jac", 'obj Bar { has y: str = ""; }')
        self._write(
            "bar.impl/methods.impl.jac",
            "impl Bar { def get_y() -> str { return self.y; } }",
        )
        py = self.compiler.compile_file(src)
        self.assertIn("Bar.get_y = _impl_Bar_get_y", py)


# =============================================================================
# Bytecode Cache Tests
# =============================================================================


class TestBytecodeCache(unittest.TestCase):
    """Test the BootstrapBytecodeCache."""

    def setUp(self) -> None:
        self.cache = BootstrapBytecodeCache()
        self.tmpdir = tempfile.mkdtemp()
        self.cache.cache_dir = self.tmpdir

    def tearDown(self) -> None:
        import shutil

        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_cache_path_generation(self) -> None:
        path = self.cache.get_cache_path("/some/path/test.jac")
        self.assertTrue(path.endswith(".jbc"))
        self.assertIn(self.tmpdir, path)

    def test_cache_path_replaces_separators(self) -> None:
        path = self.cache.get_cache_path("/some/path/test.jac")
        basename = os.path.basename(path)
        self.assertNotIn("/", basename)

    def test_save_and_load(self) -> None:
        # Create a real source file so get_cache_path can resolve it
        src = os.path.join(self.tmpdir, "test.jac")
        with open(src, "w") as f:
            f.write("obj Foo {}")
        data = b"fake bytecode data"
        self.cache.save_cache(src, data)
        loaded = self.cache.load_cached(src)
        self.assertEqual(loaded, data)

    def test_load_nonexistent(self) -> None:
        result = self.cache.load_cached("/nonexistent/file.jac")
        self.assertIsNone(result)

    def test_init_cache_dir(self) -> None:
        cache = BootstrapBytecodeCache()
        result = cache.init_cache_dir()
        self.assertTrue(os.path.isdir(result))
        self.assertIn(".cache", result)

    def test_cache_entry_creation(self) -> None:
        entry = CacheEntry(
            source_path="/test.jac",
            cache_path="/cache/test.jbc",
            source_mtime=123.0,
            valid=True,
        )
        self.assertEqual(entry.source_path, "/test.jac")
        self.assertTrue(entry.valid)


# =============================================================================
# Self-Compilation Tests
# =============================================================================


class TestBootstrapSelfCompile(unittest.TestCase):
    """Test that the seed compiler can compile all Layer 1 .jac files
    and the resulting modules can be loaded and executed."""

    def _seed_compile_and_exec(self, filename: str) -> dict:
        path = os.path.join(JAC_BOOTSTRAP_DIR, filename)
        code = seed_compile_file(path)
        ns = {"__builtins__": __builtins__}
        exec(code, ns)
        return ns

    def test_compile_bootstrap_ast(self) -> None:
        ns = self._seed_compile_and_exec("bootstrap_ast.jac")
        self.assertIn("AstNode", ns)
        self.assertIn("ModuleNode", ns)

    def test_compile_bootstrap_lexer(self) -> None:
        ns = self._seed_compile_and_exec("bootstrap_lexer.jac")
        self.assertIn("BootstrapLexer", ns)

    def test_compile_bootstrap_parser(self) -> None:
        ns = self._seed_compile_and_exec("bootstrap_parser.jac")
        self.assertIn("BootstrapParser", ns)

    def test_compile_bootstrap_codegen(self) -> None:
        ns = self._seed_compile_and_exec("bootstrap_codegen.jac")
        self.assertIn("BootstrapCodegen", ns)

    def test_compile_bootstrap_symtab(self) -> None:
        ns = self._seed_compile_and_exec("bootstrap_symtab.jac")
        self.assertIn("BootstrapSymtab", ns)
        self.assertIn("Scope", ns)

    def test_compile_bootstrap_compiler(self) -> None:
        ns = self._seed_compile_and_exec("bootstrap_compiler.jac")
        self.assertIn("BootstrapCompiler", ns)
        self.assertIn("BootstrapBytecodeCache", ns)


# =============================================================================
# Public API Tests
# =============================================================================


class TestPublicAPI(unittest.TestCase):
    """Test the public API functions."""

    def test_get_compiler_returns_compiler(self) -> None:
        get_compiler = _compiler_ns["get_compiler"]
        compiler = get_compiler()
        self.assertIsNotNone(compiler)

    def test_get_compiler_returns_same_instance(self) -> None:
        get_compiler = _compiler_ns["get_compiler"]
        c1 = get_compiler()
        c2 = get_compiler()
        self.assertIs(c1, c2)

    def test_bootstrap_compile_function(self) -> None:
        tmpdir = tempfile.mkdtemp()
        try:
            path = os.path.join(tmpdir, "test.jac")
            with open(path, "w") as f:
                f.write("glob x: int = 42;")
            bootstrap_compile = _compiler_ns["bootstrap_compile"]
            py = bootstrap_compile(path)
            self.assertIn("x: int = 42", py)
        finally:
            import shutil

            shutil.rmtree(tmpdir, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
