"""Tests exposing gaps in the Jac type checker.

These tests document missing type checking behavior identified through
systematic analysis. Each test is expected to FAIL under the current
implementation, confirming the gap exists. Once a gap is addressed,
the corresponding test should pass.

Gap index:
  #35 - Augmented assignment (+=, -=, etc.) has no operator validation
  #36 - AwaitExpr returns UnknownType instead of awaited type
  #37 - YieldExpr returns UnknownType instead of generator type
  #38 - Generic TypeVar binding is partially disabled
  #40 - WhileStmt condition not validated to be bool-like
  #41 - AssertStmt condition not type-checked
  #42 - DeleteStmt target not type-checked
  #43 - Walker visit/disengage/report have zero type validation
  #44 - Context manager __exit__ not checked (only __enter__)
  #45 - Enum iteration raises false positive error
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
# Gap #35: Augmented assignment (+=, -=, etc.) has no operator validation
#
# exit_assignment in type_checker_pass.impl.jac ignores nd.aug_op entirely.
# The Assignment AST node has an aug_op: (Token | None) field that is never
# inspected. When aug_op is set (e.g., +=), the type checker should verify
# that the augmented operator is valid for the LHS and RHS types (e.g.,
# check for __iadd__, __isub__, etc.). Instead, it only checks basic
# assignability of the RHS to the LHS type.
#
# Impact: `x: str = "hello"; x += 5` produces no error even though
#         str.__iadd__(int) is not valid. Similarly, `lst -= 1` on a list
#         produces no error even though list has no __isub__. Five distinct
#         invalid augmented operations are tested.
# =========================================================================
test "gap 35 augmented assign no operator check" {
    program = compile_and_check("checker_gap_aug_assign.jac");

    # Expected: at least 5 errors for invalid augmented operations:
    #   str += int, str += list, list -= int, int += str, bool //= float, str /= str
    # Actual: 0 errors (aug_op is completely ignored in exit_assignment)
    assert len(program.errors_had) >= 5 , f"Gap #35: Augmented assignment has no operator validation. "
    f"Expected at least 5 type errors but got {len(program.errors_had)}. "
    f"The type checker ignores nd.aug_op entirely in exit_assignment. "
    f"str += int, list -= int, int += str, bool //= float, str /= str all go unchecked.";
}

# =========================================================================
# Gap #36: AwaitExpr returns UnknownType instead of the awaited type
#
# There is no `case uni.AwaitExpr()` in _get_type_of_expression_core
# (type_evaluator.impl.jac). The AwaitExpr AST node has a target: Expr
# field, but its type is never evaluated — it falls through to the
# default UnknownType return. The await expression should unwrap the
# coroutine's return type (e.g., `await fetch_number()` where
# fetch_number returns int should give type int).
#
# Impact: All type errors involving awaited values are silently missed.
#         `bad: str = await fetch_int()` produces no error because the
#         await expression is UnknownType, which is assignable to anything.
# =========================================================================
test "gap 36 await returns unknown" {
    program = compile_and_check("checker_gap_await_unknown.jac");

    # Expected: at least 4 errors (await int->str, await dict->int,
    #   await str->int, await int->str, await int->bool)
    # Actual: 0 errors (AwaitExpr returns UnknownType, assignable to anything)
    assert len(program.errors_had) >= 4 , f"Gap #36: AwaitExpr returns UnknownType. "
    f"Expected at least 4 type errors but got {len(program.errors_had)}. "
    f"No case handler exists for AwaitExpr in _get_type_of_expression_core. "
    f"await coroutine() falls through to UnknownType instead of the return type.";
}

# =========================================================================
# Gap #37: YieldExpr returns UnknownType instead of proper generator type
#
# There is no `case uni.YieldExpr()` in _get_type_of_expression_core.
# Functions containing yield should return Generator[T], not T directly.
# The checker treats the declared return type as the actual return type,
# so `def count_up(n: int) -> int { yield i; }` is typed as returning
# int, when it actually returns Generator[int]. This means assigning
# the result to int produces NO error — a silent type safety hole.
#
# Impact: Generator function results are incorrectly typed as their
#         declared return type. `x: int = count_up(5)` produces no error
#         even though count_up returns a generator, not an int.
# =========================================================================
test "gap 37 yield returns unknown" {
    program = compile_and_check("checker_gap_yield_unknown.jac");

    # Expected: at least 3 errors (generator->int, generator->str,
    #   generator in arithmetic, generator as scalar parameter)
    # Actual: 0 errors (generator functions typed as returning declared type directly)
    assert len(program.errors_had) >= 3 , f"Gap #37: YieldExpr returns UnknownType. "
    f"Expected at least 3 type errors but got {len(program.errors_had)}. "
    f"Generator functions are typed as returning their declared type directly. "
    f"count_up(5) is treated as int, not Generator[int].";
}

# =========================================================================
# Gap #38: Generic TypeVar binding is partially disabled
#
# TypeVars (types.TypeVarType) exist in shared.type_params and concrete
# args in private.type_args, but when methods return T, the TypeVar is
# never substituted with the actual type argument.
# _get_method_with_overloads doesn't substitute TypeVars in return types.
#
# Impact: Box[int].get() may not return int as expected. Box[int].set("x")
#         may not error. This affects all generic class usage patterns
#         including single TypeVar, multiple TypeVars, and nested generics.
# =========================================================================
test "gap 38 generic typevar binding" {
    program = compile_and_check("checker_gap_generic_typevar.jac");

    # Expected: at least 6 errors across Box[int], Pair[str,int], Stack[float]:
    #   Box.get()->str, Box.set("hello"), Pair.first()->int, Pair.second()->str,
    #   Stack.push("pi"), Stack.peek()->str, nested Box[list[int]].get()->list[str]
    # Actual: 0 errors (TypeVar T is not properly bound/substituted)
    assert len(program.errors_had) >= 6 , f"Gap #38: Generic TypeVar binding is incomplete. "
    f"Expected at least 6 type errors but got {len(program.errors_had)}. "
    f"TypeVar bindings are not propagated through generic class methods. "
    f"Box[int].get() does not resolve T=int in the return type.";
}

# =========================================================================
# Gap #40: WhileStmt condition not validated to be bool-like
#
# There is no exit_while_stmt or enter_while_stmt handler in the type
# checker pass. The WhileStmt AST node has condition: Expr and
# body: Sequence[CodeBlockStmt], but the condition expression is not
# directly type-evaluated by the pass. Some sub-expression errors
# (like wrong function call args) are caught by their own handlers,
# but errors like nonexistent method calls and incompatible comparisons
# in while conditions are missed.
#
# Impact: `while obj.nonexistent_method()` produces no error.
#         `while "hello" > 5` produces no error for str > int.
# =========================================================================
test "gap 40 while condition not checked" {
    program = compile_and_check("checker_gap_while_cond.jac");

    # Expected: at least 3 errors:
    #   nonexistent method, wrong arg type, incompatible comparison, chained error
    # Actual: 2 errors (function arg errors caught by exit_func_call, but
    #   nonexistent method and str > int comparison NOT caught)
    assert len(program.errors_had) >= 3 , f"Gap #40: WhileStmt condition is not type-checked. "
    f"Expected at least 3 type errors but got {len(program.errors_had)}. "
    f"No exit_while_stmt handler exists in the type checker pass. "
    f"Nonexistent methods and wrong arg types in while conditions go unchecked.";
}

# =========================================================================
# Gap #41: AssertStmt condition not type-checked
#
# There is no exit_assert_stmt handler. The AssertStmt AST node has
# condition: Expr and error_msg: (Expr | None), neither of which are
# directly type-evaluated. Some sub-expression errors (like wrong
# function call args) are caught by their own handlers, but errors
# like nonexistent method calls and incompatible binary comparisons
# in assert conditions are missed.
#
# Impact: `assert obj.nonexistent()` produces no error.
#         `assert "hello" > 5` produces no error for str > int.
# =========================================================================
test "gap 41 assert stmt not checked" {
    program = compile_and_check("checker_gap_assert_stmt.jac");

    # Expected: at least 6 errors:
    #   wrong arg in condition (1), wrong arg in message (1),
    #   nonexistent method (1), double errors in both (2),
    #   binary expression error (1)
    # Actual: 4 errors (function arg errors caught by exit_func_call, but
    #   nonexistent method and str > int comparison NOT caught)
    assert len(program.errors_had) >= 6 , f"Gap #41: AssertStmt is not type-checked. "
    f"Expected at least 6 type errors but got {len(program.errors_had)}. "
    f"No exit_assert_stmt handler exists. Nonexistent method calls and "
    f"binary comparison errors in assert conditions are missed.";
}

# =========================================================================
# Gap #42: DeleteStmt target not type-checked
#
# There is no exit_delete_stmt handler. The DeleteStmt AST node has
# target: Expr which is never type-evaluated. Any type errors in the
# target expression (accessing nonexistent attributes, wrong index types)
# will be missed.
#
# Impact: `del obj.nonexistent_attr` produces no type error even though
#         the attribute doesn't exist. `del dict[wrong_type]` is not caught.
# =========================================================================
test "gap 42 delete stmt not checked" {
    program = compile_and_check("checker_gap_delete_stmt.jac");

    # Expected: at least 3 errors:
    #   nonexistent attr, wrong index type, nested nonexistent attr, outer nonexistent
    # Actual: 0 errors (delete target is not type-evaluated)
    assert len(program.errors_had) >= 3 , f"Gap #42: DeleteStmt is not type-checked. "
    f"Expected at least 3 type errors but got {len(program.errors_had)}. "
    f"No exit_delete_stmt handler exists. del obj.nonexistent goes unchecked.";
}

# =========================================================================
# Gap #43: Walker visit/disengage/report have zero type validation
#
# The type checker has no handlers for VisitStmt (target: Expr),
# DisengageStmt, or ReportStmt (expr: Expr). Visit targets should be
# validated as node types. Report expressions should be type-evaluated
# for errors in sub-expressions. Some sub-expression errors (like wrong
# function call args) are caught by their own handlers, but visit-specific
# and report-specific type errors are missed.
#
# Impact: `visit 42` (visiting a non-node) produces no error.
#         `report self.nonexistent()` is not caught.
# =========================================================================
test "gap 43 walker stmts not checked" {
    program = compile_and_check("checker_gap_walker_stmts.jac");

    # Expected: at least 4 errors:
    #   visit non-node (int), visit non-node (str), visit wrong arg,
    #   report wrong arg, report nonexistent method
    # Actual: 2 errors (function arg errors caught, but visit-to-non-node
    #   and nonexistent method on self NOT caught)
    assert len(program.errors_had) >= 4 , f"Gap #43: Walker statements not type-checked. "
    f"Expected at least 4 type errors but got {len(program.errors_had)}. "
    f"No handlers exist for VisitStmt/DisengageStmt/ReportStmt. "
    f"visit 42 and report with type errors go completely unchecked.";
}

# =========================================================================
# Gap #44: Context manager __exit__ not checked (only __enter__)
#
# exit_with_stmt (line 484) only checks for __enter__ method. A valid
# context manager must also have __exit__. An object with __enter__ but
# no __exit__ should produce a type error. Additionally, the as-variable
# type should be bound to __enter__'s return type.
#
# Impact: Objects with only __enter__ are accepted as context managers.
#         `with EnterOnlyManager() as val` produces no error even though
#         __exit__ is missing. The type of `val` is not set from __enter__.
# =========================================================================
test "gap 44 context manager exit not checked" {
    program = compile_and_check("checker_gap_ctx_mgr_exit.jac");

    # Expected: at least 2 errors:
    #   EnterOnlyManager missing __exit__ (x2 for single and multi),
    #   alias type binding (str->int, list[int]->str)
    # Actual: 0 errors (only __enter__ is checked, __exit__ and alias ignored)
    assert len(program.errors_had) >= 2 , f"Gap #44: Context manager __exit__ not checked. "
    f"Expected at least 2 type errors but got {len(program.errors_had)}. "
    f"exit_with_stmt only checks __enter__, never validates __exit__. "
    f"Also missing: alias type binding from __enter__ return type.";
}

# =========================================================================
# Gap #45: Enum iteration raises false positive error
#
# exit_in_for_stmt checks __iter__ via get_type_of_magic_method_call.
# Python enums are iterable (EnumMeta provides __iter__), but the Jac
# type system doesn't model the enum metaclass. The enum ClassType
# doesn't have __iter__ in its MRO, so iterating over an enum class
# raises a false "not iterable" error.
#
# Impact: Valid code `for member in Color` produces a type error.
#         All enum iteration patterns including comprehensions, len(),
#         and membership tests may produce false positives.
# =========================================================================
test "gap 45 enum iteration false positive" {
    program = compile_and_check("checker_gap_enum_iter.jac");

    # Expected: 0 errors (iterating over enum is valid Python/Jac)
    # Actual: >= 1 error (enum class not recognized as iterable)
    assert len(program.errors_had) == 0 , f"Gap #45: Enum iteration raises false positive. "
    f"Expected 0 type errors but got {len(program.errors_had)}: "
    f"{[str(e) for e in program.errors_had]}. "
    f"Iterating over an enum class should be valid (EnumMeta provides __iter__).";
}
