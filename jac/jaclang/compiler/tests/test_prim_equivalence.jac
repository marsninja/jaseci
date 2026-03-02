"""Unified cross-backend primitive equivalence tests.

Each fixture may contain up to three backend implementations:
  - def func_py()            Python reference (always run)
  - cl def func_cl()         ECMAScript/JS via Node.js
  - na { def func_na() }     Native LLVM JIT via ctypes

The harness runs the Python reference, then any available backends.
compare_results uses intersection semantics: only keys present in both
dicts are checked, so fixtures may return different subsets per backend.
"""

import ctypes;
import importlib;
import json;
import os;
import struct;
import subprocess;
import sys;
import from pathlib { Path }
import jaclang;
import from jaclang.compiler.passes.ecmascript { EsastGenPass }
import from jaclang.compiler.passes.ecmascript.es_unparse { es_to_js }
import from jaclang.compiler.passes.ecmascript.estree { Node as EsNode }
import from jaclang.jac0core.program { JacProgram }

glob FIXTURES = str(
         Path(jaclang.__file__).parent / "compiler" / "tests" / "fixtures"
     );

# -----------------------------------------------------------------------
# Python reference helper
# -----------------------------------------------------------------------
def run_py_fixture(fixture_stem: str, func_name: str) -> dict {
    added = False;
    if FIXTURES not in sys.path {
        sys.path.insert(0, FIXTURES);
        added = True;
    }
    try {
        sys.modules.pop(fixture_stem, None);
        mod = importlib.import_module(fixture_stem);
        fn = getattr(mod, func_name);
        return json.loads(json.dumps(fn()));
    } finally {
        if added {
            sys.path.remove(FIXTURES);
        }
        sys.modules.pop(fixture_stem, None);
    }
}

# -----------------------------------------------------------------------
# ES (ECMAScript / JavaScript) helpers
# -----------------------------------------------------------------------
def compile_fixture_to_js(fixture_name: str) -> str {
    fixture_path = os.path.join(FIXTURES, fixture_name);
    prog = JacProgram();
    ir = prog.compile(file_path=fixture_path, no_cgen=True);
    assert not prog.errors_had , (
        f"Compilation errors in {fixture_name}: {[str(e) for e in prog.errors_had]}"
    );
    es_pass = EsastGenPass(ir, prog);
    es_ir = es_pass.ir_out;
    assert isinstance(es_ir.gen.es_ast, EsNode) , "es_ast should be an EsNode";
    return es_to_js(es_ir.gen.es_ast);
}

def run_js_function(js_code: str, func_name: str) -> dict {
    wrapper = js_code + "\nconsole.log(JSON.stringify(" + func_name + "()));";
    result = subprocess.run(
        ["node", "-e", wrapper], capture_output=True, text=True, timeout=10
    );
    assert result.returncode == 0 , f"Node.js failed: {result.stderr}";
    return json.loads(result.stdout.strip());
}

# -----------------------------------------------------------------------
# NA (Native / LLVM) helpers
# -----------------------------------------------------------------------
def compile_native(fixture: str) -> tuple {
    prog = JacProgram();
    ir = prog.compile(file_path=str(os.path.join(FIXTURES, fixture)));
    errors = [str(e) for e in prog.errors_had] if prog.errors_had else [];
    assert not prog.errors_had , f"Compilation errors in {fixture}: {errors}";
    eng = ir.gen.native_engine;
    assert eng is not None , f"No native engine produced for {fixture}";
    return (eng, ir);
}

def get_func(eng: object, name: str, restype: type, *argtypes: type) -> object {
    addr = eng.get_function_address(name);
    assert addr != 0 , f"Function '{name}' not found in JIT engine";
    functype = ctypes.CFUNCTYPE(restype, *argtypes);
    return functype(addr);
}

class JacVal(ctypes.Structure) {
    has _fields_: list = [("tag", ctypes.c_int8), ("payload", ctypes.c_int64)];
}

def unbox_jacval(jv: JacVal) -> object {
    if jv.tag == 0 {
        return jv.payload;
    } elif jv.tag == 1 {
        return struct.unpack('d', struct.pack('q', jv.payload))[0];
    } elif jv.tag == 2 {
        if jv.payload == 0 {
            return "";
        }
        return ctypes.cast(jv.payload, ctypes.c_char_p).value.decode("utf-8");
    }
    return None;
}

def run_native_function(eng: object, func_name: str) -> dict {
    class DictStruct(ctypes.Structure) {
        has _fields_: list = [
            ("len", ctypes.c_int64),
            ("cap", ctypes.c_int64),
            ("keys", ctypes.POINTER(ctypes.c_char_p)),
            ("vals", ctypes.POINTER(JacVal))
        ];
    }
    f = get_func(eng, func_name, ctypes.POINTER(DictStruct));
    dict_ptr = f();
    result: dict = {};
    for i in range(dict_ptr.contents.len) {
        key = dict_ptr.contents.keys[i].decode("utf-8");
        jv = dict_ptr.contents.vals[i];
        result[key] = unbox_jacval(jv);
    }
    return result;
}

# -----------------------------------------------------------------------
# Comparison: intersection-based (only keys present in BOTH dicts)
# -----------------------------------------------------------------------
def compare_results(
    py_result: dict, backend_result: dict, label: str, tolerance: float = 1e-9
) -> None {
    common_keys = set(py_result.keys()) & set(backend_result.keys());
    assert common_keys , f"[{label}] No common keys between py and backend result";
    for key in sorted(common_keys) {
        py_val = py_result[key];
        bk_val = backend_result[key];
        if isinstance(py_val, float) or isinstance(bk_val, float) {
            assert abs(float(py_val) - float(bk_val)) < tolerance , (
                f"[{label}] Float mismatch on '{key}': py={py_val} backend={bk_val}"
            );
        } elif isinstance(py_val, list) and isinstance(bk_val, list) {
            assert py_val == bk_val , (
                f"[{label}] List mismatch on '{key}': py={py_val} backend={bk_val}"
            );
        } elif isinstance(py_val, dict) and isinstance(bk_val, dict) {
            assert py_val == bk_val , (
                f"[{label}] Dict mismatch on '{key}': py={py_val} backend={bk_val}"
            );
        } else {
            assert py_val == bk_val , (
                f"[{label}] Mismatch on '{key}': py={py_val!r} backend={bk_val!r}"
            );
        }
    }
}

# =======================================================================
# Tests — Merged fixtures (ES + NA)
# =======================================================================
test "numeric operators match across backends" {
    py_result = run_py_fixture("prim_numeric", "numeric_py");
    js_code = compile_fixture_to_js("prim_numeric.jac");
    compare_results(py_result, run_js_function(js_code, "numeric_cl"), "numeric [ES]");
    (eng, _) = compile_native("prim_numeric.jac");
    compare_results(py_result, run_native_function(eng, "numeric_na"), "numeric [NA]");
}

test "builtin functions match across backends" {
    py_result = run_py_fixture("prim_builtins", "builtins_py");
    js_code = compile_fixture_to_js("prim_builtins.jac");
    compare_results(py_result, run_js_function(js_code, "builtins_cl"), "builtins [ES]");
    (eng, _) = compile_native("prim_builtins.jac");
    compare_results(
        py_result, run_native_function(eng, "builtins_na"), "builtins [NA]"
    );
}

test "string methods match across backends" {
    py_result = run_py_fixture("prim_str_methods", "str_methods_py");
    js_code = compile_fixture_to_js("prim_str_methods.jac");
    compare_results(
        py_result, run_js_function(js_code, "str_methods_cl"), "str_methods [ES]"
    );
    (eng, _) = compile_native("prim_str_methods.jac");
    compare_results(
        py_result, run_native_function(eng, "str_methods_na"), "str_methods [NA]"
    );
}

test "list methods match across backends" {
    py_result = run_py_fixture("prim_list_methods", "list_methods_py");
    js_code = compile_fixture_to_js("prim_list_methods.jac");
    compare_results(
        py_result, run_js_function(js_code, "list_methods_cl"), "list_methods [ES]"
    );
    (eng, _) = compile_native("prim_list_methods.jac");
    compare_results(
        py_result, run_native_function(eng, "list_methods_na"), "list_methods [NA]"
    );
}

test "dict methods match across backends" {
    py_result = run_py_fixture("prim_dict_methods", "dict_methods_py");
    js_code = compile_fixture_to_js("prim_dict_methods.jac");
    compare_results(
        py_result, run_js_function(js_code, "dict_methods_cl"), "dict_methods [ES]"
    );
    (eng, _) = compile_native("prim_dict_methods.jac");
    compare_results(
        py_result, run_native_function(eng, "dict_methods_na"), "dict_methods [NA]"
    );
}

test "frozenset operations match across backends" {
    py_result = run_py_fixture("prim_frozenset", "frozenset_py");
    js_code = compile_fixture_to_js("prim_frozenset.jac");
    compare_results(
        py_result, run_js_function(js_code, "frozenset_cl"), "frozenset [ES]"
    );
    (eng, _) = compile_native("prim_frozenset.jac");
    compare_results(
        py_result, run_native_function(eng, "frozenset_na"), "frozenset [NA]"
    );
}

test "builtin extras match across backends" {
    py_result = run_py_fixture("prim_builtins_extra", "builtins_extra_py");
    js_code = compile_fixture_to_js("prim_builtins_extra.jac");
    compare_results(
        py_result, run_js_function(js_code, "builtins_extra_cl"), "builtins_extra [ES]"
    );
    (eng, _) = compile_native("prim_builtins_extra.jac");
    compare_results(
        py_result, run_native_function(eng, "builtins_extra_na"), "builtins_extra [NA]"
    );
}

test "string extra methods match across backends" {
    py_result = run_py_fixture("prim_str_extra", "str_extra_py");
    js_code = compile_fixture_to_js("prim_str_extra.jac");
    compare_results(
        py_result, run_js_function(js_code, "str_extra_cl"), "str_extra [ES]"
    );
    (eng, _) = compile_native("prim_str_extra.jac");
    compare_results(
        py_result, run_native_function(eng, "str_extra_na"), "str_extra [NA]"
    );
}

test "exception hierarchy matches across ES backend" {
    py_result = run_py_fixture("prim_exceptions", "exceptions_py");
    js_code = compile_fixture_to_js("prim_exceptions.jac");
    compare_results(
        py_result, run_js_function(js_code, "exceptions_cl"), "exceptions [ES]"
    );
}

test "runtime error hierarchy matches across ES backend" {
    py_result = run_py_fixture("prim_runtime_errors", "runtime_errors_py");
    js_code = compile_fixture_to_js("prim_runtime_errors.jac");
    compare_results(
        py_result, run_js_function(js_code, "runtime_errors_cl"), "runtime_errors [ES]"
    );
}

# =======================================================================
# Tests — NA-only fixtures
# =======================================================================
test "string advanced methods match across backends" {
    py_result = run_py_fixture("prim_str_advanced", "str_advanced_py");
    (eng, _) = compile_native("prim_str_advanced.jac");
    compare_results(
        py_result, run_native_function(eng, "str_advanced_na"), "str_advanced [NA]"
    );
}

test "string comparisons match across backends" {
    py_result = run_py_fixture("prim_str_cmp", "str_cmp_py");
    (eng, _) = compile_native("prim_str_cmp.jac");
    compare_results(py_result, run_native_function(eng, "str_cmp_na"), "str_cmp [NA]");
}

test "string index methods match across backends" {
    py_result = run_py_fixture("prim_str_index", "str_index_py");
    (eng, _) = compile_native("prim_str_index.jac");
    compare_results(
        py_result, run_native_function(eng, "str_index_na"), "str_index [NA]"
    );
}

test "string operators match across backends" {
    py_result = run_py_fixture("prim_str_ops", "str_ops_py");
    (eng, _) = compile_native("prim_str_ops.jac");
    compare_results(py_result, run_native_function(eng, "str_ops_na"), "str_ops [NA]");
}

test "string join matches across backends" {
    py_result = run_py_fixture("prim_str_join", "str_join_py");
    (eng, _) = compile_native("prim_str_join.jac");
    compare_results(
        py_result, run_native_function(eng, "str_join_na"), "str_join [NA]"
    );
}

test "str partition and splitlines match across backends" {
    py_result = run_py_fixture("prim_str_partition", "str_partition_py");
    (eng, _) = compile_native("prim_str_partition.jac");
    compare_results(
        py_result, run_native_function(eng, "str_partition_na"), "str_partition [NA]"
    );
}

test "list extra methods match across backends" {
    py_result = run_py_fixture("prim_list_extra", "list_extra_py");
    (eng, _) = compile_native("prim_list_extra.jac");
    compare_results(
        py_result, run_native_function(eng, "list_extra_na"), "list_extra [NA]"
    );
}

test "list remove matches across backends" {
    py_result = run_py_fixture("prim_list_remove", "list_remove_py");
    (eng, _) = compile_native("prim_list_remove.jac");
    compare_results(
        py_result, run_native_function(eng, "list_remove_na"), "list_remove [NA]"
    );
}

test "list sort matches across backends" {
    py_result = run_py_fixture("prim_list_sort", "list_sort_py");
    (eng, _) = compile_native("prim_list_sort.jac");
    compare_results(
        py_result, run_native_function(eng, "list_sort_na"), "list_sort [NA]"
    );
}

test "list multiplication matches across backends" {
    py_result = run_py_fixture("prim_list_mul", "list_mul_py");
    (eng, _) = compile_native("prim_list_mul.jac");
    compare_results(
        py_result, run_native_function(eng, "list_mul_na"), "list_mul [NA]"
    );
}

test "list comparison matches across backends" {
    py_result = run_py_fixture("prim_list_cmp", "list_cmp_py");
    (eng, _) = compile_native("prim_list_cmp.jac");
    compare_results(
        py_result, run_native_function(eng, "list_cmp_na"), "list_cmp [NA]"
    );
}

test "list operators match across backends" {
    py_result = run_py_fixture("prim_list_ops", "list_ops_py");
    (eng, _) = compile_native("prim_list_ops.jac");
    compare_results(
        py_result, run_native_function(eng, "list_ops_na"), "list_ops [NA]"
    );
}

test "dict copy and clear match across backends" {
    py_result = run_py_fixture("prim_dict_copy", "dict_copy_py");
    (eng, _) = compile_native("prim_dict_copy.jac");
    compare_results(
        py_result, run_native_function(eng, "dict_copy_na"), "dict_copy [NA]"
    );
}

test "dict extra methods match across backends" {
    py_result = run_py_fixture("prim_dict_extra", "dict_extra_py");
    (eng, _) = compile_native("prim_dict_extra.jac");
    compare_results(
        py_result, run_native_function(eng, "dict_extra_na"), "dict_extra [NA]"
    );
}

test "dict setdefault matches across backends" {
    py_result = run_py_fixture("prim_dict_setdefault", "dict_setdefault_py");
    (eng, _) = compile_native("prim_dict_setdefault.jac");
    compare_results(
        py_result,
        run_native_function(eng, "dict_setdefault_na"),
        "dict_setdefault [NA]"
    );
}

test "set methods match across backends" {
    py_result = run_py_fixture("prim_set_methods", "set_methods_py");
    (eng, _) = compile_native("prim_set_methods.jac");
    compare_results(
        py_result, run_native_function(eng, "set_methods_na"), "set_methods [NA]"
    );
}

test "set remove and pop match across backends" {
    py_result = run_py_fixture("prim_set_remove", "set_remove_py");
    (eng, _) = compile_native("prim_set_remove.jac");
    compare_results(
        py_result, run_native_function(eng, "set_remove_na"), "set_remove [NA]"
    );
}

test "set algebra matches across backends" {
    py_result = run_py_fixture("prim_set_algebra", "set_algebra_py");
    (eng, _) = compile_native("prim_set_algebra.jac");
    compare_results(
        py_result, run_native_function(eng, "set_algebra_na"), "set_algebra [NA]"
    );
}

test "set operators match across backends" {
    py_result = run_py_fixture("prim_set_operators", "set_operators_py");
    (eng, _) = compile_native("prim_set_operators.jac");
    compare_results(
        py_result, run_native_function(eng, "set_operators_na"), "set_operators [NA]"
    );
}

test "set augmented assignments match across backends" {
    py_result = run_py_fixture("prim_set_aug_assign", "set_aug_assign_py");
    (eng, _) = compile_native("prim_set_aug_assign.jac");
    compare_results(
        py_result, run_native_function(eng, "set_aug_assign_na"), "set_aug_assign [NA]"
    );
}

test "set advanced operations match across backends" {
    py_result = run_py_fixture("prim_set_advanced", "set_advanced_py");
    (eng, _) = compile_native("prim_set_advanced.jac");
    compare_results(
        py_result, run_native_function(eng, "set_advanced_na"), "set_advanced [NA]"
    );
}

test "bool conversion matches across backends" {
    py_result = run_py_fixture("prim_bool_conv", "bool_conv_py");
    (eng, _) = compile_native("prim_bool_conv.jac");
    compare_results(
        py_result, run_native_function(eng, "bool_conv_na"), "bool_conv [NA]"
    );
}

test "extra builtins 2 match across backends" {
    py_result = run_py_fixture("prim_builtins_extra2", "builtins_extra2_py");
    (eng, _) = compile_native("prim_builtins_extra2.jac");
    compare_results(
        py_result,
        run_native_function(eng, "builtins_extra2_na"),
        "builtins_extra2 [NA]"
    );
}

test "sorted and reversed match across backends" {
    py_result = run_py_fixture("prim_builtin_sort", "builtin_sort_py");
    (eng, _) = compile_native("prim_builtin_sort.jac");
    compare_results(
        py_result, run_native_function(eng, "builtin_sort_na"), "builtin_sort [NA]"
    );
}

test "builtin list and set conversions match across backends" {
    py_result = run_py_fixture("prim_builtin_convert", "builtin_convert_py");
    (eng, _) = compile_native("prim_builtin_convert.jac");
    compare_results(
        py_result,
        run_native_function(eng, "builtin_convert_na"),
        "builtin_convert [NA]"
    );
}

test "float comparisons match across backends" {
    py_result = run_py_fixture("prim_float_cmp", "float_cmp_py");
    (eng, _) = compile_native("prim_float_cmp.jac");
    compare_results(
        py_result, run_native_function(eng, "float_cmp_na"), "float_cmp [NA]"
    );
}

test "float methods match across backends" {
    py_result = run_py_fixture("prim_float_methods", "float_methods_py");
    (eng, _) = compile_native("prim_float_methods.jac");
    compare_results(
        py_result, run_native_function(eng, "float_methods_na"), "float_methods [NA]"
    );
}

test "int methods match across backends" {
    py_result = run_py_fixture("prim_int_methods", "int_methods_py");
    (eng, _) = compile_native("prim_int_methods.jac");
    compare_results(
        py_result, run_native_function(eng, "int_methods_na"), "int_methods [NA]"
    );
}

# --- NA exception tests (int-returning) ---
test "exception hierarchy basic catch" {
    (eng, _) = compile_native("prim_exceptions.jac");
    f = get_func(eng, "test_basic_catch_na", ctypes.c_int64);
    assert f() == 1;
}

test "exception hierarchy catch parent" {
    (eng, _) = compile_native("prim_exceptions.jac");
    f = get_func(eng, "test_catch_parent_na", ctypes.c_int64);
    assert f() == 1;
}

test "exception hierarchy catch grandparent" {
    (eng, _) = compile_native("prim_exceptions.jac");
    f = get_func(eng, "test_catch_grandparent_na", ctypes.c_int64);
    assert f() == 1;
}

test "exception hierarchy catch wrong type" {
    (eng, _) = compile_native("prim_exceptions.jac");
    f = get_func(eng, "test_catch_wrong_type_na", ctypes.c_int64);
    assert f() == 2;
}

test "exception hierarchy multiple handlers" {
    (eng, _) = compile_native("prim_exceptions.jac");
    f = get_func(eng, "test_multiple_handlers_na", ctypes.c_int64);
    assert f() == 2;
}

test "exception hierarchy nested" {
    (eng, _) = compile_native("prim_exceptions.jac");
    f = get_func(eng, "test_nested_hierarchy_na", ctypes.c_int64);
    assert f() == 1;
}

test "exception hierarchy finally runs" {
    (eng, _) = compile_native("prim_exceptions.jac");
    f = get_func(eng, "test_finally_runs_na", ctypes.c_int64);
    assert f() == 11;
}

test "exception hierarchy no exception" {
    (eng, _) = compile_native("prim_exceptions.jac");
    f = get_func(eng, "test_no_exception_na", ctypes.c_int64);
    assert f() == 11;
}

test "exception hierarchy as binding" {
    (eng, _) = compile_native("prim_exceptions.jac");
    f = get_func(eng, "test_exc_as_binding_na", ctypes.c_int64);
    assert f() == 1;
}

test "runtime: divzero caught by exact type" {
    (eng, _) = compile_native("prim_runtime_errors.jac");
    f = get_func(eng, "test_divzero_catch_exact_na", ctypes.c_int64);
    assert f() == 1;
}

test "runtime: divzero caught by parent ArithmeticError" {
    (eng, _) = compile_native("prim_runtime_errors.jac");
    f = get_func(eng, "test_divzero_catch_parent_na", ctypes.c_int64);
    assert f() == 1;
}

test "runtime: divzero caught by grandparent Exception" {
    (eng, _) = compile_native("prim_runtime_errors.jac");
    f = get_func(eng, "test_divzero_catch_grandparent_na", ctypes.c_int64);
    assert f() == 1;
}

test "runtime: divzero falls through wrong handler" {
    (eng, _) = compile_native("prim_runtime_errors.jac");
    f = get_func(eng, "test_divzero_wrong_handler_na", ctypes.c_int64);
    assert f() == 2;
}

test "runtime: modulo zero caught by ArithmeticError" {
    (eng, _) = compile_native("prim_runtime_errors.jac");
    f = get_func(eng, "test_modulo_zero_na", ctypes.c_int64);
    assert f() == 1;
}

test "runtime: index OOB caught by exact type" {
    (eng, _) = compile_native("prim_runtime_errors.jac");
    f = get_func(eng, "test_index_oob_catch_exact_na", ctypes.c_int64);
    assert f() == 1;
}

test "runtime: index OOB caught by parent LookupError" {
    (eng, _) = compile_native("prim_runtime_errors.jac");
    f = get_func(eng, "test_index_oob_catch_parent_na", ctypes.c_int64);
    assert f() == 1;
}

test "runtime: index OOB caught by Exception" {
    (eng, _) = compile_native("prim_runtime_errors.jac");
    f = get_func(eng, "test_index_oob_catch_exception_na", ctypes.c_int64);
    assert f() == 1;
}

test "runtime: dict key error caught by exact type" {
    (eng, _) = compile_native("prim_runtime_errors.jac");
    f = get_func(eng, "test_key_error_catch_exact_na", ctypes.c_int64);
    assert f() == 1;
}

test "runtime: dict key error caught by parent LookupError" {
    (eng, _) = compile_native("prim_runtime_errors.jac");
    f = get_func(eng, "test_key_error_catch_parent_na", ctypes.c_int64);
    assert f() == 1;
}

test "runtime: multi handler picks correct type" {
    (eng, _) = compile_native("prim_runtime_errors.jac");
    f = get_func(eng, "test_multi_handler_runtime_na", ctypes.c_int64);
    assert f() == 2;
}

test "runtime: error with finally block" {
    (eng, _) = compile_native("prim_runtime_errors.jac");
    f = get_func(eng, "test_runtime_finally_na", ctypes.c_int64);
    assert f() == 11;
}

# =======================================================================
# Tests — ES-only fixtures
# =======================================================================
test "container operators match across backends" {
    py_result = run_py_fixture("prim_containers", "containers_py");
    js_code = compile_fixture_to_js("prim_containers.jac");
    compare_results(
        py_result, run_js_function(js_code, "containers_cl"), "containers [ES]"
    );
}

test "jac runtime int methods match across backends" {
    py_result = run_py_fixture("prim_jac_runtime", "jac_rt_int_py");
    js_code = compile_fixture_to_js("prim_jac_runtime.jac");
    compare_results(
        py_result, run_js_function(js_code, "jac_rt_int_cl"), "jac_rt_int [ES]"
    );
}

test "jac runtime float methods match across backends" {
    py_result = run_py_fixture("prim_jac_runtime", "jac_rt_float_py");
    js_code = compile_fixture_to_js("prim_jac_runtime.jac");
    compare_results(
        py_result, run_js_function(js_code, "jac_rt_float_cl"), "jac_rt_float [ES]"
    );
}

test "jac runtime str methods match across backends" {
    py_result = run_py_fixture("prim_jac_runtime", "jac_rt_str_py");
    js_code = compile_fixture_to_js("prim_jac_runtime.jac");
    compare_results(
        py_result, run_js_function(js_code, "jac_rt_str_cl"), "jac_rt_str [ES]"
    );
}

test "jac runtime list methods match across backends" {
    py_result = run_py_fixture("prim_jac_runtime", "jac_rt_list_py");
    js_code = compile_fixture_to_js("prim_jac_runtime.jac");
    compare_results(
        py_result, run_js_function(js_code, "jac_rt_list_cl"), "jac_rt_list [ES]"
    );
}

test "jac runtime dict methods match across backends" {
    py_result = run_py_fixture("prim_jac_runtime", "jac_rt_dict_py");
    js_code = compile_fixture_to_js("prim_jac_runtime.jac");
    compare_results(
        py_result, run_js_function(js_code, "jac_rt_dict_cl"), "jac_rt_dict [ES]"
    );
}

test "jac runtime set methods match across backends" {
    py_result = run_py_fixture("prim_jac_runtime", "jac_rt_set_py");
    js_code = compile_fixture_to_js("prim_jac_runtime.jac");
    compare_results(
        py_result, run_js_function(js_code, "jac_rt_set_cl"), "jac_rt_set [ES]"
    );
}

test "jac runtime tuple methods match across backends" {
    py_result = run_py_fixture("prim_jac_runtime", "jac_rt_tuple_py");
    js_code = compile_fixture_to_js("prim_jac_runtime.jac");
    compare_results(
        py_result, run_js_function(js_code, "jac_rt_tuple_cl"), "jac_rt_tuple [ES]"
    );
}

test "jac runtime builtin functions match across backends" {
    py_result = run_py_fixture("prim_jac_runtime", "jac_rt_builtin_py");
    js_code = compile_fixture_to_js("prim_jac_runtime.jac");
    compare_results(
        py_result, run_js_function(js_code, "jac_rt_builtin_cl"), "jac_rt_builtin [ES]"
    );
}

test "bool truthiness matches Python semantics" {
    py_result = run_py_fixture("prim_new_primitives", "bool_truthiness_py");
    js_code = compile_fixture_to_js("prim_new_primitives.jac");
    compare_results(
        py_result,
        run_js_function(js_code, "bool_truthiness_cl"),
        "bool_truthiness [ES]"
    );
}

test "range builtin matches across backends" {
    py_result = run_py_fixture("prim_new_primitives", "range_builtin_py");
    js_code = compile_fixture_to_js("prim_new_primitives.jac");
    compare_results(
        py_result, run_js_function(js_code, "range_builtin_cl"), "range_builtin [ES]"
    );
}

test "bool bitwise operators match across backends" {
    py_result = run_py_fixture("prim_new_primitives", "bool_bitwise_py");
    js_code = compile_fixture_to_js("prim_new_primitives.jac");
    compare_results(
        py_result, run_js_function(js_code, "bool_bitwise_cl"), "bool_bitwise [ES]"
    );
}

test "format builtin matches across backends" {
    py_result = run_py_fixture("prim_new_primitives", "format_builtin_py");
    js_code = compile_fixture_to_js("prim_new_primitives.jac");
    compare_results(
        py_result, run_js_function(js_code, "format_builtin_cl"), "format_builtin [ES]"
    );
}

test "range methods match across backends" {
    py_result = run_py_fixture("prim_new_primitives", "range_methods_py");
    js_code = compile_fixture_to_js("prim_new_primitives.jac");
    compare_results(
        py_result, run_js_function(js_code, "range_methods_cl"), "range_methods [ES]"
    );
}

test "slice builtin matches across backends" {
    py_result = run_py_fixture("prim_new_primitives", "slice_builtin_py");
    js_code = compile_fixture_to_js("prim_new_primitives.jac");
    compare_results(
        py_result, run_js_function(js_code, "slice_builtin_cl"), "slice_builtin [ES]"
    );
}

test "int extra methods match across backends" {
    py_result = run_py_fixture("prim_int_extra", "int_extra_py");
    js_code = compile_fixture_to_js("prim_int_extra.jac");
    compare_results(
        py_result, run_js_function(js_code, "int_extra_cl"), "int_extra [ES]"
    );
}

test "complex operators match across backends" {
    py_result = run_py_fixture("prim_complex", "complex_ops_py");
    js_code = compile_fixture_to_js("prim_complex.jac");
    compare_results(
        py_result, run_js_function(js_code, "complex_ops_cl"), "complex_ops [ES]"
    );
}

test "bytes search methods match across backends" {
    py_result = run_py_fixture("prim_bytes", "bytes_search_py");
    js_code = compile_fixture_to_js("prim_bytes.jac");
    compare_results(
        py_result, run_js_function(js_code, "bytes_search_cl"), "bytes_search [ES]"
    );
}

test "bytes modify methods match across backends" {
    py_result = run_py_fixture("prim_bytes", "bytes_modify_py");
    js_code = compile_fixture_to_js("prim_bytes.jac");
    compare_results(
        py_result, run_js_function(js_code, "bytes_modify_cl"), "bytes_modify [ES]"
    );
}

test "bytes case methods match across backends" {
    py_result = run_py_fixture("prim_bytes", "bytes_case_py");
    js_code = compile_fixture_to_js("prim_bytes.jac");
    compare_results(
        py_result, run_js_function(js_code, "bytes_case_cl"), "bytes_case [ES]"
    );
}

test "bytes test methods match across backends" {
    py_result = run_py_fixture("prim_bytes", "bytes_test_py");
    js_code = compile_fixture_to_js("prim_bytes.jac");
    compare_results(
        py_result, run_js_function(js_code, "bytes_test_cl"), "bytes_test [ES]"
    );
}

test "set mutation methods match across backends" {
    py_result = run_py_fixture("prim_set_ops", "set_mutation_py");
    js_code = compile_fixture_to_js("prim_set_ops.jac");
    compare_results(
        py_result, run_js_function(js_code, "set_mutation_cl"), "set_mutation [ES]"
    );
}

test "set algebra methods match across backends [ES]" {
    py_result = run_py_fixture("prim_set_ops", "set_algebra_py");
    js_code = compile_fixture_to_js("prim_set_ops.jac");
    compare_results(
        py_result, run_js_function(js_code, "set_algebra_cl"), "set_algebra [ES]"
    );
}

test "set operators match across backends [ES]" {
    py_result = run_py_fixture("prim_set_ops", "set_operators_py");
    js_code = compile_fixture_to_js("prim_set_ops.jac");
    compare_results(
        py_result, run_js_function(js_code, "set_operators_cl"), "set_operators [ES]"
    );
}

test "float operators match across backends [ES]" {
    py_result = run_py_fixture("prim_float_ops", "float_ops_py");
    js_code = compile_fixture_to_js("prim_float_ops.jac");
    compare_results(
        py_result, run_js_function(js_code, "float_ops_cl"), "float_ops [ES]"
    );
}
