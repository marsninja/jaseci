# PyCore Reorganization Plan

## Goal

Reorganize the jaclang codebase to have a single `pycore` directory containing 100% of bootstrap-critical Python code, while converting everything else to Jac with help of jac's `py2jac` command.

## Current State Analysis

**Snapshot (this repo checkout):**

- **Python (excluding `jaclang/vendor/` + `__pycache__/`):** ~54k lines
- **Jac (excluding `jaclang/vendor/` + `__pycache__/`):** ~17k lines
- **PyCore Python total:** ~41.7k lines
  - **Hand-written pycore:** ~21.1k lines
  - **Generated parsers (`pycore/parser/larkparse/*.py`):** ~6.9k lines
  - **Extra generated backups currently checked in (`pycore/parser/larkparse/larkparse.bak/**`):** ~13.8k lines (cleanup candidate)

**Major milestone already achieved:** `jaclang/pycore/` exists and is the canonical home of the bootstrap-critical compiler + runtime Python.

---

## Part 1: PyCore Boundary Definition

### MUST Remain in Python (Bootstrap-Critical)

| File | Lines | Reason |
|------|-------|--------|
| `pycore/ast/unitree.py` | ~ | Core AST nodes used by ALL passes |
| `pycore/ast/constant.py` | ~ | Token constants, enums |
| `pycore/ast/codeinfo.py` | ~ | Source location tracking |
| `pycore/parser/jac_parser.py` | ~ | Lark-based parsing (Python library) |
| `pycore/parser/jac.lark` | ~ | Grammar file |
| `pycore/parser/larkparse/*.py` | ~6.9k | Generated Lark parsers (checked-in) |
| `pycore/parser/tsparser.py` | ~ | TypeScript/JS parser wrapper (Lark) |
| `pycore/passes/transform.py` | ~ | Base Transform class |
| `pycore/passes/uni_pass.py` | ~ | UniPass base class |
| `pycore/passes/sym_tab_build_pass.py` | ~ | Foundational symbol table |
| `pycore/passes/sym_tab_link_pass.py` | ~ | Cross-module symtab linking |
| `pycore/passes/semantic_analysis_pass.py` | ~ | Bootstrap semantic analysis |
| `pycore/passes/def_impl_match_pass.py` | ~ | Decl/impl matching |
| `pycore/passes/annex_pass.py` | ~ | Annex/module loading during compile |
| `pycore/passes/pyast_gen_pass.py` | ~ | Generates Python AST from Jac |
| `pycore/passes/pybc_gen_pass.py` | ~ | Python bytecode emission |
| `pycore/passes/ast_gen/*.py` | ~ | Shared AST-gen utilities |
| `pycore/program.py` | ~ | Compilation schedules + program state |
| `pycore/runtime/runtime.py` | ~ | Plugin loading, JacRuntime bootstrap |
| `pycore/settings.py` | ~ | Settings used by bootstrap code |
| `meta_importer.py` | ~ | Python import hook for `.jac` |
| `__init__.py` | ~ | Package init, meta_path setup |
| **TOTAL** | **(see snapshot above)** | |

### CAN Be Converted to Jac

| Category | Files | Lines |
|----------|-------|-------|
| CLI | `cli/cli.jac`, `cli/cmdreg.jac` | **DONE** |
| Analysis Passes | `compiler/passes/main/*.jac` | **DONE** (most) |
| **PyastBuildPass** | `compiler/passes/main/pyast_load_pass.jac` | **DONE** |
| Type System Utils | `compiler/type_system/type_utils.py` | **NOT DONE** |
| ECMAScript | `compiler/passes/ecmascript/*.py` | **NOT DONE** (optional) |
| TypeScript Parser | `pycore/parser/tsparser.py` | **KEPT PYTHON** (optional conversion) |
| Misc / UX | `utils/lang_tools.py`, `lib.py` | **NOT DONE / optional** |
| **TOTAL** | | **~13,400** |

---

## Part 2: Directory Structure (Current)

```
jaclang/
  __init__.py
  __main__.py
  meta_importer.py
  lib.py

  pycore/                      # Canonical bootstrap Python
    ast/                       # unitree/constant/codeinfo
    parser/                    # jac_parser + checked-in larkparse/
    passes/                    # bootstrap-critical passes
    runtime/                   # JacRuntime bootstrap
    program.py                 # schedules + program state
    settings.py                # settings used by bootstrap
    utils/                     # bootstrap utilities

  compiler/                    # Thin Python shim + mixed Jac/Python
    __init__.py                # ensures parsers exist; re-exports TOKEN_MAP/jac_lark
    ts.lark
    passes/
      main/
        __init__.py            # eager pycore passes + lazy `.jac` passes
        *.jac                  # converted passes (cfg_build, type_checker, etc.)
      ecmascript/              # still Python (optional conversion)
        *.py
      tool/                    # already Jac
        *.jac
    type_system/
      type_utils.py            # still Python (planned conversion)
      *.jac

  cli/                         # Converted to Jac (imported via meta_importer)
    __init__.py
    cli.jac
    cmdreg.jac

  runtimelib/                  # Mostly Jac; runtime.py is a shim
    runtime.py
    *.jac

  utils/                       # Mixed; lang_tools.py still Python
    lang_tools.py
    *.jac

  vendor/                      # Third-party Python (vendored)
```

---

## Part 3: Migration Phases

### Phase 1: Create PyCore Infrastructure

**Estimated files:** 15 | **Risk:** Low

1. Create `jaclang/pycore/` directory structure
2. Move bootstrap Python files to pycore (preserve imports via shims)
3. Update import statements throughout codebase

**Files to move:**

- `compiler/unitree.py` -> `pycore/ast/unitree.py` (**DONE**)
- `compiler/constant.py` -> `pycore/ast/constant.py` (**DONE**)
- `compiler/codeinfo.py` -> `pycore/ast/codeinfo.py` (**DONE**)
- `compiler/parser.py` -> `pycore/parser/jac_parser.py` (**DONE**)
- `compiler/jac.lark` -> `pycore/parser/jac.lark` (**DONE**)
- `compiler/larkparse/` -> `pycore/parser/larkparse/` (**DONE**, but see `larkparse.bak/` cleanup below)
- `compiler/passes/transform.py` -> `pycore/passes/transform.py` (**DONE**)
- `compiler/passes/uni_pass.py` -> `pycore/passes/uni_pass.py` (**DONE**)
- `compiler/passes/main/sym_tab_build_pass.py` -> `pycore/passes/sym_tab_build_pass.py` (**DONE**)
- `compiler/passes/main/pyast_gen_pass.py` -> `pycore/passes/pyast_gen_pass.py` (**DONE**)
- `compiler/passes/main/pybc_gen_pass.py` -> `pycore/passes/pybc_gen_pass.py` (**DONE**)
- `compiler/passes/ast_gen/` -> `pycore/passes/ast_gen/` (**DONE**)
- `runtimelib/runtime.py` -> `pycore/runtime/runtime.py` (**DONE**)

**Additional pycore moves/ownership changes beyond the original list:**

- `JacProgram` now lives in `jaclang/pycore/program.py` (compilation schedules + program state).
- `compiler/__init__.py` is now a thin Python shim responsible for generating/checking the checked-in parsers under `pycore/parser/larkparse/` and re-exporting `TOKEN_MAP` / `jac_lark` from `pycore/parser`.

**NOTE:** `pyast_load_pass.py` can be converted

### Phase 2: Convert Small/Simple Passes (Already Lazy-Loaded)

**Estimated files:** 10 | **Risk:** Low

Convert passes in order of complexity (smallest first):

1. `compiler/passes/main/sem_def_match_pass.jac` - **DONE** (Python deleted)
2. `pycore/passes/annex_pass.py` - **KEPT PYTHON** (bootstrap-critical)
3. `pycore/passes/semantic_analysis_pass.py` - **KEPT PYTHON** (bootstrap-critical)
4. `compiler/passes/main/def_use_pass.jac` - **DONE** (Python deleted)
5. `compiler/passes/main/pyjac_ast_link_pass.jac` - **DONE** (Python deleted)
6. `compiler/passes/main/import_pass.jac` - **DONE** (Python deleted)
7. `compiler/passes/main/type_checker_pass.jac` - **DONE** (Python deleted)
8. `pycore/passes/def_impl_match_pass.py` - **KEPT PYTHON** (bootstrap-critical)
9. `compiler/passes/main/cfg_build_pass.jac` - **DONE** (Python deleted)
10. `compiler/passes/main/pyast_load_pass.jac` - **DONE** (Python deleted)

**CURRENT STATUS:** 7 passes are now `.jac` in `jaclang/compiler/passes/main/` with Python versions deleted.
`jaclang/compiler/passes/main/__init__.py` provides eager Python imports from pycore for bootstrap-critical passes and lazy loading for `.jac` passes.

**Bootstrap Strategy:** The minimal compilation schedule (`get_minimal_ir_gen_sched()`) only needs:

- `SymTabBuildPass` (in pycore, Python)
- `DeclImplMatchPass` (Python)
- `SemanticAnalysisPass` (Python)

All other passes can be .jac files! When they're imported, the meta_importer compiles them
using minimal compilation (which doesn't need the passes being compiled). This breaks the
circular dependency and allows full Jac conversion.

**Note:** use the repo’s dev environment at `~/.fresh/` (has `pip`, `pytest`, and `jac`); see validation commands below.

**Conversion process for each:**

```bash
jac py2jac compiler/passes/main/<pass>.py > compiler/passes/main/<pass>.jac
# Manual review and fixup
# Update __init__.py lazy loading to use .jac
# Run tests
```

### Phase 3: Convert Utilities

**Estimated files:** 7 | **Risk:** Low-Medium | **STATUS: PARTIALLY DONE / RE-SCOPED**

1. `settings.py` (115 lines) - simple config
2. `lib.py` (149 lines) - lazy exports
3. `utils/log.py` (11 lines) - trivial
4. `utils/helpers.py` (378 lines) - utility functions
5. `utils/lang_tools.py` (198 lines)
6. `utils/module_resolver.py` (268 lines)
7. `utils/treeprinter.py` (664 lines)

**Current reality:**

- `helpers.py`, `log.py`, `module_resolver.py`, `treeprinter.py`, `settings.py` are now in `jaclang/pycore/` and remain Python (bootstrap-critical dependencies).
- `jaclang/utils/lang_tools.py` is still Python (non-pycore) and can be converted later if desired.
- `jaclang/lib.py` is still Python and acts as a user-facing compatibility facade.

### Phase 4: Convert CLI

**Estimated files:** 2 | **Risk:** Medium | **STATUS: COMPLETE**

1. `cli/cmdreg.py` (409 lines) - **FULLY CONVERTED** (.py deleted, now cmdreg.jac ~339 lines)
2. `cli/cli.py` (905 lines) - **FULLY CONVERTED** (.py deleted, now cli.jac ~694 lines)

**Note:** CLI conversion required adding `get_code()` method to JacMetaImporter for `python -m` support.

### Phase 5: Convert Type System Utilities

**Estimated files:** 1 | **Risk:** Low

1. `compiler/type_system/type_utils.py` (still Python) - **STATUS: NOT DONE**

### Phase 6: Convert ECMAScript Generation (Optional)

**Estimated files:** 3 | **Risk:** Medium-High

1. `compiler/passes/ecmascript/estree.py` (still Python) - AST definitions
2. `compiler/passes/ecmascript/es_unparse.py` (still Python) - code gen
3. `compiler/passes/ecmascript/esast_gen_pass.py` (still Python) - pass

**Note:** These are larger files. May want to keep in Python if JS target isn't critical.

### Phase 7: Convert TypeScript Parser (Optional)

**Estimated files:** 1 | **Risk:** Medium

**Current reality:** TypeScript parsing is implemented in Python at `pycore/parser/tsparser.py`, backed by `compiler/ts.lark` and generated `pycore/parser/larkparse/ts_parser.py`.

Conversion to Jac is optional; the current setup works and keeps the Lark dependency entirely in pycore.

---

## Part 4: Critical Files to Modify

### Must Update Import Paths

- `jaclang/__init__.py` - update to use pycore
- `jaclang/meta_importer.py` - update pass imports
- `jaclang/pycore/program.py` - update schedule imports (now canonical)
- `jaclang/compiler/passes/main/__init__.py` - major restructure

### Key Integration Points

- `meta_importer.py:73-80` - MINIMAL_COMPILE_MODULES list
- `pycore/program.py:68-96` - get_minimal_ir_gen_sched() and get_minimal_py_code_gen()
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

**Dev setup note:** use the `~/.fresh/` environment:

```bash
source ~/.fresh/bin/activate
python -m pip install -e jac[dev]  # if needed
python -m pytest
```

If you prefer not to activate the venv, use `~/.fresh/bin/python -m pytest`.

### Rollback Plan

- Keep Python files alongside Jac during transition
- Use feature flag in settings to toggle implementations
- CI runs both Python and Jac versions until stable

---

## Part 6: Estimated Impact

### Baseline (Current Snapshot)

- Python (excluding `jaclang/vendor/`): ~54k lines
- Jac (excluding `jaclang/vendor/`): ~17k lines
- Pycore hand-written Python (excluding checked-in generated parsers): ~21k lines

### Target (Still Reasonable)

- Keep pycore as the only bootstrap-critical Python surface area
- Continue converting non-bootstrap Python to Jac as it becomes practical (type utils, optional ECMAScript)

---

## Part 7: Implementation Order Summary

| Phase | Description | Risk | Priority | Status |
|-------|-------------|------|----------|--------|
| 1 | Create pycore structure | Low | High | **DONE** |
| 2 | Convert lazy-loaded passes (incl. pyast_load_pass) | Low-Med | High | **DONE** (7 passes) |
| 3 | Convert utilities | Low-Med | Medium | **PARTIAL** (moved into pycore; conversion deferred) |
| 4 | Convert CLI | Medium | Medium | **DONE** |
| 5 | Convert type utils | Low | Medium | **NOT DONE** |
| 6 | Convert ECMAScript | Med-High | Low | **NOT DONE / optional** |
| 7 | Convert TS parser | Medium | Low | **DEFERRED** (kept Python in pycore) |

**Key insight:** `pyast_load_pass.py` (2,604 lines) is NOT bootstrap-critical! It converts Python→Jac (py2jac), which is only needed after bootstrap is complete.

Start with Phase 1 (infrastructure) then Phase 2 (passes) as they're low-risk and high-impact.

---

## Part 8: Cleanup / Follow-ups (Discovered)

These items were not in the original plan, but are worth tracking based on current repo state:

1. **Remove generated parser backups:** `jaclang/pycore/parser/larkparse/larkparse.bak/` appears to contain nested/duplicated generated output; it inflates pycore significantly and is likely accidental.
2. **Reconcile legacy generated parsers:** `jaclang/compiler/larkparse/` still exists but appears unused (imports reference `jaclang.pycore.parser.larkparse`); confirm and remove/deprecate.
3. **Tighten `MINIMAL_COMPILE_MODULES`:** `jaclang/meta_importer.py` still lists module names that no longer exist as `.jac` modules (e.g., passes that moved into `pycore/passes/*.py`); pruning reduces confusion and avoids dead entries.
4. **Decide ownership of `ts.lark`:** currently in `jaclang/compiler/ts.lark` while the generated parser lives under pycore; consider moving grammar to `pycore/parser/` for consistency.
