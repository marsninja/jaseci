"""Tests for Stage 3: mtp.jac compiled by Layer 1.

Verifies that mtp.jac (the Jac port of mtp.py) can be:
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

MTP_JAC = "jac/jaclang/pycore/stage3/mtp.jac"


def _compile_mtp_jac() -> dict:
    """Parse and compile mtp.jac, return the exec'd namespace."""
    with open(MTP_JAC) as f:
        source = f.read()
    p = Parser(tokens=[], pos=0, filename="mtp.jac")
    mod = p.parse_module(source, "mtp.jac")
    cg = Codegen()
    py = cg.generate(mod)
    code = compile(py, "mtp.jac", "exec")
    ns: dict = {}
    exec(code, ns)
    return ns


# Compile once for all tests
_ns = _compile_mtp_jac()


# =============================================================================
# Compile Tests
# =============================================================================


class TestMtpJacCompiles(unittest.TestCase):
    """Verify mtp.jac can be parsed and compiled."""

    def test_parse_succeeds(self) -> None:
        with open(MTP_JAC) as f:
            source = f.read()
        p = Parser(tokens=[], pos=0, filename="mtp.jac")
        mod = p.parse_module(source, "mtp.jac")
        self.assertGreater(len(mod.body), 10)

    def test_codegen_produces_valid_python(self) -> None:
        with open(MTP_JAC) as f:
            source = f.read()
        p = Parser(tokens=[], pos=0, filename="mtp.jac")
        mod = p.parse_module(source, "mtp.jac")
        cg = Codegen()
        py = cg.generate(mod)
        code = compile(py, "mtp.jac", "exec")
        self.assertIsNotNone(code)

    def test_all_classes_present(self) -> None:
        for name in [
            "Info",
            "VarInfo",
            "ParamInfo",
            "FieldInfo",
            "EnumInfo",
            "ClassInfo",
            "FunctionInfo",
            "MethodInfo",
            "MTRuntime",
            "MTIR",
        ]:
            self.assertIn(name, _ns, f"{name} not found in namespace")

    def test_all_functions_present(self) -> None:
        for name in [
            "mk_list",
            "mk_dict",
            "mk_tuple",
            "mk_union",
            "is_list_type",
            "is_dict_type",
            "is_tuple_type",
            "is_union_type",
            "inner_types",
            "type_to_str",
        ]:
            self.assertIn(name, _ns, f"{name} not found in namespace")


# =============================================================================
# Info Hierarchy Tests
# =============================================================================


class TestInfo(unittest.TestCase):
    """Test Info base obj."""

    def test_defaults(self) -> None:
        info = _ns["Info"]()
        self.assertEqual(info.name, "")
        self.assertIsNone(info.semstr)

    def test_constructor(self) -> None:
        info = _ns["Info"](name="foo", semstr="a foo")
        self.assertEqual(info.name, "foo")
        self.assertEqual(info.semstr, "a foo")


class TestVarInfo(unittest.TestCase):
    """Test VarInfo obj with inheritance."""

    def test_inherits_info(self) -> None:
        var = _ns["VarInfo"](name="x", type_info="int")
        self.assertIsInstance(var, _ns["Info"])

    def test_defaults(self) -> None:
        var = _ns["VarInfo"]()
        self.assertEqual(var.name, "")
        self.assertIsNone(var.semstr)
        self.assertIsNone(var.type_info)

    def test_constructor(self) -> None:
        var = _ns["VarInfo"](name="x", semstr="count", type_info="int")
        self.assertEqual(var.name, "x")
        self.assertEqual(var.semstr, "count")
        self.assertEqual(var.type_info, "int")


class TestParamInfo(unittest.TestCase):
    """Test ParamInfo inherits from VarInfo."""

    def test_inherits_varinfo(self) -> None:
        param = _ns["ParamInfo"](name="p")
        self.assertIsInstance(param, _ns["VarInfo"])
        self.assertIsInstance(param, _ns["Info"])

    def test_has_type_info(self) -> None:
        param = _ns["ParamInfo"](name="p", type_info="str")
        self.assertEqual(param.type_info, "str")


class TestFieldInfo(unittest.TestCase):
    """Test FieldInfo inherits from VarInfo."""

    def test_inherits_varinfo(self) -> None:
        fi = _ns["FieldInfo"](name="f")
        self.assertIsInstance(fi, _ns["VarInfo"])


class TestEnumInfo(unittest.TestCase):
    """Test EnumInfo obj."""

    def test_defaults(self) -> None:
        ei = _ns["EnumInfo"]()
        self.assertEqual(ei.name, "")
        self.assertEqual(ei.members, [])

    def test_inherits_info(self) -> None:
        ei = _ns["EnumInfo"](name="Color")
        self.assertIsInstance(ei, _ns["Info"])

    def test_mutable_defaults_not_shared(self) -> None:
        e1 = _ns["EnumInfo"](name="A")
        e2 = _ns["EnumInfo"](name="B")
        e1.members.append("RED")
        self.assertEqual(e1.members, ["RED"])
        self.assertEqual(e2.members, [])


class TestClassInfo(unittest.TestCase):
    """Test ClassInfo obj."""

    def test_defaults(self) -> None:
        ci = _ns["ClassInfo"]()
        self.assertEqual(ci.fields, [])
        self.assertEqual(ci.base_classes, [])
        self.assertEqual(ci.methods, [])

    def test_inherits_info(self) -> None:
        ci = _ns["ClassInfo"](name="Foo")
        self.assertIsInstance(ci, _ns["Info"])

    def test_mutable_defaults_not_shared(self) -> None:
        c1 = _ns["ClassInfo"](name="A")
        c2 = _ns["ClassInfo"](name="B")
        c1.fields.append("x")
        self.assertEqual(c1.fields, ["x"])
        self.assertEqual(c2.fields, [])


class TestFunctionInfo(unittest.TestCase):
    """Test FunctionInfo obj."""

    def test_defaults(self) -> None:
        fi = _ns["FunctionInfo"]()
        self.assertIsNone(fi.params)
        self.assertIsNone(fi.return_type)
        self.assertIsNone(fi.tools)
        self.assertFalse(fi.by_call)

    def test_inherits_info(self) -> None:
        fi = _ns["FunctionInfo"](name="add")
        self.assertIsInstance(fi, _ns["Info"])

    def test_constructor(self) -> None:
        fi = _ns["FunctionInfo"](name="add", params=[], return_type="int", by_call=True)
        self.assertEqual(fi.return_type, "int")
        self.assertTrue(fi.by_call)


class TestMethodInfo(unittest.TestCase):
    """Test MethodInfo inherits from FunctionInfo."""

    def test_inherits_function_info(self) -> None:
        mi = _ns["MethodInfo"](name="do")
        self.assertIsInstance(mi, _ns["FunctionInfo"])
        self.assertIsInstance(mi, _ns["Info"])

    def test_parent_class(self) -> None:
        ci = _ns["ClassInfo"](name="Foo")
        mi = _ns["MethodInfo"](name="bar", parent_class=ci)
        self.assertEqual(mi.parent_class.name, "Foo")


# =============================================================================
# MTRuntime / MTIR Tests
# =============================================================================


class TestMTRuntime(unittest.TestCase):
    """Test MTRuntime obj."""

    def test_defaults(self) -> None:
        rt = _ns["MTRuntime"]()
        self.assertIsNone(rt.caller)
        self.assertEqual(rt.args, {})
        self.assertEqual(rt.call_params, {})
        self.assertIsNone(rt.mtir)

    def test_factory(self) -> None:
        def dummy():
            pass

        rt = _ns["MTRuntime"].factory(caller=dummy, args={1: "a"}, call_params={"x": 1})
        self.assertIs(rt.caller, dummy)
        self.assertEqual(rt.args, {1: "a"})
        self.assertEqual(rt.call_params, {"x": 1})
        self.assertIsNone(rt.mtir)

    def test_mutable_defaults_not_shared(self) -> None:
        r1 = _ns["MTRuntime"]()
        r2 = _ns["MTRuntime"]()
        r1.args["key"] = "val"
        self.assertEqual(r1.args, {"key": "val"})
        self.assertEqual(r2.args, {})


class TestMTIR(unittest.TestCase):
    """Test MTIR obj with runtime property."""

    def test_defaults(self) -> None:
        ir = _ns["MTIR"]()
        self.assertIsNone(ir.caller)
        self.assertEqual(ir.args, {})
        self.assertIsNone(ir.ir_info)

    def test_runtime_property(self) -> None:
        def dummy():
            pass

        ir = _ns["MTIR"](caller=dummy, args={1: "a"}, call_params={"x": 1})
        rt = ir.runtime
        self.assertIs(rt.caller, dummy)
        self.assertEqual(rt.args, {1: "a"})
        self.assertEqual(rt.call_params, {"x": 1})


# =============================================================================
# Generic Type Helper Tests
# =============================================================================


class TestTypeHelpers(unittest.TestCase):
    """Test mk_* and is_* type helper functions."""

    def test_mk_list(self) -> None:
        self.assertEqual(_ns["mk_list"]("int"), ("list", "int"))

    def test_mk_dict(self) -> None:
        self.assertEqual(_ns["mk_dict"]("str", "int"), ("dict", "str", "int"))

    def test_mk_tuple(self) -> None:
        self.assertEqual(_ns["mk_tuple"]("int", "str"), ("tuple", "int", "str"))

    def test_mk_union(self) -> None:
        self.assertEqual(_ns["mk_union"]("int", "str"), ("union", "int", "str"))

    def test_is_list_type(self) -> None:
        self.assertTrue(_ns["is_list_type"](("list", "int")))
        self.assertFalse(_ns["is_list_type"](("dict", "str", "int")))
        self.assertFalse(_ns["is_list_type"]("list"))

    def test_is_dict_type(self) -> None:
        self.assertTrue(_ns["is_dict_type"](("dict", "str", "int")))
        self.assertFalse(_ns["is_dict_type"](("list", "int")))

    def test_is_tuple_type(self) -> None:
        self.assertTrue(_ns["is_tuple_type"](("tuple", "int", "str")))
        self.assertFalse(_ns["is_tuple_type"](("list", "int")))

    def test_is_union_type(self) -> None:
        self.assertTrue(_ns["is_union_type"](("union", "int", "str")))
        self.assertFalse(_ns["is_union_type"](("list", "int")))

    def test_inner_types(self) -> None:
        self.assertEqual(_ns["inner_types"](("list", "int")), ("int",))
        self.assertEqual(_ns["inner_types"](("dict", "str", "int")), ("str", "int"))
        self.assertEqual(_ns["inner_types"]("plain"), ())


# =============================================================================
# type_to_str Tests
# =============================================================================


class TestTypeToStr(unittest.TestCase):
    """Test type_to_str pretty-printer."""

    def test_none(self) -> None:
        self.assertEqual(_ns["type_to_str"](None), "None")

    def test_string(self) -> None:
        self.assertEqual(_ns["type_to_str"]("int"), "int")

    def test_list_type(self) -> None:
        self.assertEqual(_ns["type_to_str"](("list", "str")), "list[str]")

    def test_dict_type(self) -> None:
        self.assertEqual(_ns["type_to_str"](("dict", "str", "int")), "dict[str,int]")

    def test_tuple_type(self) -> None:
        self.assertEqual(
            _ns["type_to_str"](("tuple", "int", "str", "bool")),
            "tuple[int,str,bool]",
        )

    def test_union_type(self) -> None:
        self.assertEqual(_ns["type_to_str"](("union", "int", "str")), "int|str")

    def test_nested_type(self) -> None:
        self.assertEqual(
            _ns["type_to_str"](("dict", "str", ("list", "int"))),
            "dict[str,list[int]]",
        )

    def test_object_with_name(self) -> None:
        info = _ns["Info"](name="Foo")
        self.assertEqual(_ns["type_to_str"](info), "Foo")

    def test_fallback(self) -> None:
        self.assertEqual(_ns["type_to_str"](42), "42")


if __name__ == "__main__":
    unittest.main()
