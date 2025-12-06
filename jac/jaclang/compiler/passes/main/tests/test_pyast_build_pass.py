"""Test pass module."""

import ast as py_ast
import inspect
from collections.abc import Callable

from jaclang.compiler.passes.main import PyastBuildPass
from jaclang.compiler.program import JacProgram
from jaclang.compiler.unitree import PythonModuleAst, Source
from jaclang.utils.helpers import pascal_to_snake


def test_synced_to_latest_py_ast() -> None:
    """Basic test for pass."""
    # TODO: maybe instead iterate `ast.AST.__subclasses__`?
    unparser_cls = py_ast._Unparser  # type: ignore[attr-defined]
    visit_methods = (
        [
            method
            for method in dir(unparser_cls)  # noqa: B009
            if method.startswith("visit_")
        ]
        + list(unparser_cls.binop.keys())
        + list(unparser_cls.unop.keys())
        + list(unparser_cls.boolops.keys())
        + list(unparser_cls.cmpops.keys())
    )
    node_names = [
        pascal_to_snake(method.replace("visit_", "")) for method in visit_methods
    ]
    pass_func_names = []
    for name, value in inspect.getmembers(PyastBuildPass):
        if name.startswith("proc_") and inspect.isfunction(value):
            pass_func_names.append(name.replace("proc_", ""))
    for name in pass_func_names:
        assert name in node_names
    for name in node_names:
        assert name in pass_func_names


def test_str2doc(fixture_path: Callable[[str], str]) -> None:
    """Test str2doc."""
    with open(fixture_path("str2doc.py")) as f:
        file_source = f.read()
    code = PyastBuildPass(
        ir_in=PythonModuleAst(
            py_ast.parse(file_source),
            orig_src=Source(file_source, "str2doc.py"),
        ),
        prog=JacProgram(),
    ).ir_out.unparse()
    assert '"""This is a test function."""\ndef foo()' in code


def test_fstring_triple_quotes(fixture_path: Callable[[str], str]) -> None:
    """Test that triple-quoted f-strings are converted correctly."""
    with open(fixture_path("py2jac_fstrings.py")) as f:
        file_source = f.read()
    code = PyastBuildPass(
        ir_in=PythonModuleAst(
            py_ast.parse(file_source),
            orig_src=Source(file_source, "py2jac_fstrings.py"),
        ),
        prog=JacProgram(),
    ).ir_out.unparse()
    assert 'f"""Hello\n{name}"""' in code
    assert "f'''Hello\n{name}'''''''" not in code
    assert 'f"""Hello\n{name}"""""""' not in code


def test_py2jac_augmented_assignment() -> None:
    """Test that augmented assignments don't get 'let' prefix."""
    source = """
x = 0
x += 1
x -= 2
"""
    code = PyastBuildPass(
        ir_in=PythonModuleAst(
            py_ast.parse(source),
            orig_src=Source(source, "test.py"),
        ),
        prog=JacProgram(),
    ).ir_out.unparse()
    # Regular assignment should have 'let'
    assert "let x = 0" in code
    # Augmented assignments should NOT have 'let'
    assert "x += 1" in code
    assert "x -= 2" in code
    assert "let x +=" not in code
    assert "let x -=" not in code
    # Verify it parses without errors
    prog = JacProgram.jac_str_formatter(source_str=code, file_path="test.jac")
    assert not prog.errors_had


def test_py2jac_multiline_fstring() -> None:
    """Test that non-triple-quoted f-strings have escaped newlines."""
    # Use a regular string assignment that contains a newline character
    # which would be in a non-triple-quoted context after conversion
    source = 'x = f"hello\\nworld"'
    code = PyastBuildPass(
        ir_in=PythonModuleAst(
            py_ast.parse(source),
            orig_src=Source(source, "test.py"),
        ),
        prog=JacProgram(),
    ).ir_out.unparse()
    # Newlines should be escaped in output for non-triple-quoted strings
    assert "\\n" in code
    # Verify it parses without errors
    prog = JacProgram.jac_str_formatter(source_str=code, file_path="test.jac")
    assert not prog.errors_had


def test_py2jac_triple_quoted_fstring_preserves_newlines() -> None:
    """Test that triple-quoted f-strings preserve actual newlines."""
    source = '''
x = f"""hello
world"""
'''
    code = PyastBuildPass(
        ir_in=PythonModuleAst(
            py_ast.parse(source),
            orig_src=Source(source, "test.py"),
        ),
        prog=JacProgram(),
    ).ir_out.unparse()
    # Triple-quoted strings should preserve actual newlines
    assert 'f"""hello\nworld"""' in code
    # Verify it parses without errors
    prog = JacProgram.jac_str_formatter(source_str=code, file_path="test.jac")
    assert not prog.errors_had


def test_py2jac_fstring_with_hash() -> None:
    """Test that f-strings with # character parse correctly."""
    source = '''
x = f"# heading {name}"
'''
    code = PyastBuildPass(
        ir_in=PythonModuleAst(
            py_ast.parse(source),
            orig_src=Source(source, "test.py"),
        ),
        prog=JacProgram(),
    ).ir_out.unparse()
    # Verify it parses without errors (# should not be treated as comment)
    prog = JacProgram.jac_str_formatter(source_str=code, file_path="test.jac")
    assert not prog.errors_had


def test_py2jac_nested_function_docstring() -> None:
    """Test that nested function docstrings have semicolons."""
    source = '''
def outer():
    """Outer doc."""
    def inner():
        """Inner doc."""
        pass
'''
    code = PyastBuildPass(
        ir_in=PythonModuleAst(
            py_ast.parse(source),
            orig_src=Source(source, "test.py"),
        ),
        prog=JacProgram(),
    ).ir_out.unparse()
    # Inner docstring should be followed by semicolon
    assert '"""Inner doc.""";' in code or '"""Inner doc.""" ;' in code
    # Verify it parses without errors
    prog = JacProgram.jac_str_formatter(source_str=code, file_path="test.jac")
    assert not prog.errors_had
