"""Tests exposing known shortcomings in the Jac type checker.

These tests document incomplete type checking behavior that should
be addressed in future improvements. Each test is expected to FAIL
under the current implementation, confirming the shortcoming exists.

Shortcoming index:
  #22 - No type checking on destructuring RHS (non-iterable accepted)
  #23 - set is assignable to frozenset (unsound mutability coercion)
"""

import os;
import from pathlib { Path }
import jaclang;
import from jaclang.compiler.passes.main.type_checker_pass { TypeCheckPass }
import from jaclang.jac0core.program { JacProgram }

glob JAC_ROOT = str(Path(jaclang.__file__).parent.parent),
     CHECKER_FIXTURES = os.path.join(
         JAC_ROOT, "tests", "compiler", "passes", "main", "fixtures", "checker"
     );

def compile_and_check(fixture_name: str) -> JacProgram {
    """Compile a checker fixture and run the type check pass."""
    program = JacProgram();
    mod = program.compile(os.path.join(CHECKER_FIXTURES, fixture_name));
    TypeCheckPass(ir_in=mod, prog=program);
    return program;
}

# =========================================================================
# Shortcoming #22: No type checking on destructuring RHS
#
# When destructuring `(a, b) = expr`, the type checker does not verify
# that the RHS is iterable. This means non-iterable values like int,
# bool, or None can be destructured without any error.
#
# Impact: `(a, b) = 5` compiles without error but crashes at runtime.
# =========================================================================
test "shortcoming_22_destructure_non_iterable" {
    program = compile_and_check("checker_bug_destructure_non_iterable.jac");

    # Expected: 3 errors (int, bool, NoneType are not iterable)
    # Actual: 0 errors (no iterability check on destructuring RHS)
    assert len(program.errors_had) >= 3 , f"Shortcoming #22: No type checking on destructuring RHS. "
    f"Expected at least 3 type errors but got {len(program.errors_had)}. "
    f"'(a, b) = 5' should error because int is not iterable.";
}

# =========================================================================
# Shortcoming #23: set is assignable to frozenset without error
#
# The type checker does not distinguish set from frozenset in
# assignments. In strict typing (mypy/pyright), set and frozenset are
# distinct types with different mutability guarantees. A mutable set
# should not be silently accepted where an immutable frozenset is expected.
#
# Impact: Code that expects frozenset immutability guarantees may receive
#         a mutable set that can be modified through the original reference.
# =========================================================================
test "shortcoming_23_set_to_frozenset_unsound" {
    program = compile_and_check("checker_bug_set_to_frozenset.jac");

    # Expected: 2 errors (set not assignable to frozenset)
    # Actual: 0 errors (set -> frozenset is not checked)
    assert len(program.errors_had) >= 2 , f"Shortcoming #23: set is assignable to frozenset without error. "
    f"Expected at least 2 type errors but got {len(program.errors_had)}. "
    f"set should NOT be assignable to frozenset (different mutability).";
}
