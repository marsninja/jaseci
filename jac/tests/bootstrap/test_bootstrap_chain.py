"""Tests for the full bootstrap chain: Seed -> Layer 1 -> Python output.

Tests the complete pipeline:
1. Seed compiler (Python) compiles Layer 1 Jac files
2. Layer 1 (parser + codegen) parses Jac source and generates Python
3. Generated Python is valid and executes correctly
"""

import sys
import types
import unittest
from textwrap import dedent
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


# Load all Layer 1 modules once for all tests
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


def jac_to_python(source: str) -> str:
    """Parse Jac source and generate Python source via Layer 1."""
    p = Parser(tokens=[], pos=0, filename="<test>")
    mod = p.parse_module(source, "<test>")
    cg = Codegen()
    return cg.generate(mod)


def jac_exec(source: str) -> dict:
    """Parse Jac, generate Python, compile, and execute."""
    py_source = jac_to_python(source)
    code = compile(py_source, "<test>", "exec")
    ns: dict = {}
    exec(code, ns)
    return ns


class TestBootstrapChainLoads(unittest.TestCase):
    """Verify all Layer 1 modules loaded successfully."""

    def test_ast_module_loaded(self) -> None:
        self.assertIn("AstNode", _ast_ns)
        self.assertIn("ClassNode", _ast_ns)
        self.assertIn("FuncNode", _ast_ns)

    def test_lexer_module_loaded(self) -> None:
        self.assertIn("BootstrapLexer", _lex_ns)

    def test_parser_module_loaded(self) -> None:
        self.assertIn("BootstrapParser", _parser_ns)

    def test_codegen_module_loaded(self) -> None:
        self.assertIn("BootstrapCodegen", _codegen_ns)


class TestBootstrapLexer(unittest.TestCase):
    """Test the Layer 1 lexer (compiled from Jac by seed)."""

    def lex(self, source: str) -> list:
        lexer_cls = _lex_ns["BootstrapLexer"]
        lexer = lexer_cls(source=source, filename="<test>")
        return lexer.tokenize()

    def test_basic_tokens(self) -> None:
        tokens = self.lex("obj Foo { }")
        kinds = [t.kind for t in tokens if t.kind != "EOF"]
        self.assertEqual(kinds, ["KW_OBJ", "NAME", "LBRACE", "RBRACE"])

    def test_operators(self) -> None:
        tokens = self.lex("+ - * / == != <= >= -> //")
        kinds = [t.kind for t in tokens if t.kind != "EOF"]
        self.assertEqual(
            kinds,
            [
                "PLUS",
                "MINUS",
                "STAR",
                "SLASH",
                "EQEQ",
                "NEQ",
                "LTE",
                "GTE",
                "ARROW",
                "DSLASH",
            ],
        )

    def test_fstring(self) -> None:
        tokens = self.lex('f"hello {name}"')
        self.assertEqual(tokens[0].kind, "FSTRING")

    def test_walrus(self) -> None:
        tokens = self.lex("x := 5")
        kinds = [t.kind for t in tokens if t.kind != "EOF"]
        self.assertEqual(kinds, ["NAME", "WALRUS", "INT"])


class TestBootstrapParser(unittest.TestCase):
    """Test the Layer 1 parser (compiled from Jac by seed)."""

    def parse(self, source: str) -> Any:  # noqa: ANN401
        p = Parser(tokens=[], pos=0, filename="<test>")
        return p.parse_module(source, "<test>")

    def test_parse_obj(self) -> None:
        mod = self.parse("obj Foo { has x: int = 0; }")
        self.assertEqual(len(mod.body), 1)
        self.assertEqual(mod.body[0].kind, "obj")
        self.assertEqual(mod.body[0].name, "Foo")

    def test_parse_enum(self) -> None:
        mod = self.parse('enum Color { RED = "red", BLUE = "blue" }')
        self.assertEqual(mod.body[0].kind, "enum")
        self.assertEqual(mod.body[0].name, "Color")

    def test_parse_function(self) -> None:
        mod = self.parse("def add(a: int, b: int) -> int { return a + b; }")
        self.assertEqual(mod.body[0].kind, "func")
        self.assertEqual(mod.body[0].name, "add")

    def test_parse_import(self) -> None:
        mod = self.parse("import from os.path { join, exists }")
        self.assertEqual(mod.body[0].kind, "import")
        self.assertTrue(mod.body[0].is_from)

    def test_parse_impl(self) -> None:
        mod = self.parse(
            dedent("""\
            obj Foo { has x: int = 0; }
            impl Foo { def get() -> int { return self.x; } }
        """)
        )
        self.assertEqual(len(mod.body), 2)
        self.assertEqual(mod.body[1].kind, "impl")

    def test_parse_comprehension(self) -> None:
        mod = self.parse("glob items = [x * 2 for x in range(10)];")
        # Should parse without error
        self.assertEqual(len(mod.body), 1)

    def test_parse_try_except(self) -> None:
        mod = self.parse(
            dedent("""\
            try {
                x = 1;
            } except ValueError as e {
                x = 0;
            }
        """)
        )
        self.assertEqual(mod.body[0].kind, "try")

    def test_parse_dict_comp(self) -> None:
        mod = self.parse("glob d = {k: v for (k, v) in items};")
        self.assertEqual(len(mod.body), 1)


class TestBootstrapCodegen(unittest.TestCase):
    """Test the Layer 1 codegen (compiled from Jac by seed)."""

    def test_simple_obj(self) -> None:
        py = jac_to_python("obj Point { has x: int = 0, y: int = 0; }")
        self.assertIn("class Point(Obj):", py)
        self.assertIn("x: int = 0", py)
        self.assertIn("y: int = 0", py)

    def test_obj_with_inheritance(self) -> None:
        py = jac_to_python("obj Child(Parent) { has z: int = 0; }")
        self.assertIn("class Child(Parent, Obj):", py)

    def test_enum_codegen(self) -> None:
        py = jac_to_python('enum Color { RED = "red", BLUE = "blue" }')
        self.assertIn("class Color(Enum):", py)
        self.assertIn('RED = "red"', py)

    def test_function_codegen(self) -> None:
        py = jac_to_python("def add(a: int, b: int) -> int { return a + b; }")
        self.assertIn("def add(a: int, b: int) -> int:", py)

    def test_impl_codegen(self) -> None:
        py = jac_to_python(
            dedent("""\
            obj Foo { has x: int = 0; }
            impl Foo { def get() -> int { return self.x; } }
        """)
        )
        self.assertIn("Foo.get = _impl_Foo_get", py)

    def test_mutable_defaults(self) -> None:
        py = jac_to_python("obj Container { has items: list[int] = []; }")
        self.assertIn("field(factory=lambda: [])", py)

    def test_import_codegen(self) -> None:
        py = jac_to_python("import from os.path { join, exists }")
        self.assertIn("from os.path import join, exists", py)

    def test_glob_codegen(self) -> None:
        py = jac_to_python("glob x: int = 42;")
        self.assertIn("x: int = 42", py)

    def test_if_elif_else(self) -> None:
        py = jac_to_python(
            dedent("""\
            def check(x: int) -> str {
                if x > 0 { return "pos"; }
                elif x < 0 { return "neg"; }
                else { return "zero"; }
            }
        """)
        )
        self.assertIn("if (x > 0):", py)
        self.assertIn("elif (x < 0):", py)
        self.assertIn("else:", py)

    def test_fstring_codegen(self) -> None:
        py = jac_to_python('glob msg = f"hello {name}";')
        self.assertIn('f"hello {name}"', py)

    def test_for_loop(self) -> None:
        py = jac_to_python("def f() { for x in items { print(x); } }")
        self.assertIn("for x in items:", py)

    def test_while_loop(self) -> None:
        py = jac_to_python("def f() { while True { break; } }")
        self.assertIn("while True:", py)

    def test_comprehension_codegen(self) -> None:
        py = jac_to_python("glob doubled = [x * 2 for x in range(10)];")
        self.assertIn("for x in range(10)]", py)
        self.assertIn("(x * 2)", py)


class TestBootstrapEndToEnd(unittest.TestCase):
    """End-to-end: Jac source -> Python source -> execution."""

    def test_obj_creation(self) -> None:
        ns = jac_exec(
            dedent("""\
            obj Point {
                has x: int = 0, y: int = 0;
            }
            glob p = Point(x=3, y=4);
        """)
        )
        self.assertEqual(ns["p"].x, 3)
        self.assertEqual(ns["p"].y, 4)

    def test_obj_mutable_defaults(self) -> None:
        ns = jac_exec(
            dedent("""\
            obj Container {
                has items: list[int] = [];
            }
            glob a = Container();
            glob b = Container();
            a.items.append(1);
        """)
        )
        self.assertEqual(ns["a"].items, [1])
        self.assertEqual(ns["b"].items, [])

    def test_enum_usage(self) -> None:
        ns = jac_exec(
            dedent("""\
            enum Color {
                RED = "red",
                GREEN = "green"
            }
            glob c = Color.RED;
        """)
        )
        self.assertEqual(ns["c"].value, "red")

    def test_impl_methods(self) -> None:
        ns = jac_exec(
            dedent("""\
            obj Counter {
                has count: int = 0;
            }
            impl Counter {
                def increment() -> None {
                    self.count = self.count + 1;
                }
                def get() -> int {
                    return self.count;
                }
            }
            glob c = Counter();
            c.increment();
            c.increment();
            c.increment();
            glob result = c.get();
        """)
        )
        self.assertEqual(ns["result"], 3)

    def test_function_calls(self) -> None:
        ns = jac_exec(
            dedent("""\
            def factorial(n: int) -> int {
                if n <= 1 {
                    return 1;
                }
                return n * factorial(n - 1);
            }
            glob result = factorial(5);
        """)
        )
        self.assertEqual(ns["result"], 120)

    def test_for_loop_execution(self) -> None:
        ns = jac_exec(
            dedent("""\
            def sum_list(items: list[int]) -> int {
                total = 0;
                for item in items {
                    total = total + item;
                }
                return total;
            }
            glob result = sum_list([1, 2, 3, 4, 5]);
        """)
        )
        self.assertEqual(ns["result"], 15)

    def test_inheritance(self) -> None:
        ns = jac_exec(
            dedent("""\
            obj Animal {
                has name: str = "unknown";
            }
            obj Dog(Animal) {
                has breed: str = "mutt";
            }
            glob d = Dog(name="Rex", breed="Lab");
        """)
        )
        self.assertEqual(ns["d"].name, "Rex")
        self.assertEqual(ns["d"].breed, "Lab")

    def test_dict_operations(self) -> None:
        ns = jac_exec(
            dedent("""\
            glob d = {"a": 1, "b": 2, "c": 3};
            glob total = 0;
            for key in d {
                total = total + d[key];
            }
        """)
        )
        self.assertEqual(ns["total"], 6)

    def test_string_methods(self) -> None:
        ns = jac_exec(
            dedent("""\
            glob msg = "hello world";
            glob upper_msg = msg.upper();
            glob parts = msg.split(" ");
        """)
        )
        self.assertEqual(ns["upper_msg"], "HELLO WORLD")
        self.assertEqual(ns["parts"], ["hello", "world"])

    def test_complex_obj_pattern(self) -> None:
        """Test the codegen/builder pattern used in Layer 1 itself."""
        ns = jac_exec(
            dedent("""\
            obj Builder {
                has lines: list[str] = [],
                    indent: int = 0;
            }
            impl Builder {
                def emit(line: str) -> None {
                    prefix = "";
                    i = 0;
                    while i < self.indent {
                        prefix = prefix + "    ";
                        i = i + 1;
                    }
                    self.lines.append(prefix + line);
                }
                def text() -> str {
                    result = "";
                    for line in self.lines {
                        result = result + line + "\\n";
                    }
                    return result;
                }
            }
            glob b = Builder();
            b.emit("def hello():");
            b.indent = 1;
            b.emit("print('hello')");
            b.indent = 0;
            glob output = b.text();
        """)
        )
        self.assertEqual(ns["output"], "def hello():\n    print('hello')\n")


class TestBootstrapSelfCompile(unittest.TestCase):
    """Test that Layer 1 can parse its OWN source files (not full compile,
    just parse + codegen)."""

    def test_parse_bootstrap_ast_jac(self) -> None:
        """Layer 1 parser can parse bootstrap_ast.jac."""
        with open("jac/jaclang/bootstrap/bootstrap_ast.jac") as f:
            source = f.read()
        p = Parser(tokens=[], pos=0, filename="bootstrap_ast.jac")
        mod = p.parse_module(source, "bootstrap_ast.jac")
        # Should have many obj definitions
        self.assertGreater(len(mod.body), 20)

    def test_parse_and_generate_bootstrap_ast(self) -> None:
        """Layer 1 can parse bootstrap_ast.jac and generate valid Python."""
        with open("jac/jaclang/bootstrap/bootstrap_ast.jac") as f:
            source = f.read()
        py = jac_to_python(source)
        # Verify the generated Python compiles
        compile(py, "bootstrap_ast.jac", "exec")

    def test_parse_bootstrap_lexer_jac(self) -> None:
        """Layer 1 parser can parse bootstrap_lexer.jac."""
        with open("jac/jaclang/bootstrap/bootstrap_lexer.jac") as f:
            source = f.read()
        p = Parser(tokens=[], pos=0, filename="bootstrap_lexer.jac")
        mod = p.parse_module(source, "bootstrap_lexer.jac")
        self.assertGreater(len(mod.body), 1)


if __name__ == "__main__":
    unittest.main()
