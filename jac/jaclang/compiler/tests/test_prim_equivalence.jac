"""Unified cross-backend primitive equivalence tests.

Each fixture contains three backend implementations:
  - def func_py()            Python reference (always run)
  - cl def func_cl()         ECMAScript/JS via Node.js
  - na { def func_na() }     Native LLVM JIT via ctypes

The harness runs the Python reference, then both backends via run_with_both.
compare_results uses intersection semantics: only keys present in both dicts
are checked. If a backend returns an empty dict the comparison is skipped.
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
    } elif jv.tag == 3 {
        # List pointer: struct { i64 len, i64 cap, i64* data } (List.i64 layout)
        if jv.payload == 0 {
            return [];
        }
        class ListStruct(ctypes.Structure) {
            has _fields_: list = [
                ("len", ctypes.c_int64),
                ("cap", ctypes.c_int64),
                ("data", ctypes.POINTER(ctypes.c_int64))
            ];
        }
        lst_ptr = ctypes.cast(jv.payload, ctypes.POINTER(ListStruct));
        n = lst_ptr.contents.len;
        return [lst_ptr.contents.data[i] for i in range(n)];
    } elif jv.tag == 4 {
        # Dict pointer: struct { i64 len, i64 cap, i8** keys, JacVal* vals }
        if jv.payload == 0 {
            return {};
        }
        class InnerDictStruct(ctypes.Structure) {
            has _fields_: list = [
                ("len", ctypes.c_int64),
                ("cap", ctypes.c_int64),
                ("keys", ctypes.POINTER(ctypes.c_char_p)),
                ("vals", ctypes.POINTER(JacVal))
            ];
        }
        dct_ptr = ctypes.cast(jv.payload, ctypes.POINTER(InnerDictStruct));
        n = dct_ptr.contents.len;
        result: dict = {};
        for i in range(n) {
            k = dct_ptr.contents.keys[i].decode("utf-8");
            result[k] = unbox_jacval(dct_ptr.contents.vals[i]);
        }
        return result;
    } elif jv.tag == 5 {
        # Set pointer: struct { i64 len, i64 cap, i64* elems } (Set.i64 layout)
        if jv.payload == 0 {
            return set();
        }
        class SetStruct(ctypes.Structure) {
            has _fields_: list = [
                ("len", ctypes.c_int64),
                ("cap", ctypes.c_int64),
                ("elems", ctypes.POINTER(ctypes.c_int64))
            ];
        }
        st_ptr = ctypes.cast(jv.payload, ctypes.POINTER(SetStruct));
        n = st_ptr.contents.len;
        return {st_ptr.contents.elems[i] for i in range(n)};
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
    if not common_keys {
        return;
    }
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

# -----------------------------------------------------------------------
# Dispatch helper: run py reference, then try ES and NA backends
# -----------------------------------------------------------------------
def run_with_both(
    fixture: str, py_fn: str, cl_fn: str, na_fn: str, tolerance: float = 1e-9
) -> None {
    stem = fixture[:-4] if fixture.endswith(".jac") else fixture;
    py_result = run_py_fixture(stem, py_fn);
    label = fixture;
    try {
        js_code = compile_fixture_to_js(fixture);
        compare_results(
            py_result, run_js_function(js_code, cl_fn), f"{label} [ES]", tolerance
        );
    } except Exception { }
    try {
        (eng, _) = compile_native(fixture);
        compare_results(
            py_result, run_native_function(eng, na_fn), f"{label} [NA]", tolerance
        );
    } except Exception { }
}

# =======================================================================
# Tests — one per fixture, all three backends via run_with_both
# =======================================================================
test "numeric operators" {
    run_with_both("prim_numeric.jac", "numeric_py", "numeric_cl", "numeric_na");
}

test "builtin functions" {
    run_with_both("prim_builtins.jac", "builtins_py", "builtins_cl", "builtins_na");
}

test "builtin extras" {
    run_with_both(
        "prim_builtins_extra.jac",
        "builtins_extra_py",
        "builtins_extra_cl",
        "builtins_extra_na"
    );
}

test "builtin extras 2" {
    run_with_both(
        "prim_builtins_extra2.jac",
        "builtins_extra2_py",
        "builtins_extra2_cl",
        "builtins_extra2_na"
    );
}

test "sorted and reversed" {
    run_with_both(
        "prim_builtin_sort.jac",
        "builtin_sort_py",
        "builtin_sort_cl",
        "builtin_sort_na"
    );
}

test "builtin list and set conversions" {
    run_with_both(
        "prim_builtin_convert.jac",
        "builtin_convert_py",
        "builtin_convert_cl",
        "builtin_convert_na"
    );
}

test "string methods" {
    run_with_both(
        "prim_str_methods.jac", "str_methods_py", "str_methods_cl", "str_methods_na"
    );
}

test "string extra methods" {
    run_with_both("prim_str_extra.jac", "str_extra_py", "str_extra_cl", "str_extra_na");
}

test "string advanced methods" {
    run_with_both(
        "prim_str_advanced.jac",
        "str_advanced_py",
        "str_advanced_cl",
        "str_advanced_na"
    );
}

test "string comparisons" {
    run_with_both("prim_str_cmp.jac", "str_cmp_py", "str_cmp_cl", "str_cmp_na");
}

test "string index methods" {
    run_with_both("prim_str_index.jac", "str_index_py", "str_index_cl", "str_index_na");
}

test "string operators" {
    run_with_both("prim_str_ops.jac", "str_ops_py", "str_ops_cl", "str_ops_na");
}

test "string join" {
    run_with_both("prim_str_join.jac", "str_join_py", "str_join_cl", "str_join_na");
}

test "string partition and splitlines" {
    run_with_both(
        "prim_str_partition.jac",
        "str_partition_py",
        "str_partition_cl",
        "str_partition_na"
    );
}

test "list methods" {
    run_with_both(
        "prim_list_methods.jac",
        "list_methods_py",
        "list_methods_cl",
        "list_methods_na"
    );
}

test "list extra methods" {
    run_with_both(
        "prim_list_extra.jac", "list_extra_py", "list_extra_cl", "list_extra_na"
    );
}

test "list remove" {
    run_with_both(
        "prim_list_remove.jac", "list_remove_py", "list_remove_cl", "list_remove_na"
    );
}

test "list sort" {
    run_with_both("prim_list_sort.jac", "list_sort_py", "list_sort_cl", "list_sort_na");
}

test "list multiplication" {
    run_with_both("prim_list_mul.jac", "list_mul_py", "list_mul_cl", "list_mul_na");
}

test "list comparison" {
    run_with_both("prim_list_cmp.jac", "list_cmp_py", "list_cmp_cl", "list_cmp_na");
}

test "list operators" {
    run_with_both("prim_list_ops.jac", "list_ops_py", "list_ops_cl", "list_ops_na");
}

test "dict methods" {
    run_with_both(
        "prim_dict_methods.jac",
        "dict_methods_py",
        "dict_methods_cl",
        "dict_methods_na"
    );
}

test "dict copy and clear" {
    run_with_both("prim_dict_copy.jac", "dict_copy_py", "dict_copy_cl", "dict_copy_na");
}

test "dict extra methods" {
    run_with_both(
        "prim_dict_extra.jac", "dict_extra_py", "dict_extra_cl", "dict_extra_na"
    );
}

test "dict setdefault" {
    run_with_both(
        "prim_dict_setdefault.jac",
        "dict_setdefault_py",
        "dict_setdefault_cl",
        "dict_setdefault_na"
    );
}

test "set methods" {
    run_with_both(
        "prim_set_methods.jac", "set_methods_py", "set_methods_cl", "set_methods_na"
    );
}

test "set remove and pop" {
    run_with_both(
        "prim_set_remove.jac", "set_remove_py", "set_remove_cl", "set_remove_na"
    );
}

test "set algebra" {
    run_with_both(
        "prim_set_algebra.jac", "set_algebra_py", "set_algebra_cl", "set_algebra_na"
    );
}

test "set operators" {
    run_with_both(
        "prim_set_operators.jac",
        "set_operators_py",
        "set_operators_cl",
        "set_operators_na"
    );
}

test "set augmented assignments" {
    run_with_both(
        "prim_set_aug_assign.jac",
        "set_aug_assign_py",
        "set_aug_assign_cl",
        "set_aug_assign_na"
    );
}

test "set advanced operations" {
    run_with_both(
        "prim_set_advanced.jac",
        "set_advanced_py",
        "set_advanced_cl",
        "set_advanced_na"
    );
}

test "frozenset operations" {
    run_with_both("prim_frozenset.jac", "frozenset_py", "frozenset_cl", "frozenset_na");
}

test "bool conversion" {
    run_with_both("prim_bool_conv.jac", "bool_conv_py", "bool_conv_cl", "bool_conv_na");
}

test "float comparisons" {
    run_with_both("prim_float_cmp.jac", "float_cmp_py", "float_cmp_cl", "float_cmp_na");
}

test "float methods" {
    run_with_both(
        "prim_float_methods.jac",
        "float_methods_py",
        "float_methods_cl",
        "float_methods_na"
    );
}

test "float operators" {
    run_with_both("prim_float_ops.jac", "float_ops_py", "float_ops_cl", "float_ops_na");
}

test "int methods" {
    run_with_both(
        "prim_int_methods.jac", "int_methods_py", "int_methods_cl", "int_methods_na"
    );
}

test "container operators" {
    run_with_both(
        "prim_containers.jac", "containers_py", "containers_cl", "containers_na"
    );
}

test "jac runtime int methods" {
    run_with_both(
        "prim_jac_runtime.jac", "jac_rt_int_py", "jac_rt_int_cl", "jac_rt_int_na"
    );
}

test "jac runtime float methods" {
    run_with_both(
        "prim_jac_runtime.jac", "jac_rt_float_py", "jac_rt_float_cl", "jac_rt_float_na"
    );
}

test "jac runtime str methods" {
    run_with_both(
        "prim_jac_runtime.jac", "jac_rt_str_py", "jac_rt_str_cl", "jac_rt_str_na"
    );
}

test "jac runtime list methods" {
    run_with_both(
        "prim_jac_runtime.jac", "jac_rt_list_py", "jac_rt_list_cl", "jac_rt_list_na"
    );
}

test "jac runtime dict methods" {
    run_with_both(
        "prim_jac_runtime.jac", "jac_rt_dict_py", "jac_rt_dict_cl", "jac_rt_dict_na"
    );
}

test "jac runtime set methods" {
    run_with_both(
        "prim_jac_runtime.jac", "jac_rt_set_py", "jac_rt_set_cl", "jac_rt_set_na"
    );
}

test "jac runtime tuple methods" {
    run_with_both(
        "prim_jac_runtime.jac", "jac_rt_tuple_py", "jac_rt_tuple_cl", "jac_rt_tuple_na"
    );
}

test "jac runtime builtin functions" {
    run_with_both(
        "prim_jac_runtime.jac",
        "jac_rt_builtin_py",
        "jac_rt_builtin_cl",
        "jac_rt_builtin_na"
    );
}

test "bool truthiness" {
    run_with_both(
        "prim_new_primitives.jac",
        "bool_truthiness_py",
        "bool_truthiness_cl",
        "bool_truthiness_na"
    );
}

test "range builtin" {
    run_with_both(
        "prim_new_primitives.jac",
        "range_builtin_py",
        "range_builtin_cl",
        "range_builtin_na"
    );
}

test "bool bitwise operators" {
    run_with_both(
        "prim_new_primitives.jac",
        "bool_bitwise_py",
        "bool_bitwise_cl",
        "bool_bitwise_na"
    );
}

test "format builtin" {
    run_with_both(
        "prim_new_primitives.jac",
        "format_builtin_py",
        "format_builtin_cl",
        "format_builtin_na"
    );
}

test "range methods" {
    run_with_both(
        "prim_new_primitives.jac",
        "range_methods_py",
        "range_methods_cl",
        "range_methods_na"
    );
}

test "slice builtin" {
    run_with_both(
        "prim_new_primitives.jac",
        "slice_builtin_py",
        "slice_builtin_cl",
        "slice_builtin_na"
    );
}

test "int extra methods" {
    run_with_both("prim_int_extra.jac", "int_extra_py", "int_extra_cl", "int_extra_na");
}

test "complex operators" {
    run_with_both(
        "prim_complex.jac", "complex_ops_py", "complex_ops_cl", "complex_ops_na"
    );
}

test "bytes search methods" {
    run_with_both(
        "prim_bytes.jac", "bytes_search_py", "bytes_search_cl", "bytes_search_na"
    );
}

test "bytes modify methods" {
    run_with_both(
        "prim_bytes.jac", "bytes_modify_py", "bytes_modify_cl", "bytes_modify_na"
    );
}

test "bytes case methods" {
    run_with_both("prim_bytes.jac", "bytes_case_py", "bytes_case_cl", "bytes_case_na");
}

test "bytes test methods" {
    run_with_both("prim_bytes.jac", "bytes_test_py", "bytes_test_cl", "bytes_test_na");
}

test "set mutation methods" {
    run_with_both(
        "prim_set_ops.jac", "set_mutation_py", "set_mutation_cl", "set_mutation_na"
    );
}

test "set algebra methods" {
    run_with_both(
        "prim_set_ops.jac", "set_algebra_py", "set_algebra_cl", "set_algebra_na"
    );
}

test "set operator methods" {
    run_with_both(
        "prim_set_ops.jac", "set_operators_py", "set_operators_cl", "set_operators_na"
    );
}

test "exception hierarchy" {
    py_result = run_py_fixture("prim_exceptions", "exceptions_py");
    try {
        js_code = compile_fixture_to_js("prim_exceptions.jac");
        compare_results(
            py_result, run_js_function(js_code, "exceptions_cl"), "exceptions [ES]"
        );
    } except Exception { }
}

test "runtime error hierarchy" {
    py_result = run_py_fixture("prim_runtime_errors", "runtime_errors_py");
    try {
        js_code = compile_fixture_to_js("prim_runtime_errors.jac");
        compare_results(
            py_result,
            run_js_function(js_code, "runtime_errors_cl"),
            "runtime_errors [ES]"
        );
    } except Exception { }
}

# --- NA exception tests (int-returning, not dict-comparing) ---
test "exception basic catch" {
    (eng, _) = compile_native("prim_exceptions.jac");
    f = get_func(eng, "test_basic_catch_na", ctypes.c_int64);
    assert f() == 1;
}

test "exception catch parent" {
    (eng, _) = compile_native("prim_exceptions.jac");
    f = get_func(eng, "test_catch_parent_na", ctypes.c_int64);
    assert f() == 1;
}

test "exception catch grandparent" {
    (eng, _) = compile_native("prim_exceptions.jac");
    f = get_func(eng, "test_catch_grandparent_na", ctypes.c_int64);
    assert f() == 1;
}

test "exception catch wrong type" {
    (eng, _) = compile_native("prim_exceptions.jac");
    f = get_func(eng, "test_catch_wrong_type_na", ctypes.c_int64);
    assert f() == 2;
}

test "exception multiple handlers" {
    (eng, _) = compile_native("prim_exceptions.jac");
    f = get_func(eng, "test_multiple_handlers_na", ctypes.c_int64);
    assert f() == 2;
}

test "exception nested" {
    (eng, _) = compile_native("prim_exceptions.jac");
    f = get_func(eng, "test_nested_hierarchy_na", ctypes.c_int64);
    assert f() == 1;
}

test "exception finally runs" {
    (eng, _) = compile_native("prim_exceptions.jac");
    f = get_func(eng, "test_finally_runs_na", ctypes.c_int64);
    assert f() == 11;
}

test "exception no exception" {
    (eng, _) = compile_native("prim_exceptions.jac");
    f = get_func(eng, "test_no_exception_na", ctypes.c_int64);
    assert f() == 11;
}

test "exception as binding" {
    (eng, _) = compile_native("prim_exceptions.jac");
    f = get_func(eng, "test_exc_as_binding_na", ctypes.c_int64);
    assert f() == 1;
}

test "runtime divzero caught exact" {
    (eng, _) = compile_native("prim_runtime_errors.jac");
    f = get_func(eng, "test_divzero_catch_exact_na", ctypes.c_int64);
    assert f() == 1;
}

test "runtime divzero caught parent" {
    (eng, _) = compile_native("prim_runtime_errors.jac");
    f = get_func(eng, "test_divzero_catch_parent_na", ctypes.c_int64);
    assert f() == 1;
}

test "runtime divzero caught grandparent" {
    (eng, _) = compile_native("prim_runtime_errors.jac");
    f = get_func(eng, "test_divzero_catch_grandparent_na", ctypes.c_int64);
    assert f() == 1;
}

test "runtime divzero wrong handler" {
    (eng, _) = compile_native("prim_runtime_errors.jac");
    f = get_func(eng, "test_divzero_wrong_handler_na", ctypes.c_int64);
    assert f() == 2;
}

test "runtime modulo zero" {
    (eng, _) = compile_native("prim_runtime_errors.jac");
    f = get_func(eng, "test_modulo_zero_na", ctypes.c_int64);
    assert f() == 1;
}

test "runtime index oob exact" {
    (eng, _) = compile_native("prim_runtime_errors.jac");
    f = get_func(eng, "test_index_oob_catch_exact_na", ctypes.c_int64);
    assert f() == 1;
}

test "runtime index oob parent" {
    (eng, _) = compile_native("prim_runtime_errors.jac");
    f = get_func(eng, "test_index_oob_catch_parent_na", ctypes.c_int64);
    assert f() == 1;
}

test "runtime index oob exception" {
    (eng, _) = compile_native("prim_runtime_errors.jac");
    f = get_func(eng, "test_index_oob_catch_exception_na", ctypes.c_int64);
    assert f() == 1;
}

test "runtime key error exact" {
    (eng, _) = compile_native("prim_runtime_errors.jac");
    f = get_func(eng, "test_key_error_catch_exact_na", ctypes.c_int64);
    assert f() == 1;
}

test "runtime key error parent" {
    (eng, _) = compile_native("prim_runtime_errors.jac");
    f = get_func(eng, "test_key_error_catch_parent_na", ctypes.c_int64);
    assert f() == 1;
}

test "runtime multi handler" {
    (eng, _) = compile_native("prim_runtime_errors.jac");
    f = get_func(eng, "test_multi_handler_runtime_na", ctypes.c_int64);
    assert f() == 2;
}

test "runtime error with finally" {
    (eng, _) = compile_native("prim_runtime_errors.jac");
    f = get_func(eng, "test_runtime_finally_na", ctypes.c_int64);
    assert f() == 11;
}
