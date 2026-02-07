"""Tests for the bootstrap symbol table (Layer 1).

Tests the Scope, Symbol, and BootstrapSymtab objects compiled from Jac
by the seed compiler. Covers scope management, symbol lookup, impl matching,
and .impl.jac file discovery.
"""

import os
import sys
import tempfile
import types
import unittest
from typing import Any

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


# Load Layer 1 modules needed for symtab tests
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

Scope = _symtab_ns["Scope"]
Symbol = _symtab_ns["Symbol"]
ImplRecord = _symtab_ns["ImplRecord"]
BootstrapSymtab = _symtab_ns["BootstrapSymtab"]
Parser = _parser_ns["BootstrapParser"]


def _parse(source: str) -> Any:  # noqa: ANN401
    """Parse Jac source into a ModuleNode."""
    p = Parser(tokens=[], pos=0, filename="<test>")
    return p.parse_module(source, "<test>")


# =============================================================================
# Scope Tests
# =============================================================================


class TestScope(unittest.TestCase):
    """Test Scope object: define, lookup, parent chain, children."""

    def test_define_and_lookup_local(self) -> None:
        s = Scope(name="test", scope_kind="module")
        sym = s.define("x", "var", None)
        self.assertEqual(sym.name, "x")
        self.assertEqual(sym.kind, "var")
        found = s.lookup_local("x")
        self.assertIsNotNone(found)
        self.assertEqual(found.name, "x")

    def test_lookup_local_missing(self) -> None:
        s = Scope(name="test", scope_kind="module")
        self.assertIsNone(s.lookup_local("missing"))

    def test_lookup_parent_chain(self) -> None:
        parent = Scope(name="mod", scope_kind="module")
        parent.define("x", "var", None)
        child = Scope(name="func", parent=parent, scope_kind="func")
        found = child.lookup("x")
        self.assertIsNotNone(found)
        self.assertEqual(found.name, "x")

    def test_lookup_missing_returns_none(self) -> None:
        parent = Scope(name="mod", scope_kind="module")
        child = Scope(name="func", parent=parent, scope_kind="func")
        self.assertIsNone(child.lookup("missing"))

    def test_shadowing(self) -> None:
        parent = Scope(name="mod", scope_kind="module")
        parent.define("x", "var", None)
        child = Scope(name="func", parent=parent, scope_kind="func")
        child.define("x", "param", None)
        found = child.lookup("x")
        self.assertEqual(found.kind, "param")

    def test_define_with_scope(self) -> None:
        s = Scope(name="mod", scope_kind="module")
        child = s.define_with_scope("Foo", "obj", None, "class")
        self.assertEqual(child.name, "Foo")
        self.assertEqual(child.scope_kind, "class")
        self.assertEqual(child.parent, s)
        self.assertEqual(len(s.children), 1)

    def test_find_child(self) -> None:
        s = Scope(name="mod", scope_kind="module")
        s.define_with_scope("Foo", "obj", None, "class")
        s.define_with_scope("Bar", "obj", None, "class")
        found = s.find_child("Bar")
        self.assertIsNotNone(found)
        self.assertEqual(found.name, "Bar")

    def test_find_child_missing(self) -> None:
        s = Scope(name="mod", scope_kind="module")
        self.assertIsNone(s.find_child("missing"))


# =============================================================================
# BootstrapSymtab Build Tests
# =============================================================================


class TestBootstrapSymtabBuild(unittest.TestCase):
    """Test building symbol tables from parsed Jac modules."""

    def test_build_obj(self) -> None:
        mod = _parse("obj Foo { has x: int = 0; }")
        st = BootstrapSymtab()
        scope = st.build(mod)
        sym = scope.lookup_local("Foo")
        self.assertIsNotNone(sym)
        self.assertEqual(sym.kind, "obj")

    def test_build_obj_fields(self) -> None:
        mod = _parse('obj Foo { has x: int = 0, y: str = ""; }')
        st = BootstrapSymtab()
        scope = st.build(mod)
        foo_sym = scope.lookup_local("Foo")
        self.assertIsNotNone(foo_sym.scope)
        x_sym = foo_sym.scope.lookup_local("x")
        self.assertIsNotNone(x_sym)
        self.assertEqual(x_sym.kind, "field")
        y_sym = foo_sym.scope.lookup_local("y")
        self.assertIsNotNone(y_sym)

    def test_build_obj_with_method(self) -> None:
        mod = _parse(
            "obj Foo { has x: int = 0; def get_x() -> int { return self.x; } }"
        )
        st = BootstrapSymtab()
        scope = st.build(mod)
        foo_sym = scope.lookup_local("Foo")
        get_sym = foo_sym.scope.lookup_local("get_x")
        self.assertIsNotNone(get_sym)
        self.assertEqual(get_sym.kind, "method")

    def test_build_enum(self) -> None:
        mod = _parse('enum Color { RED = "red", BLUE = "blue" }')
        st = BootstrapSymtab()
        scope = st.build(mod)
        sym = scope.lookup_local("Color")
        self.assertIsNotNone(sym)
        self.assertEqual(sym.kind, "enum")
        red = sym.scope.lookup_local("RED")
        self.assertIsNotNone(red)
        self.assertEqual(red.kind, "member")

    def test_build_func(self) -> None:
        mod = _parse("def add(a: int, b: int) -> int { return a + b; }")
        st = BootstrapSymtab()
        scope = st.build(mod)
        sym = scope.lookup_local("add")
        self.assertIsNotNone(sym)
        self.assertEqual(sym.kind, "func")
        a_param = sym.scope.lookup_local("a")
        self.assertIsNotNone(a_param)
        self.assertEqual(a_param.kind, "param")

    def test_build_import_from(self) -> None:
        mod = _parse("import from os.path { join, exists }")
        st = BootstrapSymtab()
        scope = st.build(mod)
        self.assertIsNotNone(scope.lookup_local("join"))
        self.assertIsNotNone(scope.lookup_local("exists"))

    def test_build_import_module(self) -> None:
        mod = _parse("import os;")
        st = BootstrapSymtab()
        scope = st.build(mod)
        self.assertIsNotNone(scope.lookup_local("os"))

    def test_build_glob(self) -> None:
        mod = _parse("glob x: int = 42;")
        st = BootstrapSymtab()
        scope = st.build(mod)
        sym = scope.lookup_local("x")
        self.assertIsNotNone(sym)
        self.assertEqual(sym.kind, "var")

    def test_build_multiple_definitions(self) -> None:
        mod = _parse(
            "obj Foo { has x: int = 0; }\n"
            'obj Bar { has y: str = ""; }\n'
            "def helper() -> None { pass; }\n"
            "glob count: int = 0;\n"
        )
        st = BootstrapSymtab()
        scope = st.build(mod)
        self.assertIsNotNone(scope.lookup_local("Foo"))
        self.assertIsNotNone(scope.lookup_local("Bar"))
        self.assertIsNotNone(scope.lookup_local("helper"))
        self.assertIsNotNone(scope.lookup_local("count"))

    def test_build_nested_scopes(self) -> None:
        mod = _parse(
            "obj Outer { has val: int = 0; def method(x: int) -> int { return x; } }"
        )
        st = BootstrapSymtab()
        scope = st.build(mod)
        outer = scope.lookup_local("Outer")
        self.assertIsNotNone(outer.scope)
        method = outer.scope.lookup_local("method")
        self.assertIsNotNone(method)
        self.assertIsNotNone(method.scope)
        x_param = method.scope.lookup_local("x")
        self.assertIsNotNone(x_param)


# =============================================================================
# Impl Matching Tests
# =============================================================================


class TestImplMatching(unittest.TestCase):
    """Test impl recording and matching to target classes."""

    def test_simple_impl_match(self) -> None:
        mod = _parse(
            "obj Foo { has x: int = 0; }\n"
            "impl Foo { def get() -> int { return self.x; } }"
        )
        st = BootstrapSymtab()
        st.build(mod)
        st.match_impls()
        unmatched = st.get_unmatched_impls()
        self.assertEqual(len(unmatched), 0)

    def test_impl_methods_injected(self) -> None:
        mod = _parse(
            "obj Foo { has x: int = 0; }\n"
            "impl Foo { def get() -> int { return self.x; } }"
        )
        st = BootstrapSymtab()
        st.build(mod)
        st.match_impls()
        foo = st.root_scope.lookup_local("Foo")
        get_sym = foo.scope.lookup_local("get")
        self.assertIsNotNone(get_sym)
        self.assertEqual(get_sym.kind, "method")

    def test_multiple_methods_in_impl(self) -> None:
        mod = _parse(
            "obj Foo { has x: int = 0; }\n"
            "impl Foo {\n"
            "  def get() -> int { return self.x; }\n"
            "  def set(val: int) -> None { self.x = val; }\n"
            "}"
        )
        st = BootstrapSymtab()
        st.build(mod)
        st.match_impls()
        foo = st.root_scope.lookup_local("Foo")
        self.assertIsNotNone(foo.scope.lookup_local("get"))
        self.assertIsNotNone(foo.scope.lookup_local("set"))

    def test_unmatched_impl(self) -> None:
        mod = _parse("impl MissingClass { def get() -> int { return 0; } }")
        st = BootstrapSymtab()
        st.build(mod)
        st.match_impls()
        unmatched = st.get_unmatched_impls()
        self.assertEqual(len(unmatched), 1)
        self.assertEqual(unmatched[0].target_name, "MissingClass")

    def test_multiple_impls_same_target(self) -> None:
        mod = _parse(
            "obj Foo { has x: int = 0; }\n"
            "impl Foo { def get() -> int { return self.x; } }\n"
            "impl Foo { def set(v: int) -> None { self.x = v; } }"
        )
        st = BootstrapSymtab()
        st.build(mod)
        st.match_impls()
        unmatched = st.get_unmatched_impls()
        self.assertEqual(len(unmatched), 0)
        foo = st.root_scope.lookup_local("Foo")
        self.assertIsNotNone(foo.scope.lookup_local("get"))
        self.assertIsNotNone(foo.scope.lookup_local("set"))

    def test_impl_param_symbols(self) -> None:
        mod = _parse(
            "obj Foo { has x: int = 0; }\n"
            "impl Foo { def set(val: int) -> None { self.x = val; } }"
        )
        st = BootstrapSymtab()
        st.build(mod)
        st.match_impls()
        foo = st.root_scope.lookup_local("Foo")
        set_sym = foo.scope.lookup_local("set")
        self.assertIsNotNone(set_sym.scope)
        val_param = set_sym.scope.lookup_local("val")
        self.assertIsNotNone(val_param)
        self.assertEqual(val_param.kind, "param")


# =============================================================================
# Impl File Discovery Tests
# =============================================================================


class TestImplFileDiscovery(unittest.TestCase):
    """Test .impl.jac file discovery in various directory layouts."""

    def setUp(self) -> None:
        self.tmpdir = tempfile.mkdtemp()
        self.st = BootstrapSymtab()

    def tearDown(self) -> None:
        import shutil

        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def _write(self, rel_path: str, content: str = "") -> str:
        full = os.path.join(self.tmpdir, rel_path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w") as f:
            f.write(content)
        return full

    def test_same_dir_impl(self) -> None:
        src = self._write("foo.jac", "obj Foo {}")
        self._write("foo.impl.jac", "impl Foo { def bar() {} }")
        result = self.st.discover_impl_files(src)
        self.assertEqual(len(result), 1)
        self.assertTrue(result[0].endswith("foo.impl.jac"))

    def test_module_folder_impl(self) -> None:
        src = self._write("foo.jac", "obj Foo {}")
        self._write("foo.impl/bar.impl.jac", "impl Foo { def bar() {} }")
        result = self.st.discover_impl_files(src)
        self.assertEqual(len(result), 1)
        self.assertTrue(result[0].endswith("bar.impl.jac"))

    def test_shared_folder_impl(self) -> None:
        src = self._write("foo.jac", "obj Foo {}")
        self._write("impl/foo.impl.jac", "impl Foo { def bar() {} }")
        result = self.st.discover_impl_files(src)
        self.assertEqual(len(result), 1)
        self.assertTrue(result[0].endswith("foo.impl.jac"))

    def test_no_impl_files(self) -> None:
        src = self._write("foo.jac", "obj Foo {}")
        result = self.st.discover_impl_files(src)
        self.assertEqual(len(result), 0)

    def test_impl_file_ignored_for_impl_source(self) -> None:
        src = self._write("foo.impl.jac", "impl Foo {}")
        result = self.st.discover_impl_files(src)
        self.assertEqual(len(result), 0)


# =============================================================================
# Scope Dump Tests
# =============================================================================


class TestScopeDump(unittest.TestCase):
    """Test the debug dump_scope method."""

    def test_dump_produces_output(self) -> None:
        mod = _parse("obj Foo { has x: int = 0; }\ndef bar() -> None { pass; }")
        st = BootstrapSymtab()
        scope = st.build(mod)
        output = st.dump_scope(scope, 0)
        self.assertIn("Foo", output)
        self.assertIn("bar", output)
        self.assertIn("module", output)


if __name__ == "__main__":
    unittest.main()
