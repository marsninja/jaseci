"""Tests for improved error reporting across the Jac compiler pipeline."""

import os;
import from pathlib { Path }
import from jaclang.jac0core.program { JacProgram }

glob FIXTURES = str(Path(__file__).parent / "fixtures" / "error_reporting");

def fixture_path(filename: str) -> str {
    return os.path.join(FIXTURES, filename);
}

def _all_errors_text(program: JacProgram) -> str {
    return " ".join([e.pretty_print() for e in program.errors_had]);
}

def _all_warnings_text(program: JacProgram) -> str {
    return " ".join([w.pretty_print() for w in program.warnings_had]);
}

# ── Phase B: Cascading Error Reduction ──
test "wp11: missing has in obj produces limited errors with hint" {
    program = JacProgram();
    program.compile(fixture_path("wp11_missing_has_obj.jac"));
    assert len(program.errors_had) <= 3 , (
        f"Expected at most 3 errors (was cascading 6+), got {len(program.errors_had)}"
    );
    error_text = _all_errors_text(program);
    assert "has" in error_text.lower() , (
        f"Expected hint about 'has' keyword in: {error_text}"
    );
}

test "wp11: missing has in node produces limited errors with hint" {
    program = JacProgram();
    program.compile(fixture_path("wp11_missing_has_node.jac"));
    assert len(program.errors_had) <= 3 , (
        f"Expected at most 3 errors (was cascading 11+), got {len(program.errors_had)}"
    );
    error_text = _all_errors_text(program);
    assert "has" in error_text.lower() , (
        f"Expected hint about 'has' keyword in: {error_text}"
    );
}

test "wp17: else if suggests elif" {
    program = JacProgram();
    program.compile(fixture_path("wp17_else_if.jac"));
    assert len(program.errors_had) <= 2 , (
        f"Expected at most 2 errors (was cascading 5+), got {len(program.errors_had)}"
    );
    error_text = _all_errors_text(program);
    assert "elif" in error_text , (
        f"Expected suggestion to use 'elif' in: {error_text}"
    );
}

test "wp9: def with colon suggests braces" {
    program = JacProgram();
    program.compile(fixture_path("wp9_def_with_colon.jac"));
    assert len(program.errors_had) <= 6 , (
        f"Expected reduced errors with hint, got {len(program.errors_had)}"
    );
    error_text = _all_errors_text(program);
    assert "{" in error_text , (
        f"Expected suggestion about curly braces in: {error_text}"
    );
}

test "wp10: backtick string gives clear error" {
    program = JacProgram();
    program.compile(fixture_path("wp10_backtick_string.jac"));
    assert len(program.errors_had) <= 3 , (
        f"Expected at most 3 errors (was cascading), got {len(program.errors_had)}"
    );
    error_text = _all_errors_text(program);
    assert "backtick" in error_text.lower()
    or "quotes" in error_text.lower()
    or "f-string" in error_text.lower() , (
        f"Expected mention of backtick/quotes in: {error_text}"
    );
}

# ── Phase C: Suggestion Improvements ──
test "wp16: module-level code suggests with entry" {
    program = JacProgram();
    program.compile(fixture_path("wp16_module_level_code.jac"));
    assert len(program.errors_had) >= 1;
    error_text = _all_errors_text(program);
    assert "entry" in error_text.lower() , (
        f"Expected suggestion about 'with entry' in: {error_text}"
    );
}

test "wp16: python import syntax suggests jac import" {
    program = JacProgram();
    program.compile(fixture_path("wp16_python_import.jac"));
    assert len(program.errors_had) >= 1;
    error_text = _all_errors_text(program);
    assert "import" in error_text.lower() , (
        f"Expected suggestion about import syntax in: {error_text}"
    );
}

test "wp16: pub def suggests def:pub" {
    program = JacProgram();
    program.compile(fixture_path("wp16_pub_def.jac"));
    assert len(program.errors_had) >= 1;
    error_text = _all_errors_text(program);
    assert "def:pub" in error_text or ":" in error_text , (
        f"Expected suggestion about 'def:pub' in: {error_text}"
    );
}

test "wp16: module-level variable suggests glob" {
    program = JacProgram();
    program.compile(fixture_path("wp16_var_without_glob.jac"));
    assert len(program.errors_had) >= 1;
    error_text = _all_errors_text(program);
    assert "glob" in error_text , (
        f"Expected suggestion about 'glob' in: {error_text}"
    );
}

test "wp20: python enum syntax suggests braces" {
    program = JacProgram();
    program.compile(fixture_path("wp20_enum_colon.jac"));
    assert len(program.errors_had) >= 1;
    error_text = _all_errors_text(program);
    assert "{" in error_text or "brace" in error_text.lower() , (
        f"Expected suggestion about braces in: {error_text}"
    );
}

test "wp22: typo enty suggests entry" {
    program = JacProgram();
    program.compile(fixture_path("wp22_typo_enty.jac"));
    assert len(program.errors_had) >= 1;
    error_text = _all_errors_text(program);
    assert "entry" in error_text , (
        f"Expected suggestion about 'entry' in: {error_text}"
    );
}

# ── Phase A: Critical Silent Failures ──
test "wp15: visit outside walker gives clear error without leaking internals" {
    program = JacProgram();
    program.compile(fixture_path("wp15_visit_outside_walker.jac"));
    assert len(program.errors_had) >= 1;
    error_text = _all_errors_text(program);
    assert "visit" in error_text.lower() , (
        f"Expected error mentioning 'visit' in: {error_text}"
    );
    assert "walker" in error_text.lower() , (
        f"Expected error mentioning 'walker' in: {error_text}"
    );
}

test "wp15: disengage outside walker gives clear error" {
    program = JacProgram();
    program.compile(fixture_path("wp15_disengage_outside_walker.jac"));
    assert len(program.errors_had) >= 1;
    error_text = _all_errors_text(program);
    assert "disengage" in error_text.lower() , (
        f"Expected error mentioning 'disengage' in: {error_text}"
    );
    assert "walker" in error_text.lower() , (
        f"Expected error mentioning 'walker' in: {error_text}"
    );
}

test "wp8: report outside walker warns" {
    program = JacProgram();
    program.compile(fixture_path("wp8_report_outside_walker.jac"));
    assert len(program.warnings_had) >= 1 , (
        f"Expected at least 1 warning, got {len(program.warnings_had)}"
    );
    warning_text = _all_warnings_text(program);
    assert "report" in warning_text.lower() , (
        f"Expected warning about 'report' in: {warning_text}"
    );
}

# ── Phase D: Semantic Warnings ──
test "wp12: has inside class warns about obj" {
    program = JacProgram();
    program.compile(fixture_path("wp12_has_in_class.jac"));
    assert len(program.warnings_had) >= 1 , (
        f"Expected at least 1 warning about has in class, got {len(
            program.warnings_had
        )}"
    );
    warning_text = _all_warnings_text(program);
    assert "obj" in warning_text or "class" in warning_text , (
        f"Expected warning about 'obj' or 'class' in: {warning_text}"
    );
}

# ── Phase E: Missing semicolons ──
# NOTE: WP1 (missing semicolons warning) only fires for bare expression statements,
# not for assignments. Assignments like `x = 5` still accept optional semicolons
# silently. Full coverage would require changes to parse_assignment_with_target too.

# ── JSX/Client-Side Error Reporting ──
test "jsx: mismatched closing tag detected" {
    program = JacProgram();
    program.compile(fixture_path("jsx_tag_mismatch.jac"));
    assert len(program.errors_had) >= 1;
    error_text = _all_errors_text(program);
    assert "does not match" in error_text.lower()
    or "did you mean" in error_text.lower() , (
        f"Expected tag mismatch error in: {error_text}"
    );
    assert "div" in error_text , (
        f"Expected mention of the correct tag 'div' in: {error_text}"
    );
}

test "jsx: void element must be self-closed" {
    program = JacProgram();
    program.compile(fixture_path("jsx_void_element.jac"));
    assert len(program.errors_had) >= 1;
    error_text = _all_errors_text(program);
    assert "void" in error_text.lower()
    or "self-closed" in error_text.lower()
    or "/>" in error_text , (f"Expected void element hint in: {error_text}");
}

test "jsx: imperative if in expression suggests conditional" {
    program = JacProgram();
    program.compile(fixture_path("jsx_if_in_expr.jac"));
    assert len(program.errors_had) >= 1;
    error_text = _all_errors_text(program);
    assert "conditional expression" in error_text.lower()
    or "if condition else" in error_text.lower() , (
        f"Expected conditional expression hint in: {error_text}"
    );
}

test "jsx: imperative for in expression suggests list comprehension" {
    program = JacProgram();
    program.compile(fixture_path("jsx_for_in_expr.jac"));
    assert len(program.errors_had) >= 1;
    error_text = _all_errors_text(program);
    assert "list comprehension" in error_text.lower()
    or "for item in list" in error_text.lower() , (
        f"Expected list comprehension hint in: {error_text}"
    );
}

test "jsx: missing cl prefix on JsxElement function warns" {
    program = JacProgram();
    program.compile(fixture_path("jsx_missing_cl.jac"));
    assert len(program.warnings_had) >= 1 , (
        f"Expected warning about missing cl prefix, got {len(program.warnings_had)}"
    );
    warning_text = _all_warnings_text(program);
    assert "JsxElement" in warning_text or "client" in warning_text.lower() , (
        f"Expected warning about JsxElement/client in: {warning_text}"
    );
}

test "jsx: await without async warns" {
    program = JacProgram();
    program.compile(fixture_path("jsx_await_no_async.jac"));
    assert len(program.warnings_had) >= 1 , (
        f"Expected warning about await without async, got {len(program.warnings_had)}"
    );
    warning_text = _all_warnings_text(program);
    assert "await" in warning_text.lower() and "async" in warning_text.lower() , (
        f"Expected warning mentioning 'await' and 'async' in: {warning_text}"
    );
}

test "jsx: string literal in event handler warns" {
    program = JacProgram();
    program.compile(fixture_path("jsx_string_handler.jac"));
    assert len(program.warnings_had) >= 1 , (
        f"Expected warning about string in event handler, got {len(
            program.warnings_had
        )}"
    );
    warning_text = _all_warnings_text(program);
    assert "onChange" in warning_text or "event" in warning_text.lower() , (
        f"Expected warning about event handler in: {warning_text}"
    );
}

# ── Backward Compatibility ──
test "backward compat: valid code compiles without errors" {
    program = JacProgram();
    program.compile(fixture_path("valid_comprehensive.jac"));
    assert len(program.errors_had) == 0 , (
        f"Valid code should have 0 errors, got {len(program.errors_had)}: " + _all_errors_text(
            program
        )
    );
}
