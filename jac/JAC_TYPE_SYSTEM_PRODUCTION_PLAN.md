# Jac Type System: Production-Grade Completion Plan

## Executive Summary

This document outlines a comprehensive plan to bring the Jac type checking system to full production-grade completion. The current implementation provides a solid foundation based on Pyright's architecture, but several areas require enhancement to achieve production readiness.

---

## Table of Contents

1. [Current State Assessment](#1-current-state-assessment)
2. [Architecture Overview](#2-architecture-overview)
3. [Gap Analysis](#3-gap-analysis)
4. [Implementation Roadmap](#4-implementation-roadmap)
5. [Phase 1: Core Type System Enhancements](#5-phase-1-core-type-system-enhancements)
6. [Phase 2: Expression Coverage](#6-phase-2-expression-coverage)
7. [Phase 3: Advanced Type Features](#7-phase-3-advanced-type-features)
8. [Phase 4: IDE & Tooling Integration](#8-phase-4-ide--tooling-integration)
9. [Phase 5: Performance & Robustness](#9-phase-5-performance--robustness)
10. [Testing Strategy](#10-testing-strategy)
11. [Success Metrics](#11-success-metrics)

---

## 1. Current State Assessment

### What Works Well

The current type system has a solid foundation with the following capabilities:

| Feature | Status | Coverage |
|---------|--------|----------|
| Basic Type Inference | Implemented | ~80% |
| Class Type Checking | Implemented | ~75% |
| Function Parameter Validation | Implemented | ~85% |
| Generic Types | Partially Implemented | ~60% |
| Union Types | Implemented | ~70% |
| Protocol Checking | Basic Implementation | ~50% |
| Module Import Resolution | Implemented | ~70% |
| Binary Operators | Implemented | ~75% |
| Return Type Checking | Implemented | ~80% |
| Jac-specific Types (Node/Walker/Edge) | Implemented | ~85% |

### Key Files & Components

```
jac/jaclang/compiler/type_system/
├── types.jac                    # Core type representations (TypeBase, ClassType, FunctionType, etc.)
├── type_evaluator.jac           # Type inference engine interface
├── type_utils.jac               # Utility functions (MRO, protocol checking)
├── operations.jac               # Binary/unary operator type resolution
├── jac_builtins.pyi             # Jac-specific type stubs
└── type_evaluator.impl/
    ├── type_evaluator.impl.jac      # Core expression type inference
    ├── construct_types.impl.jac     # Type construction methods
    ├── parameter_type_check.impl.jac # Function argument validation
    ├── imported.impl.jac            # Module/import resolution
    └── evaluator_util_methods.impl.jac # Helper methods

jac/jaclang/compiler/passes/main/
├── type_checker_pass.jac        # Type checking pass orchestrator
└── impl/type_checker_pass.impl.jac # Pass implementation
```

### Test Coverage

- **45 test functions** covering major type checking scenarios
- **33 fixture files** for type checker validation
- Good coverage for: assignments, parameter matching, generics, protocols, connections

---

## 2. Architecture Overview

### Compilation Pipeline

```
Source (.jac)
     ↓
[Parser] → AST
     ↓
[SymTabBuildPass] → Symbol table construction
     ↓
[SymTabLinkPass] → Cross-module symbol linking
     ↓
[DeclImplMatchPass] → Declaration/implementation matching
     ↓
[SemanticAnalysisPass] → Structural validation
     ↓
[TypeCheckPass] → Type validation  ←── TypeEvaluator (type inference engine)
     ↓
[CodeGenPass] → Python bytecode
```

### Type Representation Hierarchy

```
TypeBase (abstract)
├── UnboundType       # Unresolved type
├── UnknownType       # Cannot determine type
├── NeverType         # Bottom type
├── AnyType           # Top type (accepts anything)
├── ModuleType        # Module types
├── TypeVarType       # Generic type variables
├── ClassType         # Class and instance types
│   ├── ClassDetailsShared   # Shared metadata (name, MRO, type params)
│   └── ClassDetailsPrivate  # Instance-specific (type arguments)
├── FunctionType      # Function signatures
├── OverloadedType    # Multiple function overloads
└── UnionType         # Union of types (A | B)
```

---

## 3. Gap Analysis

### Critical Gaps (Must Fix)

| Gap | Current State | Impact | Effort |
|-----|---------------|--------|--------|
| Literal Types | Not implemented | Prevents precise string/bool inference | Medium |
| Type Narrowing | Not implemented | No control flow analysis | High |
| Variance Rules | Not implemented | Incorrect generic subtyping | Medium |
| Iterator Protocol | Workaround using `__getitem__` | Incorrect for-loop inference | Medium |
| Callable Validation | Incomplete for `__call__` | Objects with `__call__` partially work | Medium |

### High Priority Gaps

| Gap | Current State | Impact | Effort |
|-----|---------------|--------|--------|
| Enum Type Support | TODO in code | Enums not type-checked | Medium |
| Lambda Expressions | Not handled | Lambdas return UnknownType | Medium |
| Comprehensions | Not handled | List/dict/set comprehensions not typed | Medium |
| Ternary Expressions | Not handled | Conditional expressions not typed | Low |
| Boolean Operators (`and`/`or`) | Incomplete | Type narrowing missing | Medium |
| Context Managers | Not implemented | `with` statement not typed | Medium |

### Medium Priority Gaps

| Gap | Current State | Impact | Effort |
|-----|---------------|--------|--------|
| Null-safe Operator (`?.`) | TODO in code | Optional chaining not typed | Medium |
| Type Guards | Not implemented | No user-defined narrowing | High |
| Recursive Types | Limited support | Complex recursive structures fail | Medium |
| Decorator Support | Basic | Only `@staticmethod`, `@classmethod` | Medium |
| Multiple Inheritance MRO | Incomplete | Recursive base class handling | Medium |
| Stub File Resolution | Ad-hoc | Hardcoded path checking | Medium |

### Low Priority / Nice-to-Have

| Gap | Current State | Impact | Effort |
|-----|---------------|--------|--------|
| Async/Await Types | Not implemented | Async code not typed | High |
| Final Enforcement | Detection only | Can detect but not prevent modification | Low |
| TypedDict | Not implemented | Typed dictionaries not supported | Medium |
| ParamSpec | Not implemented | Higher-order function typing limited | High |
| Concatenate | Not implemented | Callable manipulation limited | High |

---

## 4. Implementation Roadmap

### Phase 1: Core Type System Enhancements (4-6 weeks)
Focus: Fix critical gaps that cause incorrect type inference

### Phase 2: Expression Coverage (3-4 weeks)
Focus: Handle all expression types correctly

### Phase 3: Advanced Type Features (4-6 weeks)
Focus: Implement sophisticated type features

### Phase 4: IDE & Tooling Integration (2-3 weeks)
Focus: Improve developer experience

### Phase 5: Performance & Robustness (2-3 weeks)
Focus: Production hardening

---

## 5. Phase 1: Core Type System Enhancements

### 1.1 Implement Literal Types

**Files to modify:**
- `types.jac` - Add `LiteralType` class
- `type_evaluator.impl.jac` - Handle literal inference

**Implementation:**
```
class LiteralType(TypeBase):
    CATEGORY = TypeCategory.Literal

    def init(self, value: str | int | bool, base_type: ClassType) -> None:
        self.value = value
        self.base_type = base_type
```

**Tasks:**
- [ ] Add `LiteralType` to type hierarchy
- [ ] Modify string/int/float/bool literal handling to create `LiteralType`
- [ ] Implement literal type widening rules
- [ ] Add literal type comparison in `assign_type()`
- [ ] Add tests for literal type inference

### 1.2 Fix Iterator Protocol

**Current issue:** Uses `__getitem__` workaround instead of proper `__iter__`/`__next__`

**Files to modify:**
- `type_evaluator.impl.jac` (lines 350-361)
- `type_utils.jac` - Add iterator unwrapping

**Tasks:**
- [ ] Implement proper `Iterator[T]` type resolution
- [ ] Handle `__iter__` returning self-referential types
- [ ] Extract element type from `__next__` return type
- [ ] Add fallback to `__getitem__` for legacy iteration
- [ ] Test with custom iterators

### 1.3 Implement Type Variance

**Current issue:** `list[int]` incorrectly assignable to `list[object]`

**Files to modify:**
- `types.jac` - Add variance annotations to type parameters
- `type_evaluator.impl.jac` (`_assign_class` method)

**Tasks:**
- [ ] Add `Variance` enum (Invariant, Covariant, Contravariant)
- [ ] Annotate built-in generic types with variance
- [ ] Implement variance checking in `_assign_class()`
- [ ] Handle covariant containers (tuple, frozenset)
- [ ] Handle contravariant positions (function parameters)
- [ ] Add comprehensive variance tests

### 1.4 Complete Callable Type Checking

**Current issue:** Objects with `__call__` partially validated

**Files to modify:**
- `parameter_type_check.impl.jac` (line 107-114)
- `type_evaluator.impl.jac`

**Tasks:**
- [ ] Fully validate arguments when calling `__call__`
- [ ] Handle recursive callable (callable returning callable)
- [ ] Support callable objects in higher-order functions
- [ ] Add tests for callable objects

### 1.5 Enum Type Support

**Current issue:** Enum types return `UnknownType`

**Files to modify:**
- `construct_types.impl.jac` (line 24)
- `types.jac` - Consider `EnumType` class

**Tasks:**
- [ ] Implement enum type extraction from `uni.Enum` nodes
- [ ] Handle enum member access
- [ ] Support enum value types
- [ ] Add enum type tests

---

## 6. Phase 2: Expression Coverage

### 2.1 Lambda Expression Types

**Files to modify:**
- `type_evaluator.impl.jac` - Add `case uni.LambdaExpr()`

**Tasks:**
- [ ] Create `FunctionType` from lambda signature
- [ ] Infer parameter types from context
- [ ] Infer return type from body
- [ ] Handle lambda in type annotations
- [ ] Add lambda type tests

### 2.2 Comprehension Types

**Files to modify:**
- `type_evaluator.impl.jac` - Add cases for comprehensions

**Tasks:**
- [ ] Handle `ListComp` → `list[T]`
- [ ] Handle `DictComp` → `dict[K, V]`
- [ ] Handle `SetComp` → `set[T]`
- [ ] Handle `GeneratorExp` → `Generator[T, None, None]`
- [ ] Properly type iteration variables in comprehensions
- [ ] Add comprehension type tests

### 2.3 Ternary Expression Types

**Files to modify:**
- `type_evaluator.impl.jac` - Add `case uni.IfElseExpr()`

**Tasks:**
- [ ] Compute union of true/false branch types
- [ ] Handle None in ternary branches
- [ ] Consider literal narrowing in branches
- [ ] Add ternary expression tests

### 2.4 Boolean Operator Types

**Files to modify:**
- `operations.jac` - Enhance boolean operator handling

**Tasks:**
- [ ] Implement `and` return type (narrow to truthy)
- [ ] Implement `or` return type (first truthy or last)
- [ ] Handle short-circuit evaluation in types
- [ ] Add boolean operator tests

### 2.5 Slice Expression Types

**Files to modify:**
- `type_evaluator.impl.jac` - Enhance `IndexSlice` handling

**Tasks:**
- [ ] Handle `seq[start:stop:step]` returning same sequence type
- [ ] Validate slice indices are integers
- [ ] Handle `__getitem__` with `slice` object
- [ ] Add slice type tests

---

## 7. Phase 3: Advanced Type Features

### 3.1 Type Narrowing / Control Flow Analysis

**Description:** Track type changes through control flow

**Files to create/modify:**
- New: `type_narrowing.jac` - Narrowing rules
- `type_checker_pass.impl.jac` - Apply narrowing in conditions

**Tasks:**
- [ ] Implement basic narrowing for `isinstance()` checks
- [ ] Implement narrowing for `is None` / `is not None`
- [ ] Handle narrowing in `if/elif/else` branches
- [ ] Handle narrowing in `match` statements
- [ ] Implement type guards (`TypeGuard[T]`)
- [ ] Track narrowing through assignments
- [ ] Add control flow tests

### 3.2 Null-Safe Operator (`?.`)

**Current:** TODO in `type_evaluator.impl.jac` line 95

**Tasks:**
- [ ] Handle `expr?.member` returning `T | None`
- [ ] Chain null-safe operators
- [ ] Handle null-safe with function calls `expr?.method()`
- [ ] Add null-safe operator tests

### 3.3 Context Managers

**Files to modify:**
- `type_evaluator.impl.jac` - Handle `with` statements

**Tasks:**
- [ ] Validate `__enter__` and `__exit__` methods exist
- [ ] Infer type from `__enter__` return value
- [ ] Handle async context managers (`__aenter__`/`__aexit__`)
- [ ] Add context manager tests

### 3.4 Decorator Type Transformation

**Files to modify:**
- `construct_types.impl.jac` - Enhance decorator handling

**Tasks:**
- [ ] Implement `@property` type transformation
- [ ] Implement `@classmethod` type transformation (done)
- [ ] Implement `@staticmethod` type transformation (done)
- [ ] Handle custom decorators with return type
- [ ] Support decorator factories
- [ ] Add decorator type tests

### 3.5 Multiple Inheritance & MRO

**Current:** MRO computation exists but recursive base handling incomplete

**Files to modify:**
- `type_utils.jac` (`compute_mro_linearization`)
- `type_evaluator.impl.jac` (`_assign_class` line 426)

**Tasks:**
- [ ] Complete C3 linearization for complex hierarchies
- [ ] Handle diamond inheritance
- [ ] Recursively check all base classes for protocol matching
- [ ] Add multiple inheritance tests

---

## 8. Phase 4: IDE & Tooling Integration

### 4.1 Enhanced Error Messages

**Tasks:**
- [ ] Include expected vs actual type in all error messages
- [ ] Add "Did you mean?" suggestions for member access errors
- [ ] Provide fix suggestions for common type errors
- [ ] Show type inference path for complex errors

### 4.2 Hover Information

**Files to modify:**
- `type_utils.jac` - Enhance completion items

**Tasks:**
- [ ] Provide rich type information on hover
- [ ] Show generic type arguments in hover
- [ ] Display function signatures with parameter types
- [ ] Show documentation strings with types

### 4.3 Go-to-Definition Improvements

**Tasks:**
- [ ] Ensure all type annotations are resolvable
- [ ] Handle generic type parameter definitions
- [ ] Support jump to overloaded method definitions
- [ ] Handle imported type definitions

### 4.4 Auto-Completion Enhancements

**Tasks:**
- [ ] Type-aware completion suggestions
- [ ] Filter completions by expected type
- [ ] Rank completions by type compatibility
- [ ] Support generic method completion

---

## 9. Phase 5: Performance & Robustness

### 5.1 Caching Improvements

**Tasks:**
- [ ] Cache type computation results more aggressively
- [ ] Implement cache invalidation for incremental changes
- [ ] Cache module type information across compilations
- [ ] Profile and optimize hot paths

### 5.2 Circular Reference Handling

**Current:** Basic handling via `SymbolResolutionStackEntry`

**Tasks:**
- [ ] Improve cycle detection for complex cases
- [ ] Handle mutually recursive types
- [ ] Add timeout for type resolution
- [ ] Provide meaningful errors for unresolvable cycles

### 5.3 Error Recovery

**Tasks:**
- [ ] Continue type checking after errors
- [ ] Provide partial type information on error
- [ ] Handle malformed AST nodes gracefully
- [ ] Add fuzzing tests for robustness

### 5.4 Strict Mode

**Tasks:**
- [ ] Implement strict mode flag
- [ ] Disallow `UnknownType` in strict mode
- [ ] Require explicit type annotations in strict mode
- [ ] Add strict mode configuration options

---

## 10. Testing Strategy

### Unit Tests

**Target:** 90%+ line coverage for type system files

| Component | Current Tests | Target Tests |
|-----------|---------------|--------------|
| Type representations | 10 | 30 |
| Type evaluator | 30 | 80 |
| Parameter matching | 13 | 25 |
| Operations | 5 | 20 |
| Type utilities | 5 | 15 |

### Integration Tests

**Add test fixtures for:**
- [ ] Complex generic type scenarios
- [ ] Real-world code patterns
- [ ] Edge cases from bug reports
- [ ] Cross-module type inference
- [ ] Large codebase type checking

### Regression Tests

- [ ] Create snapshot tests for type inference results
- [ ] Add performance regression tests
- [ ] Track error message quality over time

### Compatibility Tests

- [ ] Test against Pyright for Python compatibility
- [ ] Test Jac-specific type features
- [ ] Test TypeScript/JavaScript interop

---

## 11. Success Metrics

### Coverage Metrics

| Metric | Current | Phase 1 Target | Final Target |
|--------|---------|----------------|--------------|
| Expression types covered | 65% | 80% | 95% |
| Test coverage | ~70% | 85% | 95% |
| Known TODOs resolved | 0/31 | 15/31 | 28/31 |

### Quality Metrics

| Metric | Target |
|--------|--------|
| False positive rate | < 1% |
| False negative rate | < 5% |
| Type inference accuracy | > 95% |
| IDE response time | < 100ms |

### User Experience Metrics

| Metric | Target |
|--------|--------|
| Error message clarity | 4.5/5 user rating |
| Type hint accuracy | > 98% |
| Auto-completion relevance | > 90% |

---

## Appendix A: Known TODOs in Codebase

| File | Line | Description | Priority |
|------|------|-------------|----------|
| type_evaluator.impl.jac | 31 | Boolean literals not supported | High |
| type_evaluator.impl.jac | 95 | Null-coalescing operator incomplete | Medium |
| type_evaluator.impl.jac | 106 | Sequence[T] constraint validation | Medium |
| type_evaluator.impl.jac | 194 | Type comparability checking | Medium |
| type_evaluator.impl.jac | 352 | Iterator[T] resolution workaround | High |
| type_evaluator.impl.jac | 412 | Type variance not implemented | High |
| construct_types.impl.jac | 24 | Enum type extraction | Medium |
| construct_types.impl.jac | 46 | Literal string types | High |
| construct_types.impl.jac | 116 | *args/**kwargs parameter category | Medium |
| operations.jac | 60 | Union type `__or__`/`__ror__` checking | Medium |
| parameter_type_check.impl.jac | 72 | TypeVar argument validation | Medium |
| parameter_type_check.impl.jac | 109 | Callable object argument validation | Medium |
| imported.impl.jac | 22 | Module resolution ad-hoc | Medium |
| evaluator_util_methods.impl.jac | 69 | type[x] special case | Medium |

---

## Appendix B: Pyright Reference Mapping

| Pyright Component | Jac Equivalent | Status |
|-------------------|----------------|--------|
| `typeEvaluator.ts` | `type_evaluator.jac` | Partial |
| `types.ts` | `types.jac` | Partial |
| `typeUtils.ts` | `type_utils.jac` | Partial |
| `operations.ts` | `operations.jac` | Partial |
| `checker.ts` | `type_checker_pass.jac` | Partial |
| `binder.ts` | `sym_tab_build_pass.py` | Partial |
| `narrowing.ts` | Not implemented | TODO |
| `protocols.ts` | Inline in `type_utils` | Basic |
| `parameterUtils.ts` | `parameter_type_check.impl.jac` | Partial |

---

## Appendix C: File Modification Summary

### Files Requiring Major Changes
- `jac/jaclang/compiler/type_system/type_evaluator.impl/type_evaluator.impl.jac`
- `jac/jaclang/compiler/type_system/types.jac`
- `jac/jaclang/compiler/type_system/operations.jac`

### Files Requiring Minor Changes
- `jac/jaclang/compiler/type_system/type_utils.jac`
- `jac/jaclang/compiler/type_system/type_evaluator.impl/construct_types.impl.jac`
- `jac/jaclang/compiler/type_system/type_evaluator.impl/parameter_type_check.impl.jac`
- `jac/jaclang/compiler/passes/main/impl/type_checker_pass.impl.jac`

### New Files to Create
- `jac/jaclang/compiler/type_system/type_narrowing.jac` (Phase 3)
- `jac/jaclang/compiler/type_system/variance.jac` (Phase 1)

---

*Document Version: 1.0*
*Created: 2025-12-30*
*Last Updated: 2025-12-30*
