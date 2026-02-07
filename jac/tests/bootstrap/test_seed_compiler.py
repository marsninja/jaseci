"""Tests for the Layer 0 Seed Compiler."""

import sys
import unittest
from textwrap import dedent

sys.path.insert(0, "/home/marsninja/repos/j3/jac")

from jaclang.bootstrap.seed_compiler import Lexer, seed_compile, seed_exec


class TestLexer(unittest.TestCase):
    """Test the Jac subset lexer."""

    def lex(self, source: str) -> list:
        return Lexer(source).tokenize()

    def token_kinds(self, source: str) -> list[str]:
        return [t.kind for t in self.lex(source) if t.kind != "EOF"]

    def test_basic_tokens(self) -> None:
        tokens = self.token_kinds("obj Foo { }")
        self.assertEqual(tokens, ["KW_OBJ", "NAME", "LBRACE", "RBRACE"])

    def test_keywords(self) -> None:
        tokens = self.token_kinds("if else while for in return")
        self.assertEqual(
            tokens, ["KW_IF", "KW_ELSE", "KW_WHILE", "KW_FOR", "KW_IN", "KW_RETURN"]
        )

    def test_operators(self) -> None:
        tokens = self.token_kinds("+ - * / == != <= >= -> //")
        self.assertEqual(
            tokens,
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

    def test_numbers(self) -> None:
        tokens = self.lex("42 3.14 1_000")
        nums = [(t.kind, t.value) for t in tokens if t.kind != "EOF"]
        self.assertEqual(nums, [("INT", "42"), ("FLOAT", "3.14"), ("INT", "1_000")])

    def test_string(self) -> None:
        tokens = self.lex('"hello world"')
        self.assertEqual(tokens[0].kind, "STRING")
        self.assertEqual(tokens[0].value, '"hello world"')

    def test_fstring(self) -> None:
        tokens = self.lex('f"hello {name}"')
        self.assertEqual(tokens[0].kind, "FSTRING")

    def test_comments(self) -> None:
        tokens = self.token_kinds("x # comment\ny")
        self.assertEqual(tokens, ["NAME", "NAME"])

    def test_floor_div_token(self) -> None:
        tokens = self.token_kinds("x // y")
        self.assertEqual(tokens, ["NAME", "DSLASH", "NAME"])

    def test_triple_quoted_string(self) -> None:
        tokens = self.lex('"""hello\nworld"""')
        self.assertEqual(tokens[0].kind, "STRING")

    def test_augmented_assign(self) -> None:
        tokens = self.token_kinds("x += 1; y -= 2;")
        self.assertEqual(
            tokens,
            ["NAME", "PLUS_EQ", "INT", "SEMI", "NAME", "MINUS_EQ", "INT", "SEMI"],
        )


class TestSeedCompilerBasic(unittest.TestCase):
    """Test basic compilation of Jac subset to Python."""

    def compile_and_exec(self, source: str) -> dict:
        """Compile Jac source and execute, returning namespace."""
        return seed_exec(source, "<test>")

    def test_glob_int(self) -> None:
        ns = self.compile_and_exec("glob x: int = 42;")
        self.assertEqual(ns["x"], 42)

    def test_glob_string(self) -> None:
        ns = self.compile_and_exec('glob msg: str = "hello";')
        self.assertEqual(ns["msg"], "hello")

    def test_glob_no_type(self) -> None:
        ns = self.compile_and_exec("glob x = 10;")
        self.assertEqual(ns["x"], 10)

    def test_glob_multiple(self) -> None:
        ns = self.compile_and_exec("glob a = 1, b = 2;")
        self.assertEqual(ns["a"], 1)
        self.assertEqual(ns["b"], 2)

    def test_simple_function(self) -> None:
        ns = self.compile_and_exec(
            dedent("""\
            def add(a: int, b: int) -> int {
                return a + b;
            }
        """)
        )
        self.assertEqual(ns["add"](3, 4), 7)

    def test_can_function(self) -> None:
        ns = self.compile_and_exec(
            dedent("""\
            can multiply(a: int, b: int) -> int {
                return a * b;
            }
        """)
        )
        self.assertEqual(ns["multiply"](3, 4), 12)

    def test_function_default_param(self) -> None:
        ns = self.compile_and_exec(
            dedent("""\
            def greet(name: str = "world") -> str {
                return "hello " + name;
            }
        """)
        )
        self.assertEqual(ns["greet"](), "hello world")
        self.assertEqual(ns["greet"]("jac"), "hello jac")


class TestSeedCompilerObj(unittest.TestCase):
    """Test obj compilation."""

    def compile_and_exec(self, source: str) -> dict:
        return seed_exec(source, "<test>")

    def test_empty_obj(self) -> None:
        ns = self.compile_and_exec("obj Empty { }")
        self.assertIn("Empty", ns)
        e = ns["Empty"]()
        self.assertIsNotNone(e)

    def test_obj_with_fields(self) -> None:
        ns = self.compile_and_exec(
            dedent("""\
            obj Point {
                has x: int = 0,
                    y: int = 0;
            }
        """)
        )
        p = ns["Point"](x=3, y=4)
        self.assertEqual(p.x, 3)
        self.assertEqual(p.y, 4)

    def test_obj_default_values(self) -> None:
        ns = self.compile_and_exec(
            dedent("""\
            obj Config {
                has name: str = "default",
                    value: int = 0;
            }
        """)
        )
        c = ns["Config"]()
        self.assertEqual(c.name, "default")
        self.assertEqual(c.value, 0)

    def test_obj_mutable_default(self) -> None:
        ns = self.compile_and_exec(
            dedent("""\
            obj Container {
                has items: list[int] = [];
            }
        """)
        )
        c1 = ns["Container"]()
        c2 = ns["Container"]()
        c1.items.append(1)
        # Ensure mutable defaults are NOT shared
        self.assertEqual(c1.items, [1])
        self.assertEqual(c2.items, [])

    def test_obj_inheritance(self) -> None:
        ns = self.compile_and_exec(
            dedent("""\
            obj Base {
                has x: int = 0;
            }
            obj Child(Base) {
                has y: int = 0;
            }
        """)
        )
        c = ns["Child"](x=1, y=2)
        self.assertEqual(c.x, 1)
        self.assertEqual(c.y, 2)
        self.assertIsInstance(c, ns["Base"])

    def test_obj_with_methods(self) -> None:
        ns = self.compile_and_exec(
            dedent("""\
            obj Counter {
                has count: int = 0;
                def increment() -> None {
                    self.count = self.count + 1;
                }
                def get_count() -> int {
                    return self.count;
                }
            }
        """)
        )
        c = ns["Counter"]()
        c.increment()
        c.increment()
        self.assertEqual(c.get_count(), 2)


class TestSeedCompilerEnum(unittest.TestCase):
    """Test enum compilation."""

    def compile_and_exec(self, source: str) -> dict:
        return seed_exec(source, "<test>")

    def test_basic_enum(self) -> None:
        ns = self.compile_and_exec(
            dedent("""\
            enum Color {
                RED = "red",
                GREEN = "green",
                BLUE = "blue"
            }
        """)
        )
        self.assertEqual(ns["Color"].RED.value, "red")
        self.assertEqual(ns["Color"].GREEN.value, "green")

    def test_enum_int_values(self) -> None:
        ns = self.compile_and_exec(
            dedent("""\
            enum Priority {
                LOW = 1,
                MEDIUM = 2,
                HIGH = 3
            }
        """)
        )
        self.assertEqual(ns["Priority"].LOW.value, 1)
        self.assertEqual(ns["Priority"].HIGH.value, 3)


class TestSeedCompilerImpl(unittest.TestCase):
    """Test impl block compilation."""

    def compile_and_exec(self, source: str) -> dict:
        return seed_exec(source, "<test>")

    def test_impl_block(self) -> None:
        ns = self.compile_and_exec(
            dedent("""\
            obj Dog {
                has name: str = "Rex",
                    age: int = 0;
            }
            impl Dog {
                def bark() -> str {
                    return self.name + " says woof!";
                }
            }
        """)
        )
        d = ns["Dog"](name="Buddy", age=3)
        self.assertEqual(d.bark(), "Buddy says woof!")

    def test_impl_single_method(self) -> None:
        ns = self.compile_and_exec(
            dedent("""\
            obj Cat {
                has name: str = "Kitty";
            }
            impl Cat.meow() -> str {
                return self.name + " says meow!";
            }
        """)
        )
        c = ns["Cat"]()
        self.assertEqual(c.meow(), "Kitty says meow!")

    def test_impl_multiple_methods(self) -> None:
        ns = self.compile_and_exec(
            dedent("""\
            obj Calculator {
                has result: int = 0;
            }
            impl Calculator {
                def add(x: int) -> None {
                    self.result = self.result + x;
                }
                def sub(x: int) -> None {
                    self.result = self.result - x;
                }
                def get() -> int {
                    return self.result;
                }
            }
        """)
        )
        c = ns["Calculator"]()
        c.add(10)
        c.sub(3)
        self.assertEqual(c.get(), 7)


class TestSeedCompilerImport(unittest.TestCase):
    """Test import statement compilation."""

    def test_import_from(self) -> None:
        code = seed_compile(
            dedent("""\
            import from os.path { join, exists }
        """)
        )
        ns: dict = {}
        exec(code, ns)
        import os.path

        self.assertEqual(ns["join"], os.path.join)

    def test_import_simple(self) -> None:
        code = seed_compile("import os;")
        ns: dict = {}
        exec(code, ns)
        import os as os_mod

        self.assertEqual(ns["os"], os_mod)


class TestSeedCompilerControlFlow(unittest.TestCase):
    """Test control flow compilation."""

    def compile_and_exec(self, source: str) -> dict:
        return seed_exec(source, "<test>")

    def test_if_else(self) -> None:
        ns = self.compile_and_exec(
            dedent("""\
            def check(x: int) -> str {
                if x > 0 {
                    return "pos";
                } elif x < 0 {
                    return "neg";
                } else {
                    return "zero";
                }
            }
        """)
        )
        self.assertEqual(ns["check"](5), "pos")
        self.assertEqual(ns["check"](-3), "neg")
        self.assertEqual(ns["check"](0), "zero")

    def test_while_loop(self) -> None:
        ns = self.compile_and_exec(
            dedent("""\
            def sum_to(n: int) -> int {
                total = 0;
                i = 0;
                while i < n {
                    i = i + 1;
                    total = total + i;
                }
                return total;
            }
        """)
        )
        self.assertEqual(ns["sum_to"](5), 15)

    def test_for_loop(self) -> None:
        ns = self.compile_and_exec(
            dedent("""\
            def sum_list(items: list[int]) -> int {
                total = 0;
                for item in items {
                    total = total + item;
                }
                return total;
            }
        """)
        )
        self.assertEqual(ns["sum_list"]([1, 2, 3, 4]), 10)

    def test_for_tuple_unpack(self) -> None:
        ns = self.compile_and_exec(
            dedent("""\
            def sum_pairs(pairs: list) -> int {
                total = 0;
                for (a, b) in pairs {
                    total = total + a + b;
                }
                return total;
            }
        """)
        )
        self.assertEqual(ns["sum_pairs"]([(1, 2), (3, 4)]), 10)

    def test_break_continue(self) -> None:
        ns = self.compile_and_exec(
            dedent("""\
            def first_even(items: list[int]) -> int {
                for item in items {
                    if item % 2 == 0 {
                        return item;
                    }
                }
                return 0;
            }
        """)
        )
        self.assertEqual(ns["first_even"]([1, 3, 4, 6]), 4)


class TestSeedCompilerExpressions(unittest.TestCase):
    """Test expression compilation."""

    def compile_and_exec(self, source: str) -> dict:
        return seed_exec(source, "<test>")

    def test_arithmetic(self) -> None:
        ns = self.compile_and_exec("glob x = 2 + 3 * 4;")
        self.assertEqual(ns["x"], 14)

    def test_comparison(self) -> None:
        ns = self.compile_and_exec(
            dedent("""\
            glob a = 1 < 2;
            glob b = 3 >= 3;
            glob c = 4 == 5;
        """)
        )
        self.assertTrue(ns["a"])
        self.assertTrue(ns["b"])
        self.assertFalse(ns["c"])

    def test_boolean_ops(self) -> None:
        ns = self.compile_and_exec(
            dedent("""\
            glob x = True and False;
            glob y = True or False;
            glob z = not True;
        """)
        )
        self.assertFalse(ns["x"])
        self.assertTrue(ns["y"])
        self.assertFalse(ns["z"])

    def test_ternary(self) -> None:
        ns = self.compile_and_exec(
            dedent("""\
            glob x = "yes" if True else "no";
            glob y = "yes" if False else "no";
        """)
        )
        self.assertEqual(ns["x"], "yes")
        self.assertEqual(ns["y"], "no")

    def test_in_operator(self) -> None:
        ns = self.compile_and_exec(
            dedent("""\
            def has_item(items: list, val: int) -> bool {
                return val in items;
            }
        """)
        )
        self.assertTrue(ns["has_item"]([1, 2, 3], 2))
        self.assertFalse(ns["has_item"]([1, 2, 3], 5))

    def test_not_in_operator(self) -> None:
        ns = self.compile_and_exec(
            dedent("""\
            def missing(items: list, val: int) -> bool {
                return val not in items;
            }
        """)
        )
        self.assertTrue(ns["missing"]([1, 2, 3], 5))

    def test_is_operator(self) -> None:
        ns = self.compile_and_exec(
            dedent("""\
            def is_none(x: int) -> bool {
                return x is None;
            }
        """)
        )
        self.assertTrue(ns["is_none"](None))
        self.assertFalse(ns["is_none"](5))

    def test_string_concat(self) -> None:
        ns = self.compile_and_exec('glob msg = "hello" + " " + "world";')
        self.assertEqual(ns["msg"], "hello world")

    def test_augmented_assign(self) -> None:
        ns = self.compile_and_exec(
            dedent("""\
            def count_up() -> int {
                x = 0;
                x += 5;
                x -= 2;
                return x;
            }
        """)
        )
        self.assertEqual(ns["count_up"](), 3)

    def test_dict_literal(self) -> None:
        ns = self.compile_and_exec('glob d = {"a": 1, "b": 2};')
        self.assertEqual(ns["d"], {"a": 1, "b": 2})

    def test_list_literal(self) -> None:
        ns = self.compile_and_exec("glob items = [1, 2, 3];")
        self.assertEqual(ns["items"], [1, 2, 3])

    def test_tuple_literal(self) -> None:
        ns = self.compile_and_exec("glob t = (1, 2, 3);")
        self.assertEqual(ns["t"], (1, 2, 3))

    def test_floor_division(self) -> None:
        ns = self.compile_and_exec("glob x = 7 // 2;")
        self.assertEqual(ns["x"], 3)

    def test_modulo(self) -> None:
        ns = self.compile_and_exec("glob x = 10 % 3;")
        self.assertEqual(ns["x"], 1)

    def test_method_call(self) -> None:
        ns = self.compile_and_exec(
            dedent("""\
            glob items = [1, 2, 3];
            items.append(4);
        """)
        )
        self.assertEqual(ns["items"], [1, 2, 3, 4])

    def test_subscript(self) -> None:
        ns = self.compile_and_exec(
            dedent("""\
            glob items = [10, 20, 30];
            glob x = items[1];
        """)
        )
        self.assertEqual(ns["x"], 20)

    def test_kwarg_call(self) -> None:
        ns = self.compile_and_exec(
            dedent("""\
            obj Point {
                has x: int = 0, y: int = 0;
            }
            glob p = Point(x=3, y=4);
        """)
        )
        self.assertEqual(ns["p"].x, 3)
        self.assertEqual(ns["p"].y, 4)

    def test_unary_minus(self) -> None:
        ns = self.compile_and_exec("glob x = -5;")
        self.assertEqual(ns["x"], -5)


class TestSeedCompilerFStrings(unittest.TestCase):
    """Test f-string compilation."""

    def compile_and_exec(self, source: str) -> dict:
        return seed_exec(source, "<test>")

    def test_simple_fstring(self) -> None:
        ns = self.compile_and_exec(
            dedent("""\
            glob name = "world";
            glob msg = f"hello {name}";
        """)
        )
        self.assertEqual(ns["msg"], "hello world")

    def test_fstring_expr(self) -> None:
        ns = self.compile_and_exec(
            dedent("""\
            glob x = 3;
            glob msg = f"x is {x + 1}";
        """)
        )
        self.assertEqual(ns["msg"], "x is 4")

    def test_fstring_multiple(self) -> None:
        ns = self.compile_and_exec(
            dedent("""\
            glob a = 1;
            glob b = 2;
            glob msg = f"{a} + {b} = {a + b}";
        """)
        )
        self.assertEqual(ns["msg"], "1 + 2 = 3")

    def test_fstring_method_call(self) -> None:
        ns = self.compile_and_exec(
            dedent("""\
            glob name = "hello";
            glob msg = f"upper: {name.upper()}";
        """)
        )
        self.assertEqual(ns["msg"], "upper: HELLO")


class TestSeedCompilerIntegration(unittest.TestCase):
    """Integration tests: realistic Layer 1-like code patterns."""

    def compile_and_exec(self, source: str) -> dict:
        return seed_exec(source, "<test>")

    def test_linked_list(self) -> None:
        """Test a simple linked list (Layer 1-like pattern)."""
        ns = self.compile_and_exec(
            dedent("""\
            obj ListNode {
                has value: int = 0,
                    next: ListNode | None = None;
            }
            def make_list(items: list[int]) -> ListNode | None {
                head: ListNode | None = None;
                i = len(items) - 1;
                while i >= 0 {
                    node = ListNode(value=items[i], next=head);
                    head = node;
                    i = i - 1;
                }
                return head;
            }
            def list_sum(head: ListNode | None) -> int {
                total = 0;
                curr = head;
                while curr is not None {
                    total = total + curr.value;
                    curr = curr.next;
                }
                return total;
            }
        """)
        )
        head = ns["make_list"]([1, 2, 3, 4, 5])
        self.assertEqual(ns["list_sum"](head), 15)

    def test_ast_like_pattern(self) -> None:
        """Test obj hierarchy (mimics bootstrap AST nodes)."""
        ns = self.compile_and_exec(
            dedent("""\
            obj AstNode {
                has kind: str = "";
            }
            obj ExprNode(AstNode) {
                has op: str = "";
            }
            obj BinExpr(ExprNode) {
                has left: AstNode | None = None,
                    right: AstNode | None = None;
            }
            obj LitExpr(ExprNode) {
                has value: str = "";
            }
            def eval_expr(node: AstNode) -> int {
                if node.kind == "lit" {
                    return int(node.value);
                }
                if node.kind == "bin" {
                    left_val = eval_expr(node.left);
                    right_val = eval_expr(node.right);
                    if node.op == "+" {
                        return left_val + right_val;
                    }
                    if node.op == "*" {
                        return left_val * right_val;
                    }
                }
                return 0;
            }
            glob l1 = LitExpr(kind="lit", value="3");
            glob l2 = LitExpr(kind="lit", value="4");
            glob add = BinExpr(kind="bin", op="+", left=l1, right=l2);
            glob result = eval_expr(add);
        """)
        )
        self.assertEqual(ns["result"], 7)

    def test_enum_with_obj(self) -> None:
        """Test enum + obj pattern (Layer 1 token types)."""
        ns = self.compile_and_exec(
            dedent("""\
            enum TokenKind {
                NAME = "NAME",
                INT = "INT",
                PLUS = "PLUS",
                EOF = "EOF"
            }
            obj Token {
                has kind: str = "",
                    value: str = "",
                    line: int = 0;
            }
            def make_token(kind: str, value: str, line: int) -> Token {
                return Token(kind=kind, value=value, line=line);
            }
            glob t = make_token("NAME", "foo", 1);
        """)
        )
        self.assertEqual(ns["t"].kind, "NAME")
        self.assertEqual(ns["t"].value, "foo")
        self.assertEqual(ns["t"].line, 1)

    def test_string_builder_pattern(self) -> None:
        """Test the codegen string builder pattern."""
        ns = self.compile_and_exec(
            dedent("""\
            obj CodeBuilder {
                has lines: list[str] = [],
                    indent: int = 0;
            }
            impl CodeBuilder {
                def emit(line: str) -> None {
                    prefix = "";
                    i = 0;
                    while i < self.indent {
                        prefix = prefix + "    ";
                        i = i + 1;
                    }
                    self.lines.append(prefix + line);
                }
                def get_output() -> str {
                    result = "";
                    for line in self.lines {
                        result = result + line + "\\n";
                    }
                    return result;
                }
            }
            glob cb = CodeBuilder();
            cb.emit("class Foo:");
            cb.indent = 1;
            cb.emit("x: int = 0");
            cb.indent = 0;
            glob output = cb.get_output();
        """)
        )
        expected = "class Foo:\n    x: int = 0\n"
        self.assertEqual(ns["output"], expected)

    def test_dict_operations(self) -> None:
        """Test dict operations (symbol table pattern)."""
        ns = self.compile_and_exec(
            dedent("""\
            obj SymTable {
                has symbols: dict[str, str] = {};
            }
            impl SymTable {
                def define(name: str, kind: str) -> None {
                    self.symbols[name] = kind;
                }
                def lookup(name: str) -> str | None {
                    if name in self.symbols {
                        return self.symbols[name];
                    }
                    return None;
                }
            }
            glob st = SymTable();
            st.define("x", "var");
            st.define("Foo", "class");
            glob r1 = st.lookup("x");
            glob r2 = st.lookup("missing");
        """)
        )
        self.assertEqual(ns["r1"], "var")
        self.assertIsNone(ns["r2"])


if __name__ == "__main__":
    unittest.main()
