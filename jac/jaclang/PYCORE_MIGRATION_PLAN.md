# PyCore Reorganization Plan

## Goal

Reorganize the jaclang codebase to have a single `pycore` directory containing 100% of bootstrap-critical Python code, while converting everything else to Jac.

## Current State Analysis

**Total Python code (excluding vendor/tests):** ~38,000 lines
**Already in Jac:** ~12,000 lines (runtimelib, langserve, type_system, passes/tool)
**Target pycore:** ~13,000 lines (hand-written) + ~7,000 lines (generated parsers)

---

## Part 1: PyCore Boundary Definition

### MUST Remain in Python (Bootstrap-Critical)

| File | Lines | Reason |
|------|-------|--------|
| `compiler/unitree.py` | 5,500 | Core AST nodes used by ALL passes |
| `compiler/parser.py` | 3,772 | Lark-based parsing (Python library) |
| `compiler/passes/main/pyast_gen_pass.py` | 3,450 | Generates Python AST from Jac |
| `compiler/passes/main/sym_tab_build_pass.py` | 374 | Foundational symbol table |
| `compiler/passes/main/pybc_gen_pass.py` | 49 | Python's compile() builtin |
| `compiler/passes/transform.py` | 178 | Base Transform class |
| `compiler/passes/uni_pass.py` | 138 | UniPass base class |
| `compiler/constant.py` | 777 | Token constants, enums |
| `compiler/codeinfo.py` | 135 | Source location tracking |
| `compiler/__init__.py` | 114 | Parser generation, TOKEN_MAP |
| `compiler/larkparse/*.py` | ~7,000 | Generated Lark parsers |
| `runtimelib/runtime.py` | 2,208 | Plugin loading, JacRuntime |
| `meta_importer.py` | 207 | Python import hook for .jac |
| `__init__.py` | 22 | Package init, meta_path setup |
| **TOTAL** | **~17,900** | |

### CAN Be Converted to Jac

| Category | Files | Lines |
|----------|-------|-------|
| CLI | `cli.py`, `cmdreg.py` | ~1,300 |
| Analysis Passes | 9 passes (lazy-loaded) | ~1,200 |
| **PyastBuildPass** | `pyast_load_pass.py` (py2jac) | 2,604 |
| ECMAScript | `esast_gen_pass.py`, `es_unparse.py`, `estree.py` | ~4,300 |
| Utils | `helpers.py`, `module_resolver.py`, `lang_tools.py`, `log.py`, `treeprinter.py` | ~1,500 |
| TypeScript Parser | `tsparser.py` | 1,780 |
| Other | `settings.py`, `lib.py`, `type_utils.py`, `program.py` (partial) | ~700 |
| **TOTAL** | | **~13,400** |

---

## Part 2: Target Directory Structure

```
jaclang/
  __init__.py                  # KEEP (bootstrap)
  meta_importer.py             # KEEP (bootstrap)
  settings.jac                 # CONVERT
  lib.jac                      # CONVERT

  pycore/                      # NEW - All Python bootstrap code
    __init__.py                # Exports all pycore modules
    ast/
      __init__.py
      unitree.py               # Core AST definitions
      constant.py              # Tokens, symbols, enums
      codeinfo.py              # Code location tracking
    parser/
      __init__.py              # Parser generation utilities
      jac_parser.py            # Main Jac parser
      jac.lark                 # Grammar file
      larkparse/               # Generated parsers
        jac_parser.py
        ts_parser.py
    passes/
      __init__.py
      transform.py             # Base Transform
      uni_pass.py              # UniPass base
      sym_tab_build_pass.py    # Symbol table
      pyast_gen_pass.py        # Python AST gen (Jac→Python, MUST be Python)
      pybc_gen_pass.py         # Bytecode gen
      ast_gen/
        base_ast_gen_pass.py
    runtime/
      __init__.py
      runtime.py               # JacRuntime bootstrap

  compiler/                    # RESTRUCTURED - mostly Jac
    __init__.jac               # NEW Jac package init
    program.jac                # CONVERT (or keep thin Python wrapper)
    tsparser.jac               # CONVERT
    utils.jac                  # CONVERT compiler utils
    passes/
      main/
        __init__.jac           # Re-export pycore passes + Jac passes
        pyast_load_pass.jac    # CONVERT - Python→Jac AST (py2jac), NOT bootstrap-critical!
        def_impl_match_pass.jac
        semantic_analysis_pass.jac
        sem_def_match_pass.jac
        cfg_build_pass.jac
        def_use_pass.jac
        pyjac_ast_link_pass.jac
        type_checker_pass.jac
        annex_pass.jac
        import_pass.jac
      ecmascript/
        __init__.jac
        esast_gen_pass.jac
        es_unparse.jac
        estree.jac
      tool/                    # ALREADY JAC - unchanged
        ...
    type_system/               # ALREADY MOSTLY JAC - unchanged
      ...
      type_utils.jac           # CONVERT

  cli/                         # CONVERT
    __init__.jac
    cli.jac
    cmdreg.jac

  utils/                       # CONVERT
    __init__.jac
    helpers.jac
    module_resolver.jac
    lang_tools.jac
    log.jac
    treeprinter.jac

  runtimelib/                  # ALREADY MOSTLY JAC - unchanged
  langserve/                   # ALREADY JAC - unchanged
  vendor/                      # KEEP - third-party Python
```

---

## Part 3: Migration Phases

### Phase 1: Create PyCore Infrastructure

**Estimated files:** 15 | **Risk:** Low

1. Create `jaclang/pycore/` directory structure
2. Move bootstrap Python files to pycore (preserve imports via shims)
3. Update import statements throughout codebase
4. Create compatibility shims in old locations:

   ```python
   # jaclang/compiler/unitree.py (becomes shim)
   from jaclang.pycore.ast.unitree import *
   ```

**Files to move:**

- `compiler/unitree.py` -> `pycore/ast/unitree.py`
- `compiler/constant.py` -> `pycore/ast/constant.py`
- `compiler/codeinfo.py` -> `pycore/ast/codeinfo.py`
- `compiler/parser.py` -> `pycore/parser/jac_parser.py`
- `compiler/__init__.py` -> `pycore/parser/__init__.py`
- `compiler/jac.lark` -> `pycore/parser/jac.lark`
- `compiler/larkparse/` -> `pycore/parser/larkparse/`
- `compiler/passes/transform.py` -> `pycore/passes/transform.py`
- `compiler/passes/uni_pass.py` -> `pycore/passes/uni_pass.py`
- `compiler/passes/main/sym_tab_build_pass.py` -> `pycore/passes/sym_tab_build_pass.py`
- `compiler/passes/main/pyast_gen_pass.py` -> `pycore/passes/pyast_gen_pass.py`
- `compiler/passes/main/pybc_gen_pass.py` -> `pycore/passes/pybc_gen_pass.py`
- `compiler/passes/ast_gen/` -> `pycore/passes/ast_gen/`
- `runtimelib/runtime.py` -> `pycore/runtime/runtime.py`

**NOTE:** `pyast_load_pass.jac` is now in `compiler/passes/main/` - fully converted to Jac!

### Phase 2: Convert Small/Simple Passes (Already Lazy-Loaded)

**Estimated files:** 10 | **Risk:** Low

Convert passes in order of complexity (smallest first):

1. `sem_def_match_pass.py` (68 lines) - **FULLY CONVERTED** (.py deleted)
2. `annex_pass.py` (95 lines) - MUST STAY PYTHON (bootstrap-critical)
3. `semantic_analysis_pass.py` (119 lines) - MUST STAY PYTHON (bootstrap-critical)
4. `def_use_pass.py` (122 lines) - **FULLY CONVERTED** (.py deleted)
5. `pyjac_ast_link_pass.py` (134 lines) - **FULLY CONVERTED** (.py deleted)
6. `import_pass.py` (131 lines) - **FULLY CONVERTED** (.py deleted)
7. `type_checker_pass.py` (148 lines) - **FULLY CONVERTED** (.py deleted)
8. `def_impl_match_pass.py` (175 lines) - MUST STAY PYTHON (bootstrap-critical)
9. `cfg_build_pass.py` (323 lines) - **FULLY CONVERTED** (.py deleted)
10. `pyast_load_pass.py` (2,604 lines) - **FULLY CONVERTED** (.py deleted) - py2jac itself!

**CURRENT STATUS:** 7 passes fully converted to .jac - Python versions DELETED!
The meta_importer compiles these .jac files using minimal compilation schedule.

**Bootstrap Strategy:** The minimal compilation schedule (`get_minimal_ir_gen_sched()`) only needs:

- `SymTabBuildPass` (in pycore, Python)
- `DeclImplMatchPass` (Python)
- `SemanticAnalysisPass` (Python)

All other passes can be .jac files! When they're imported, the meta_importer compiles them
using minimal compilation (which doesn't need the passes being compiled). This breaks the
circular dependency and allows full Jac conversion.

**1203 tests pass with .jac-only passes!**

**Conversion process for each:**

```bash
jac py2jac compiler/passes/main/<pass>.py > compiler/passes/main/<pass>.jac
# Manual review and fixup
# Update __init__.py lazy loading to use .jac
# Run tests
```

### Phase 3: Convert Utilities

**Estimated files:** 7 | **Risk:** Low-Medium

1. `settings.py` (115 lines) - simple config
2. `lib.py` (149 lines) - lazy exports
3. `utils/log.py` (11 lines) - trivial
4. `utils/helpers.py` (378 lines) - utility functions
5. `utils/lang_tools.py` (198 lines)
6. `utils/module_resolver.py` (268 lines)
7. `utils/treeprinter.py` (664 lines)

### Phase 4: Convert CLI

**Estimated files:** 2 | **Risk:** Medium

1. `cli/cmdreg.py` (409 lines) - command registration
2. `cli/cli.py` (905 lines) - main CLI commands

**Note:** CLI has heavy use of argparse and click patterns. May need careful py2jac review.

### Phase 5: Convert Type System Utilities

**Estimated files:** 1 | **Risk:** Low

1. `type_system/type_utils.py` (304 lines)

### Phase 6: Convert ECMAScript Generation (Optional)

**Estimated files:** 3 | **Risk:** Medium-High

1. `passes/ecmascript/estree.py` (970 lines) - AST definitions
2. `passes/ecmascript/es_unparse.py` (590 lines) - code gen
3. `passes/ecmascript/esast_gen_pass.py` (2717 lines) - pass

**Note:** These are larger files. May want to keep in Python if JS target isn't critical.

### Phase 7: Convert TypeScript Parser (Optional)

**Estimated files:** 1 | **Risk:** Medium

1. `tsparser.py` (1780 lines)

---

## Part 4: Critical Files to Modify

### Must Update Import Paths

- `jaclang/__init__.py` - update to use pycore
- `jaclang/meta_importer.py` - update pass imports
- `jaclang/compiler/program.py` - update schedule imports
- `jaclang/compiler/passes/main/__init__.py` - major restructure

### Key Integration Points

- `meta_importer.py:73-80` - MINIMAL_COMPILE_MODULES list
- `program.py:70-87` - get_minimal_ir_gen_sched() and get_minimal_py_code_gen()
- `passes/main/__init__.py:12-17` - bootstrap-critical pass imports
- `passes/main/__init__.py:21-31` - _LAZY_PASSES dict for Jac conversion

---

## Part 5: Validation Strategy

### Per-File Testing

1. Run `jac py2jac <file>` and review output
2. Make manual adjustments for Jac idioms
3. Run existing unit tests for that module
4. Run integration tests

### Regression Testing

1. Full test suite after each phase
2. Bootstrap test: compile a fresh Jac file
3. Self-hosting test: jaclang compiles jaclang

### Rollback Plan

- Keep Python files alongside Jac during transition
- Use feature flag in settings to toggle implementations
- CI runs both Python and Jac versions until stable

---

## Part 6: Estimated Impact

### Before

- Python: 38,000 lines (excluding vendor)
- Jac: 12,000 lines

### After (Target)

- Python (pycore): ~10,900 lines hand-written + 7,000 generated (~17,900 total)
- Jac: ~28,000 lines

### Reduction

- ~20,000 lines of Python converted to Jac (including pyast_load_pass!)
- pycore is ~29% of original Python codebase (down from 100%)

---

## Part 7: Implementation Order Summary

| Phase | Description | Files | Lines | Risk | Priority |
|-------|-------------|-------|-------|------|----------|
| 1 | Create pycore structure | 15 | - | Low | High |
| 2 | Convert lazy-loaded passes (incl. pyast_load_pass!) | 10 | ~3,800 | Low-Med | High |
| 3 | Convert utilities | 7 | ~1,500 | Low-Med | Medium |
| 4 | Convert CLI | 2 | ~1,300 | Medium | Medium |
| 5 | Convert type utils | 1 | ~300 | Low | Medium |
| 6 | Convert ECMAScript | 3 | ~4,300 | Med-High | Low |
| 7 | Convert TS parser | 1 | ~1,800 | Medium | Low |

**Key insight:** `pyast_load_pass.py` (2,604 lines) is NOT bootstrap-critical! It converts Python→Jac (py2jac), which is only needed after bootstrap is complete.

Start with Phase 1 (infrastructure) then Phase 2 (passes) as they're low-risk and high-impact.
