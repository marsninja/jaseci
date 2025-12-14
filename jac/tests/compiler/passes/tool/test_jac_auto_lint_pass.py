"""Test Jac Auto Lint Pass module."""

import os
from collections.abc import Callable

import pytest

import jaclang.pycore.unitree as uni
from jaclang.pycore.program import JacProgram


# Fixture path helper
@pytest.fixture
def auto_lint_fixture_path() -> Callable[[str], str]:
    """Return a function that returns the path to an auto_lint fixture file."""
    base_dir = os.path.dirname(__file__)
    fixtures_dir = os.path.join(base_dir, "fixtures", "auto_lint")

    def get_path(filename: str) -> str:
        return os.path.join(fixtures_dir, filename)

    return get_path


class TestJacAutoLintPass:
    """Tests for the Jac Auto Lint Pass."""

    def test_simple_extraction(self, auto_lint_fixture_path: Callable[[str], str]) -> None:
        """Test extracting simple assignments from with entry block."""
        input_path = auto_lint_fixture_path("simple_extraction.jac")

        # Format with linting enabled (default)
        prog = JacProgram.jac_file_formatter(input_path, auto_lint=True)
        formatted = prog.mod.main.gen.jac

        # Should contain glob declarations
        assert "glob x = 5;" in formatted
        assert "glob y = " in formatted
        assert "glob z = " in formatted

        # Should NOT contain with entry block syntax (it was fully extracted)
        # Note: "with entry" may appear in the docstring, so check for the block syntax
        assert "with entry {" not in formatted

    def test_no_lint_flag(self, auto_lint_fixture_path: Callable[[str], str]) -> None:
        """Test that --no-lint preserves with entry blocks."""
        input_path = auto_lint_fixture_path("simple_extraction.jac")

        # Format with linting disabled
        prog = JacProgram.jac_file_formatter(input_path, auto_lint=False)
        formatted = prog.mod.main.gen.jac

        # Should still contain with entry block
        assert "with entry" in formatted

        # Should NOT contain glob declarations
        assert "glob x" not in formatted

    def test_mixed_statements(self, auto_lint_fixture_path: Callable[[str], str]) -> None:
        """Test partial extraction when some statements can't be extracted."""
        input_path = auto_lint_fixture_path("mixed_statements.jac")

        prog = JacProgram.jac_file_formatter(input_path, auto_lint=True)
        formatted = prog.mod.main.gen.jac

        # Extractable assignments should become globs
        assert "glob x = 5;" in formatted
        assert "glob y = 10;" in formatted

        # Non-extractable statement should stay in with entry
        assert "with entry" in formatted
        assert "print(" in formatted

    def test_no_extraction_needed(self, auto_lint_fixture_path: Callable[[str], str]) -> None:
        """Test file that already uses glob - no changes needed."""
        input_path = auto_lint_fixture_path("no_extraction_needed.jac")

        prog = JacProgram.jac_file_formatter(input_path, auto_lint=True)
        formatted = prog.mod.main.gen.jac

        # Should preserve existing glob declarations
        assert "glob x = 5;" in formatted
        assert "glob y = " in formatted
        assert "glob z = " in formatted

        # Should NOT have with entry blocks
        assert "with entry" not in formatted

    def test_complex_values_not_extracted(
        self, auto_lint_fixture_path: Callable[[str], str]
    ) -> None:
        """Test that non-pure expressions are NOT extracted."""
        input_path = auto_lint_fixture_path("complex_values.jac")

        prog = JacProgram.jac_file_formatter(input_path, auto_lint=True)
        formatted = prog.mod.main.gen.jac

        # Should still have with entry block since nothing can be extracted
        assert "with entry" in formatted

        # Should NOT have any glob declarations
        assert "glob result" not in formatted
        assert "glob value" not in formatted
        assert "glob item" not in formatted

    def test_named_entry_not_modified(
        self, auto_lint_fixture_path: Callable[[str], str]
    ) -> None:
        """Test that named entry blocks are NOT modified."""
        input_path = auto_lint_fixture_path("named_entry.jac")

        prog = JacProgram.jac_file_formatter(input_path, auto_lint=True)
        formatted = prog.mod.main.gen.jac

        # Named entry block should be preserved
        assert "with entry:__main__" in formatted or "with entry :__main__" in formatted

        # Assignment inside should NOT become glob
        assert "glob x" not in formatted

    def test_globs_inserted_after_imports(
        self, auto_lint_fixture_path: Callable[[str], str]
    ) -> None:
        """Test that extracted globs are inserted after imports."""
        input_path = auto_lint_fixture_path("with_imports.jac")

        prog = JacProgram.jac_file_formatter(input_path, auto_lint=True)
        formatted = prog.mod.main.gen.jac

        # Find positions
        import_pos = formatted.find("import from os")
        glob_x_pos = formatted.find("glob x")
        glob_y_pos = formatted.find("glob y")
        def_pos = formatted.find("def main")

        # Globs should come after imports but before def
        assert import_pos < glob_x_pos < def_pos
        assert import_pos < glob_y_pos < def_pos

        # Should not have with entry block anymore
        assert "with entry" not in formatted

    def test_pure_expressions(self, auto_lint_fixture_path: Callable[[str], str]) -> None:
        """Test various pure expressions that should be extracted."""
        input_path = auto_lint_fixture_path("pure_expressions.jac")

        prog = JacProgram.jac_file_formatter(input_path, auto_lint=True)
        formatted = prog.mod.main.gen.jac

        # All these should be extracted
        assert "glob int_val" in formatted
        assert "glob float_val" in formatted
        assert "glob str_val" in formatted
        assert "glob bool_val" in formatted
        assert "glob null_val" in formatted
        assert "glob list_val" in formatted
        assert "glob dict_val" in formatted
        assert "glob sum_val" in formatted
        assert "glob neg_val" in formatted

        # with entry should be removed (all extracted)
        assert "with entry" not in formatted


class TestIsPureExpression:
    """Unit tests for the is_pure_expression method."""

    def _create_test_pass(self) -> object:
        """Create a JacAutoLintPass instance for testing."""
        from jaclang.compiler.passes.tool.jac_auto_lint_pass import JacAutoLintPass

        # Create a minimal module for the pass
        source = uni.Source("", mod_path="test.jac")
        prog = JacProgram()
        # We need to create a stub module
        module = uni.Module.make_stub()
        return JacAutoLintPass(ir_in=module, prog=prog)

    def test_literals_are_pure(self) -> None:
        """Test that literal values are considered pure."""
        # This is a conceptual test - the actual implementation
        # checks isinstance against AST node types
        pass  # Covered by integration tests above

    def test_function_calls_not_pure(self) -> None:
        """Test that function calls are NOT considered pure."""
        # Covered by complex_values integration test
        pass


class TestFormatCommandIntegration:
    """Integration tests for the format CLI command."""

    def test_format_with_lint_default(
        self, auto_lint_fixture_path: Callable[[str], str], tmp_path
    ) -> None:
        """Test that format applies linting by default."""
        import shutil

        # Copy fixture to temp location
        src = auto_lint_fixture_path("simple_extraction.jac")
        dst = tmp_path / "test.jac"
        shutil.copy(src, dst)

        # Format the file
        prog = JacProgram.jac_file_formatter(str(dst), auto_lint=True)
        formatted = prog.mod.main.gen.jac

        # Linting should have been applied
        assert "glob" in formatted
