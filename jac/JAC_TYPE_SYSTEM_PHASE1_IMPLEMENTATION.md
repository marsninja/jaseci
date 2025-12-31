# Jac Type System: Phase 1 Implementation Guide

## Overview

This document provides detailed implementation specifications for Phase 1 of the Jac type system production-grade completion. Phase 1 focuses on **core type system enhancements** that fix critical gaps causing incorrect type inference.

**Estimated Effort:** 4-6 weeks
**Priority:** Critical
**Prerequisites:** Familiarity with Jac compiler architecture and Pyright type system

---

## Table of Contents

1. [Task 1.1: Literal Types](#task-11-literal-types)
2. [Task 1.2: Boolean Literal Support](#task-12-boolean-literal-support)
3. [Task 1.3: Fix Iterator Protocol](#task-13-fix-iterator-protocol)
4. [Task 1.4: Type Variance Rules](#task-14-type-variance-rules)
5. [Task 1.5: Enum Type Support](#task-15-enum-type-support)
6. [Task 1.6: Complete Callable Validation](#task-16-complete-callable-validation)
7. [New Test Fixtures](#new-test-fixtures)
8. [New Test Cases](#new-test-cases)

---

## Task 1.1: Literal Types

### Problem Statement

Currently, string literals like `"hello"` are typed as `str` instead of `Literal["hello"]`. This prevents precise type inference for:
- String literal comparisons
- Overload resolution based on literal values
- Type narrowing with literal checks

### Files to Modify

| File | Changes |
|------|---------|
| `jac/jaclang/compiler/type_system/types.jac` | Add `LiteralType` class |
| `jac/jaclang/compiler/type_system/impl/types.impl.jac` | Add `LiteralType` implementation |
| `jac/jaclang/compiler/type_system/type_evaluator.impl/construct_types.impl.jac` | Update literal handling |
| `jac/jaclang/compiler/type_system/type_evaluator.impl/type_evaluator.impl.jac` | Update `assign_type` |

### Code Changes

#### 1. Add `LiteralType` to `types.jac` (after line 110)

```jac
"""Represents a literal type with a specific value."""
class LiteralType(TypeBase) {
    with entry {
        CATEGORY: ClassVar[TypeCategory] = TypeCategory.Literal;
    }

    def init(
        self: LiteralType,
        value: str | int | float | bool,
        base_type: ClassType,
        flags: TypeFlags = TypeFlags.Instance
    ) -> None;

    def __str__(self: LiteralType) -> str;
    def __eq__(self: LiteralType, other: object) -> bool;
    def widen(self: LiteralType) -> ClassType;
}
```

#### 2. Update `TypeCategory` enum in `types.jac` (add after line 26)

```jac
class TypeCategory(IntEnum) {
    with entry {
        Unbound = auto();
        Unknown = auto();
        Never = auto();
        Any = auto();
        Module = auto();
        TypeVar = auto();
        Class = auto();
        Function = auto();
        Overload = auto();
        Union = auto();
        Literal = auto();  # <-- Add this
    }
}
```

#### 3. Add implementation to `impl/types.impl.jac`

```jac
"""Initialize a literal type."""
impl LiteralType.init(
    self: LiteralType,
    value: str | int | float | bool,
    base_type: ClassType,
    flags: TypeFlags = TypeFlags.Instance
) -> None {
    super.init(flags=flags);
    self.value = value;
    self.base_type = base_type;
}

"""String representation of literal type."""
impl LiteralType.__str__(self: LiteralType) -> str {
    if isinstance(self.value, str) {
        return f'Literal["{self.value}"]';
    }
    return f'Literal[{self.value}]';
}

"""Check equality with another literal type."""
impl LiteralType.__eq__(self: LiteralType, other: object) -> bool {
    if not isinstance(other, LiteralType) {
        return False;
    }
    return self.value == other.value and self.base_type.shared == other.base_type.shared;
}

"""Widen literal type to its base type."""
impl LiteralType.widen(self: LiteralType) -> ClassType {
    return self.base_type.clone_as_instance();
}
```

#### 4. Update `construct_types.impl.jac` - `get_type_of_string` method

```jac
"""Return the effective type of the string."""
impl TypeEvaluator.get_type_of_string(
    self: TypeEvaluator, node: uni.String | uni.MultiString
) -> TypeBase {
    assert self.prefetch.str_class is not None;
    # Create a LiteralType for string literals
    if isinstance(node, uni.String) {
        str_value = node.value;
        # Remove quotes from the string value
        if str_value.startswith('"') or str_value.startswith("'") {
            str_value = str_value[1:-1];
        }
        return types.LiteralType(
            value=str_value,
            base_type=self.prefetch.str_class
        );
    }
    # For MultiString, widen to str since value may be complex
    return self.prefetch.str_class;
}
```

#### 5. Update `get_type_of_int` method

```jac
"""Return the effective type of the int."""
impl TypeEvaluator.get_type_of_int(self: TypeEvaluator, node: uni.Int) -> TypeBase {
    assert self.prefetch.int_class is not None;
    # Create a LiteralType for integer literals
    int_value = int(node.value);
    return types.LiteralType(
        value=int_value,
        base_type=self.prefetch.int_class
    );
}
```

#### 6. Update `assign_type` in `type_evaluator.impl.jac`

```jac
"""Assign the source type to the destination type."""
impl TypeEvaluator.assign_type(
    self: TypeEvaluator, src_type: TypeBase, dest_type: TypeBase
) -> bool {
    if types.TypeCategory.Unknown in (src_type.category, dest_type.category) {
        return True;
    }
    if src_type == dest_type {
        return True;
    }

    # Handle LiteralType: Literal[x] is assignable to its base type
    if isinstance(src_type, types.LiteralType) {
        # Literal["foo"] is assignable to str
        if dest_type.is_class_instance() {
            return self.assign_type(src_type.base_type.clone_as_instance(), dest_type);
        }
        # Literal["foo"] is assignable to Literal["foo"]
        if isinstance(dest_type, types.LiteralType) {
            return src_type.value == dest_type.value and \
                   src_type.base_type.shared == dest_type.base_type.shared;
        }
    }

    # Handle destination being Literal type
    if isinstance(dest_type, types.LiteralType) {
        # Only exact literal match is valid
        if isinstance(src_type, types.LiteralType) {
            return src_type.value == dest_type.value;
        }
        # str is NOT assignable to Literal["foo"]
        return False;
    }

    # ... rest of existing implementation ...
}
```

---

## Task 1.2: Boolean Literal Support

### Problem Statement

Boolean literals (`True`, `False`) are not properly typed. The type evaluator has a TODO comment at line 31 of `type_evaluator.impl.jac`.

### Files to Modify

| File | Changes |
|------|---------|
| `jac/jaclang/compiler/type_system/type_evaluator.jac` | Add `get_type_of_bool` method |
| `jac/jaclang/compiler/type_system/type_evaluator.impl/type_evaluator.impl.jac` | Handle `uni.Bool` case |
| `jac/jaclang/compiler/type_system/type_evaluator.impl/construct_types.impl.jac` | Implement `get_type_of_bool` |

### Code Changes

#### 1. Add method declaration to `type_evaluator.jac` (after line 167)

```jac
def get_type_of_bool(self: TypeEvaluator, node: uni.Bool) -> TypeBase;
```

#### 2. Add case in `_get_type_of_expression_core` (after line 30)

```jac
case uni.Bool():
    if self.prefetch {
        return self._convert_to_instance(self.get_type_of_bool(expr));
    }
```

#### 3. Implement in `construct_types.impl.jac`

```jac
"""Return the effective type of the boolean."""
impl TypeEvaluator.get_type_of_bool(self: TypeEvaluator, node: uni.Bool) -> TypeBase {
    assert self.prefetch.bool_class is not None;
    # Create a LiteralType for boolean literals
    bool_value = node.value == "True";
    return types.LiteralType(
        value=bool_value,
        base_type=self.prefetch.bool_class
    );
}
```

---

## Task 1.3: Fix Iterator Protocol

### Problem Statement

The current implementation uses `__getitem__` as a workaround instead of properly resolving `Iterator[T]` via `__iter__` and `__next__`. This is documented at line 352-361 of `type_evaluator.impl.jac`.

### Files to Modify

| File | Changes |
|------|---------|
| `jac/jaclang/compiler/type_system/type_evaluator.impl/type_evaluator.impl.jac` | Fix for-loop type inference |
| `jac/jaclang/compiler/type_system/type_utils.jac` | Add `get_iterator_element_type` helper |
| `jac/jaclang/compiler/type_system/impl/type_utils.impl.jac` | Implement helper |

### Code Changes

#### 1. Add helper function declaration in `type_utils.jac`

```jac
def get_iterator_element_type(
    evaluator: "TypeEvaluator",
    collection_type: types.ClassType
) -> types.TypeBase | None;
```

#### 2. Implement in `impl/type_utils.impl.jac`

```jac
"""
Get the element type of an iterable collection.

This function resolves the element type by:
1. Checking for generic type arguments (list[T] -> T)
2. Falling back to __iter__ -> __next__ return type
3. Falling back to __getitem__ return type
"""
impl get_iterator_element_type(
    evaluator: "TypeEvaluator",
    collection_type: types.ClassType
) -> types.TypeBase | None {
    # Strategy 1: Check generic type arguments
    # For list[T], dict[K, V], set[T], tuple[T, ...], the first type arg is element type
    if collection_type.private.type_args {
        # For dict, iteration yields keys (first type arg)
        # For list/set/tuple, iteration yields the element type (first type arg)
        return evaluator._convert_to_instance(collection_type.private.type_args[0]);
    }

    # Strategy 2: Try __iter__ method
    if iter_method := evaluator._lookup_class_member(collection_type, "__iter__") {
        iter_type = evaluator.get_type_of_symbol(iter_method.symbol);
        if isinstance(iter_type, types.FunctionType) and iter_type.return_type {
            # The return type should be Iterator[T], get T from __next__
            iter_return = iter_type.return_type;
            if isinstance(iter_return, types.ClassType) {
                # Try to get __next__ from the iterator
                if next_method := evaluator._lookup_class_member(iter_return, "__next__") {
                    next_type = evaluator.get_type_of_symbol(next_method.symbol);
                    if isinstance(next_type, types.FunctionType) and next_type.return_type {
                        return evaluator._convert_to_instance(next_type.return_type);
                    }
                }
                # Fallback: check type args of iterator
                if iter_return.private.type_args {
                    return evaluator._convert_to_instance(iter_return.private.type_args[0]);
                }
            }
        }
    }

    # Strategy 3: Fallback to __getitem__ (legacy iteration protocol)
    if getitem_method := evaluator._lookup_class_member(collection_type, "__getitem__") {
        getitem_type = evaluator.get_type_of_symbol(getitem_method.symbol);
        if isinstance(getitem_type, types.FunctionType) and getitem_type.return_type {
            return evaluator._convert_to_instance(getitem_type.return_type);
        }
    }

    return None;
}
```

#### 3. Update for-loop handling in `type_evaluator.impl.jac` (replace lines 350-361)

```jac
# ---- Handle for statement: for <name> in <expr> ----
if isinstance(node_.parent, uni.InForStmt) {
    collection_type = self.get_type_of_expression(node_.parent.collection);

    if isinstance(collection_type, types.ClassType) {
        element_type = type_utils.get_iterator_element_type(self, collection_type);
        if element_type is not None {
            return element_type;
        }
    }

    # If we couldn't determine the element type, return Unknown
    return types.UnknownType();
}
```

---

## Task 1.4: Type Variance Rules

### Problem Statement

Currently, `list[int]` is incorrectly assignable to `list[object]` because type variance is not implemented. This violates type safety for mutable containers.

### Files to Modify

| File | Changes |
|------|---------|
| `jac/jaclang/compiler/type_system/types.jac` | Add `Variance` enum |
| `jac/jaclang/compiler/type_system/type_evaluator.impl/type_evaluator.impl.jac` | Update `_assign_class` |
| `jac/jaclang/compiler/type_system/type_utils.jac` | Add variance checking helper |

### Code Changes

#### 1. Add `Variance` enum to `types.jac` (after `TypeFlags`)

```jac
"""Variance of a type parameter."""
class Variance(IntEnum) {
    with entry {
        Invariant = 0;    # T must match exactly (mutable containers)
        Covariant = 1;    # T can be subtype (read-only, return types)
        Contravariant = 2; # T can be supertype (write-only, parameter types)
    }
}
```

#### 2. Update `TypeVarType` in `types.jac`

```jac
"""Represents a type variable."""
class TypeVarType(TypeBase) {
    with entry {
        CATEGORY: ClassVar[TypeCategory] = TypeCategory.TypeVar;
    }

    def init(
        self: TypeVarType,
        name: str = "",
        variance: Variance = Variance.Invariant,
        bound: TypeBase | None = None
    ) -> None;
}
```

#### 3. Update `TypeVarType.init` in `impl/types.impl.jac`

```jac
"""Initialize type variable."""
impl TypeVarType.init(
    self: TypeVarType,
    name: str = "",
    variance: Variance = Variance.Invariant,
    bound: TypeBase | None = None
) -> None {
    super.init();
    self.name = name;
    self.variance = variance;
    self.bound = bound;
}
```

#### 4. Add helper to `type_utils.jac`

```jac
def check_type_args_compatibility(
    evaluator: "TypeEvaluator",
    src_type: types.ClassType,
    dest_type: types.ClassType
) -> bool;
```

#### 5. Implement in `impl/type_utils.impl.jac`

```jac
"""
Check if type arguments are compatible considering variance.

For invariant type parameters (most mutable containers):
  list[int] is NOT assignable to list[object]

For covariant type parameters (immutable containers, return types):
  tuple[int, ...] IS assignable to tuple[object, ...]

For contravariant type parameters (function parameters):
  Callable[[object], None] IS assignable to Callable[[int], None]
"""
impl check_type_args_compatibility(
    evaluator: "TypeEvaluator",
    src_type: types.ClassType,
    dest_type: types.ClassType
) -> bool {
    # If no type parameters, just check class compatibility
    if not dest_type.shared.type_params {
        return True;
    }

    # If dest has type args but src doesn't, allow (src is unparameterized)
    if not src_type.private.type_args {
        return True;
    }

    # Check each type parameter
    for (i, type_param) in enumerate(dest_type.shared.type_params) {
        if i >= len(src_type.private.type_args) or i >= len(dest_type.private.type_args) {
            break;
        }

        src_arg = src_type.private.type_args[i];
        dest_arg = dest_type.private.type_args[i];

        # Get variance (default to invariant)
        variance = types.Variance.Invariant;
        if isinstance(type_param, types.TypeVarType) {
            variance = type_param.variance;
        }

        match variance {
            case types.Variance.Invariant:
                # Must match exactly (same shared reference)
                if isinstance(src_arg, types.ClassType) and isinstance(dest_arg, types.ClassType) {
                    if src_arg.shared != dest_arg.shared {
                        return False;
                    }
                }

            case types.Variance.Covariant:
                # src_arg must be subtype of dest_arg
                if not evaluator.assign_type(
                    evaluator._convert_to_instance(src_arg),
                    evaluator._convert_to_instance(dest_arg)
                ) {
                    return False;
                }

            case types.Variance.Contravariant:
                # dest_arg must be subtype of src_arg (reversed)
                if not evaluator.assign_type(
                    evaluator._convert_to_instance(dest_arg),
                    evaluator._convert_to_instance(src_arg)
                ) {
                    return False;
                }
        }
    }
    return True;
}
```

#### 6. Update `_assign_class` in `type_evaluator.impl.jac`

Add after line 405 (after subclass check):

```jac
# Check type argument compatibility with variance
if src_type.shared == dest_type.shared {
    # Same class, check type arguments
    if not type_utils.check_type_args_compatibility(self, src_type, dest_type) {
        return False;
    }
    return True;
}
```

---

## Task 1.5: Enum Type Support

### Problem Statement

Enum types return `UnknownType` instead of being properly typed. There's a TODO at line 24 of `construct_types.impl.jac`.

### Files to Modify

| File | Changes |
|------|---------|
| `jac/jaclang/compiler/type_system/type_evaluator.impl/construct_types.impl.jac` | Handle Enum in `_get_type_of_self` |
| `jac/jaclang/compiler/type_system/type_evaluator.impl/type_evaluator.impl.jac` | Handle `uni.Enum` case |

### Code Changes

#### 1. Update `_get_type_of_self` in `construct_types.impl.jac`

```jac
"""Return the effective type of self."""
impl TypeEvaluator._get_type_of_self(
    self: TypeEvaluator, node_: uni.SpecialVarRef
) -> TypeBase {
    if method := self._get_enclosing_method(node_) {
        cls = method.method_owner;
        if isinstance(cls, uni.Archetype) {
            node_.sym = type_utils.lookup_symtab(
                method, node_.value, self.builtins_module
            );
            node_.type = self.get_type_of_class(cls).clone_as_instance();
            return node_.type;
        }
        if isinstance(cls, uni.Enum) {
            # Handle enum self type
            node_.sym = type_utils.lookup_symtab(
                method, node_.value, self.builtins_module
            );
            node_.type = self.get_type_of_enum(cls).clone_as_instance();
            return node_.type;
        }
    }
    return types.UnknownType();
}
```

#### 2. Add `get_type_of_enum` method to `type_evaluator.jac`

```jac
def get_type_of_enum(self: TypeEvaluator, node_: uni.Enum) -> types.ClassType;
```

#### 3. Implement `get_type_of_enum` in `construct_types.impl.jac`

```jac
"""Return the effective type of the enum."""
impl TypeEvaluator.get_type_of_enum(
    self: TypeEvaluator, node_: uni.Enum
) -> types.ClassType {
    # Is this type already cached?
    if node_.name_spec.type is not None {
        return cast(types.ClassType, node_.name_spec.type);
    }

    # Enums inherit from Enum base class
    base_classes: list[TypeBase] = [];
    for base_class in node_.base_classes or [] {
        base_class_type = self.get_type_of_expression(base_class);
        base_classes.append(base_class_type);
    }

    is_builtin_class = node_.find_parent_of_type(uni.Module) == self.builtins_module;

    cls_type = types.ClassType(
        types.ClassType.ClassDetailsShared(
            class_name=node_.name_spec.sym_name,
            symbol_table=node_,
            type_params=[],
            base_classes=base_classes,
            is_builtin_class=is_builtin_class,
            is_data_class=False,
        ),
        private=None,
        flags=types.TypeFlags.Instantiable,
    );

    # Compute the MRO for the enum
    type_utils.compute_mro_linearization(cls_type);

    # Cache the type
    node_.name_spec.type = cls_type;
    return cls_type;
}
```

#### 4. Update `_get_type_of_symbol` to handle Enum

In `type_evaluator.impl.jac`, update the match statement (around line 288):

```jac
case uni.Archetype() | uni.Enum():
    if isinstance(node_, uni.Enum) {
        return self.get_type_of_enum(node_);
    }
    return self.get_type_of_class(node_);
```

---

## Task 1.6: Complete Callable Validation

### Problem Statement

Objects with `__call__` method are not fully validated. There's a TODO at line 109 of `parameter_type_check.impl.jac`.

### Files to Modify

| File | Changes |
|------|---------|
| `jac/jaclang/compiler/type_system/type_evaluator.impl/parameter_type_check.impl.jac` | Validate `__call__` arguments |

### Code Changes

#### Update callable validation in `validate_call_args`

Replace lines 107-114:

```jac
# 5. Call to a callable object (__call__).
if caller_type.is_class_instance() {
    assert isinstance(caller_type, types.ClassType);

    # Look up __call__ method
    if call_method := self._lookup_object_member(caller_type, "__call__") {
        call_type = self.get_type_of_symbol(call_method.symbol);

        # Specialize if it's a method
        if isinstance(call_type, types.FunctionType) {
            call_type = call_type.specialize(caller_type);
            # Validate arguments against __call__ parameters
            arg_param_match = self.match_args_to_params(expr, call_type);
            if not arg_param_match.argument_errors {
                self.validate_arg_types(arg_param_match);
            }
            return call_type.return_type or types.UnknownType();
        }

        # Handle overloaded __call__
        if isinstance(call_type, types.OverloadedType) {
            for overload in call_type.overloads {
                specialized = overload.specialize(caller_type);
                arg_param_match = self.match_args_to_params(
                    expr, specialized, checking_overload=True
                );
                if not arg_param_match.argument_errors {
                    if self.validate_arg_types(arg_param_match, checking_overload=True) {
                        return specialized.return_type or types.UnknownType();
                    }
                }
            }
            self.add_diagnostic(
                expr,
                "No matching overload found for __call__ with the given arguments",
            );
        }

        # Recursive: __call__ returns another callable
        if isinstance(call_type, types.ClassType) and call_type.is_class_instance() {
            return self.validate_call_args(expr);  # Recursively validate
        }
    }
}
return types.UnknownType();
```

---

## New Test Fixtures

### Fixture 1: `checker_literal_types.jac`

```jac
"""Test fixture for literal type checking."""

with entry {
    # String literals
    s1: str = "hello";  # <-- Ok: Literal["hello"] assignable to str
    s2 = "world";
    s3: str = s2;  # <-- Ok

    # Integer literals
    i1: int = 42;  # <-- Ok: Literal[42] assignable to int
    i2 = 100;
    i3: int = i2;  # <-- Ok

    # Float literals
    f1: float = 3.14;  # <-- Ok
    f2: int = 3.14;  # <-- Error: float not assignable to int

    # Boolean literals
    b1: bool = True;  # <-- Ok
    b2: bool = False;  # <-- Ok
    b3: int = True;  # <-- Ok: bool is subtype of int
    b4: str = True;  # <-- Error: bool not assignable to str
}
```

### Fixture 2: `checker_boolean_literals.jac`

```jac
"""Test fixture for boolean literal type checking."""

def accepts_bool(x: bool) -> bool {
    return x;
}

def accepts_int(x: int) -> int {
    return x;
}

with entry {
    # Boolean literals should be typed
    t = True;
    f = False;

    # Should work with bool parameter
    accepts_bool(True);  # <-- Ok
    accepts_bool(False);  # <-- Ok
    accepts_bool(t);  # <-- Ok

    # Bool is subtype of int
    accepts_int(True);  # <-- Ok
    accepts_int(1);  # <-- Ok

    # String should not work
    accepts_bool("true");  # <-- Error
}
```

### Fixture 3: `checker_iterator_protocol.jac`

```jac
"""Test fixture for iterator protocol type checking."""

obj CustomIterator {
    has items: list[int] = [1, 2, 3],
        index: int = 0;

    def __iter__()  -> CustomIterator {
        return self;
    }

    def __next__()  -> int {
        if self.index >= len(self.items) {
            raise StopIteration();
        }
        result = self.items[self.index];
        self.index += 1;
        return result;
    }
}

obj CustomIterable {
    has data: list[str] = ["a", "b", "c"];

    def __iter__()  -> list[str] {
        return self.data;
    }
}

with entry {
    # Standard list iteration
    nums: list[int] = [1, 2, 3];
    for n in nums {
        x: int = n;  # <-- Ok
        y: str = n;  # <-- Error
    }

    # Dict iteration yields keys
    d: dict[str, int] = {"a": 1, "b": 2};
    for k in d {
        s: str = k;  # <-- Ok
        i: int = k;  # <-- Error
    }

    # Custom iterator
    it = CustomIterator();
    for item in it {
        a: int = item;  # <-- Ok
        b: str = item;  # <-- Error
    }

    # Custom iterable
    iterable = CustomIterable();
    for s in iterable {
        c: str = s;  # <-- Ok
        d: int = s;  # <-- Error
    }
}
```

### Fixture 4: `checker_type_variance.jac`

```jac
"""Test fixture for type variance checking."""

obj Animal {
    has name: str = "";
}

obj Dog(Animal) {
    has breed: str = "";
}

obj Cat(Animal) {
    has indoor: bool = True;
}

def process_animals(animals: list[Animal]) -> None {
    for a in animals {
        print(a.name);
    }
}

def get_dogs() -> list[Dog] {
    return [Dog(name="Rex"), Dog(name="Buddy")];
}

with entry {
    # Invariance: list[Dog] should NOT be assignable to list[Animal]
    # because lists are mutable
    dogs: list[Dog] = [Dog(name="Rex")];
    animals: list[Animal] = dogs;  # <-- Error: invariant type parameter

    # This is why: if allowed, you could do:
    # animals.append(Cat())  # Now dogs contains a Cat!

    # But reading is ok through function calls
    # (the function doesn't mutate, just reads)
    process_animals(dogs);  # <-- This should still error due to invariance

    # Same class, different type args
    int_list: list[int] = [1, 2, 3];
    str_list: list[str] = int_list;  # <-- Error

    # Nested generics
    nested: list[list[int]] = [[1, 2], [3, 4]];
    nested2: list[list[object]] = nested;  # <-- Error: inner list is also invariant
}
```

### Fixture 5: `checker_enum_types.jac`

```jac
"""Test fixture for enum type checking."""
import from enum { Enum }

enum Color {
    RED = 1,
    GREEN = 2,
    BLUE = 3
}

enum Status {
    PENDING = "pending",
    ACTIVE = "active",
    DONE = "done"
}

def paint(color: Color) -> None {
    print(color);
}

def set_status(status: Status) -> None {
    print(status);
}

with entry {
    # Enum assignment
    c: Color = Color.RED;  # <-- Ok
    s: Status = Status.ACTIVE;  # <-- Ok

    # Function calls with enums
    paint(Color.BLUE);  # <-- Ok
    set_status(Status.DONE);  # <-- Ok

    # Wrong enum type
    paint(Status.ACTIVE);  # <-- Error: Status not assignable to Color
    set_status(Color.RED);  # <-- Error: Color not assignable to Status

    # Enum not assignable to primitive
    i: int = Color.RED;  # <-- Error (unless we support enum value access)
    st: str = Status.PENDING;  # <-- Error
}
```

### Fixture 6: `checker_callable_objects.jac`

```jac
"""Test fixture for callable object type checking."""

obj Adder {
    has base: int = 0;

    def __call__(x: int, y: int)  -> int {
        return self.base + x + y;
    }
}

obj Greeter {
    has prefix: str = "Hello";

    def __call__(name: str)  -> str {
        return f"{self.prefix}, {name}!";
    }
}

obj Multiplier {
    has factor: int = 2;

    def __call__(x: int)  -> int {
        return x * self.factor;
    }

    def __call__(x: float)  -> float {
        return x * self.factor;
    }
}

with entry {
    # Basic callable
    adder = Adder(base=10);
    result1: int = adder(5, 3);  # <-- Ok, returns int
    result2: str = adder(5, 3);  # <-- Error: int not assignable to str

    # Wrong argument types
    adder("a", "b");  # <-- Error: str not assignable to int

    # Missing arguments
    adder(5);  # <-- Error: missing argument 'y'

    # String callable
    greeter = Greeter();
    msg: str = greeter("World");  # <-- Ok
    num: int = greeter("World");  # <-- Error: str not assignable to int

    # Wrong argument type
    greeter(42);  # <-- Error: int not assignable to str

    # Overloaded callable
    mult = Multiplier();
    r1: int = mult(5);  # <-- Ok
    r2: float = mult(3.14);  # <-- Ok
    r3: str = mult(5);  # <-- Error
}
```

---

## New Test Cases

Add the following tests to `jac/tests/compiler/passes/main/test_checker_pass.py`:

```python
def test_literal_types(fixture_path: Callable[[str], str]) -> None:
    """Test literal type checking."""
    program = JacProgram()
    mod = program.compile(fixture_path("checker_literal_types.jac"))
    TypeCheckPass(ir_in=mod, prog=program)
    assert len(program.errors_had) == 2
    _assert_error_pretty_found(
        """
        f2: int = 3.14;  # <-- Error
        ^^^^^^^^^^^^^^^
    """,
        program.errors_had[0].pretty_print(),
    )
    _assert_error_pretty_found(
        """
        b4: str = True;  # <-- Error
        ^^^^^^^^^^^^^^^
    """,
        program.errors_had[1].pretty_print(),
    )


def test_boolean_literals(fixture_path: Callable[[str], str]) -> None:
    """Test boolean literal type checking."""
    program = JacProgram()
    mod = program.compile(fixture_path("checker_boolean_literals.jac"))
    TypeCheckPass(ir_in=mod, prog=program)
    assert len(program.errors_had) == 1
    _assert_error_pretty_found(
        """
        accepts_bool("true");  # <-- Error
                     ^^^^^^
    """,
        program.errors_had[0].pretty_print(),
    )


def test_iterator_protocol(fixture_path: Callable[[str], str]) -> None:
    """Test iterator protocol type checking."""
    program = JacProgram()
    mod = program.compile(fixture_path("checker_iterator_protocol.jac"))
    TypeCheckPass(ir_in=mod, prog=program)
    assert len(program.errors_had) == 4
    # Each for loop should have one error (assigning element to wrong type)
    expected_errors = [
        "y: str = n;",  # list[int] iteration
        "i: int = k;",  # dict[str, int] iteration (keys are str)
        "b: str = item;",  # CustomIterator yields int
        "d: int = s;",  # CustomIterable yields str
    ]
    for i, expected in enumerate(expected_errors):
        assert expected in program.errors_had[i].pretty_print()


def test_type_variance(fixture_path: Callable[[str], str]) -> None:
    """Test type variance checking."""
    program = JacProgram()
    mod = program.compile(fixture_path("checker_type_variance.jac"))
    TypeCheckPass(ir_in=mod, prog=program)
    # Should have errors for invariant type parameter violations
    assert len(program.errors_had) >= 3
    _assert_error_pretty_found(
        """
        animals: list[Animal] = dogs;  # <-- Error
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    """,
        program.errors_had[0].pretty_print(),
    )


def test_enum_types(fixture_path: Callable[[str], str]) -> None:
    """Test enum type checking."""
    program = JacProgram()
    mod = program.compile(fixture_path("checker_enum_types.jac"))
    TypeCheckPass(ir_in=mod, prog=program)
    assert len(program.errors_had) == 4
    _assert_error_pretty_found(
        """
        paint(Status.ACTIVE);  # <-- Error
              ^^^^^^^^^^^^^
    """,
        program.errors_had[0].pretty_print(),
    )
    _assert_error_pretty_found(
        """
        set_status(Color.RED);  # <-- Error
                   ^^^^^^^^^
    """,
        program.errors_had[1].pretty_print(),
    )


def test_callable_objects(fixture_path: Callable[[str], str]) -> None:
    """Test callable object type checking."""
    program = JacProgram()
    mod = program.compile(fixture_path("checker_callable_objects.jac"))
    TypeCheckPass(ir_in=mod, prog=program)
    # Expect errors for:
    # 1. result2: str = adder(5, 3)
    # 2. adder("a", "b")
    # 3. adder(5) - missing argument
    # 4. num: int = greeter("World")
    # 5. greeter(42)
    # 6. r3: str = mult(5)
    assert len(program.errors_had) >= 6


def test_literal_type_widening(fixture_path: Callable[[str], str]) -> None:
    """Test that literal types widen correctly in assignments."""
    program = JacProgram()
    program.build(fixture_path("checker_literal_types.jac"), type_check=True)
    # Verify that s1, i1, b1 are properly typed


def test_nested_generic_variance(fixture_path: Callable[[str], str]) -> None:
    """Test variance with nested generic types."""
    program = JacProgram()
    mod = program.compile(fixture_path("checker_type_variance.jac"))
    TypeCheckPass(ir_in=mod, prog=program)
    # Should catch nested invariance violation
    _assert_error_pretty_found(
        "nested2: list[list[object]]",
        str([e.pretty_print() for e in program.errors_had]),
    )
```

---

## Summary Checklist

### Task 1.1: Literal Types
- [ ] Add `LiteralType` class to `types.jac`
- [ ] Add `Literal` to `TypeCategory` enum
- [ ] Implement `LiteralType` in `impl/types.impl.jac`
- [ ] Update `get_type_of_string` to return `LiteralType`
- [ ] Update `get_type_of_int` to return `LiteralType`
- [ ] Update `assign_type` to handle `LiteralType`
- [ ] Add `checker_literal_types.jac` fixture
- [ ] Add `test_literal_types` test

### Task 1.2: Boolean Literal Support
- [ ] Add `get_type_of_bool` declaration
- [ ] Add `uni.Bool` case in expression handling
- [ ] Implement `get_type_of_bool`
- [ ] Add `checker_boolean_literals.jac` fixture
- [ ] Add `test_boolean_literals` test

### Task 1.3: Fix Iterator Protocol
- [ ] Add `get_iterator_element_type` helper declaration
- [ ] Implement `get_iterator_element_type`
- [ ] Update for-loop type inference
- [ ] Add `checker_iterator_protocol.jac` fixture
- [ ] Add `test_iterator_protocol` test

### Task 1.4: Type Variance Rules
- [ ] Add `Variance` enum
- [ ] Update `TypeVarType` with variance
- [ ] Add `check_type_args_compatibility` helper
- [ ] Update `_assign_class` to check variance
- [ ] Add `checker_type_variance.jac` fixture
- [ ] Add `test_type_variance` test

### Task 1.5: Enum Type Support
- [ ] Add `get_type_of_enum` declaration
- [ ] Implement `get_type_of_enum`
- [ ] Update `_get_type_of_self` for enums
- [ ] Update `_get_type_of_symbol` for enums
- [ ] Add `checker_enum_types.jac` fixture
- [ ] Add `test_enum_types` test

### Task 1.6: Complete Callable Validation
- [ ] Update callable validation in `validate_call_args`
- [ ] Handle overloaded `__call__`
- [ ] Handle recursive callable
- [ ] Add `checker_callable_objects.jac` fixture
- [ ] Add `test_callable_objects` test

---

*Document Version: 1.0*
*Created: 2025-12-30*
*Parent Document: JAC_TYPE_SYSTEM_PRODUCTION_PLAN.md*
