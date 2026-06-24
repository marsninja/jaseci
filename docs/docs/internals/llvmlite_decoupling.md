# Decoupling `na` from the Python `llvmlite` Dependency

> **Status:** Validation + RFC for [issue #6925](https://github.com/jaseci-labs/jaseci/issues/6925).
> This document records what was *verified against the tree* before any code
> was written, corrects two material scope errors in the issue, and lays out a
> realistic, phased plan. It does **not** itself change runtime behaviour.

## Overview

The single `jac` binary bundles a ~160 MB `libllvmlite.so` and drives native
(`na`) JIT compilation through the Python **`llvmlite`** package. Issue #6925
proposes to drop that runtime dependency by (1) statically linking a curated,
host-only LLVM into the binary and (2) reimplementing the binding layer in pure
Jac against LLVM's stable C API (`llvm-c`), keeping `llvmlite` as reference
only.

The *direction* is sound and the JIT/codegen binding surface is small. But the
issue as written under-scopes the work by roughly an order of magnitude and
contains one feasibility blocker it does not acknowledge. This document is the
validation pass that surfaces both, so the implementation can be planned
against reality rather than against the issue's optimistic framing.

This is an **internals** document; it assumes the codespace model from
[Compiler Architecture](compiler_architecture.md) and the boundary model from
[Cross-Codespace Interop](interop.md).

## TL;DR -- verdict

| # | Claim in the issue | Verdict |
|---|---|---|
| 1 | `llvmlite>=0.47.0` pinned in `jac/jac.toml`; native pass imports `llvmlite.binding`; one `add_symbol` touchpoint in `interop_bridge.jac` | **Accurate** |
| 2 | The `llvmlite.binding` surface `na` uses is a small subset that maps ~1:1 onto LLVM-C | **Accurate** (full inventory below) |
| 3 | `libllvmlite.so` has zero CPython coupling (ctypes `CDLL`), ~160 MB, LLVM linked inside | **Accurate** |
| 4 | "Bind LLVM-C directly" / "skip llvmlite's shim entirely" against the shipped artifact | **Blocked** -- the shipped `.so` exports **0** raw `LLVM*` symbols (only 312 `LLVMPY_*`). A *new* LLVM build with `llvm-c` symbols exported is mandatory, not optional. |
| 5 | Definition of done = "binding reimplemented (~30 fns), `llvmlite` gone, `na` suite green" | **Materially incomplete** -- the issue never mentions **`llvmlite.ir`**, a large pure-Python IR *builder* used ~5,000 times across the native passes. Removing the *package* requires reimplementing it too. |
| 6 | `mkpayload.sh` pip-installs the wheel | **Minor inaccuracy** -- the dependency flows through `jac/jac.toml` `dependencies`, not a line in `mkpayload.sh`. |

**Bottom line:** #6925's "~30 functions / `na` suite green" framing describes only
the `llvmlite.binding` swap. The package cannot leave `jac.toml` until
`llvmlite.ir` is also replaced, and the LLVM-C path cannot start until a custom
LLVM is built. The true effort is a multi-PR program, not a single change.

## What is true today

### Two distinct `llvmlite` layers are in use, not one

The issue frames the work around `llvmlite.binding` (the ctypes marshalling
layer over the native shim). The tree actually depends on **two** independent
`llvmlite` sub-packages:

1. **`llvmlite.binding`** -- ctypes wrappers over the `LLVMPY_*` C ABI exported
   by `libllvmlite.so`. Drives parse / verify / optimize / JIT / emit. This is
   the layer the issue describes.
2. **`llvmlite.ir`** -- a **pure-Python LLVM-IR builder** (`ir.Module`,
   `ir.IRBuilder`, the type and constant constructors). It emits *textual* IR
   which is then handed to `binding.parse_assembly`. The issue does not mention
   it at all.

Both must go for the package pin to leave `jac/jac.toml`.

### `llvmlite.binding` -- full consumer + API inventory

Consumers (not just `na_compile_pass`):

| File | Uses |
|---|---|
| `compiler/passes/native/impl/na_compile_pass.impl.jac` | the bulk: parse, verify, init, target machine, new-PM optimize, MCJIT, emit, bitcode, dynamic symbols, linkage surgery |
| `compiler/passes/native/wasm_build.jac` | `initialize_all_*`, `parse_assembly`, `Target`, `create_pipeline_tuning_options`, `create_pass_builder` |
| `jac0core/interop_bridge.jac` | the single `add_symbol(name, addr)` interop touchpoint |
| `jac0core/codeinfo.jac` | `import type` of `ModuleRef`, `ExecutionEngine` (carried on codegen state) |

API surface, mapped to LLVM-C and to the already-exported `LLVMPY_*`:

| `llvmlite.binding` call | LLVM-C | `LLVMPY_*` exported today? |
|---|---|---|
| `parse_assembly` | `LLVMParseIRInContext` | ✅ |
| `Module.verify` | `LLVMVerifyModule` | ✅ |
| `Target.from_triple` / `from_default_triple` | `LLVMGetTargetFromTriple` / `LLVMGetDefaultTargetTriple` | ✅ |
| `create_target_machine(opt, jit)` | `LLVMCreateTargetMachine` | ✅ |
| `create_pipeline_tuning_options` / `create_pass_builder` / `ModulePassManager.run` | `LLVMCreatePassBuilderOptions` + `LLVMRunPasses` | ✅ |
| `create_mcjit_compiler` | `LLVMCreateMCJITCompilerForModule` | ✅ |
| `ExecutionEngine.get_function_address` | `LLVMGetFunctionAddress` | ✅ |
| `TargetMachine.emit_object` | `LLVMTargetMachineEmitToMemoryBuffer` | ✅ |
| `Module.as_bitcode` | `LLVMWriteBitcodeToMemoryBuffer` | ✅ |
| `load_library_permanently` | `LLVMLoadLibraryPermanently` | ✅ |
| `add_symbol(name, addr)` | `LLVMAddSymbol` | ✅ |
| `Module.link_in` (na↔na) | `LLVMLinkModules2` | ✅ |
| get/set `linkage` (link-time surgery) | `LLVMGet/SetLinkage` | ✅ |
| `initialize_native_*` / `initialize_all_*` | `LLVMInitializeNative{Target,AsmPrinter}` / `LLVMInitializeAll*` | ✅ |
| `ExecutionEngine.enable_jit_events` | **no clean MCJIT path in `llvm-c`** | ✅ (`LLVMPY_*` exposes it) |

This is ~30 entry points -- bounded, but detail-sensitive (opaque handles,
out-param error strings, `LLVMDisposeMessage` / `LLVMDisposeMemoryBuffer`
lifetimes, reading bytes out of an `LLVMMemoryBuffer`). The issue's risk call --
"lifetime/dispose bugs are the likely failure mode" -- is correct.

Note the `enable_jit_events` row: it is used (live GDB/JIT registration in
`na_compile_pass.impl.jac`). The `LLVMPY_*` ABI exposes it; `llvm-c` does not
cleanly for MCJIT, so the LLVM-C path needs the issue's documented fallback (a
small C shim) and the `LLVMPY_*` path does not.

### `llvmlite.ir` -- the omitted elephant

The pure-Python IR builder is used pervasively across the native passes
(`na_ir_gen_pass` and its impl tree, `compiler/targets/abi.jac`,
`primitives_native.jac`, `type_evaluator.impl/imported.impl.jac`,
`jac0core/impl/unitree.impl.jac`). Approximate call counts:

| Constructor | Uses |
|---|---|
| `ir.Value` | ~1,886 |
| `ir.Constant` | ~1,726 |
| `ir.IntType` | ~1,040 |
| `ir.PointerType` | ~220 |
| `ir.IRBuilder` | ~187 |
| `ir.Function` | ~183 |
| `ir.Type` / `ir.FunctionType` / `ir.*StructType` / globals / blocks / FP types | ~600 combined |

Reimplementing this is a far larger and riskier effort than the binding swap:
it is a full IR-emission layer (type system, constant folding/printing,
instruction formatting). It can be done two ways -- a pure-Jac textual-IR
emitter (matches today's "build text, then `parse_assembly`" flow) or building
IR through LLVM-C's `IRBuilder` directly -- but either is its own multi-PR
project. **No acceptance criterion in #6925 covers it, yet criterion "remove
`llvmlite` from `jac.toml`" cannot pass without it.**

### What survives untouched

The object-file linkers (`elf_linker`, `macho_linker`, `pe_linker`,
`wasm_linker`) consume the **bytes** returned by `emit_object()`; they have no
`llvmlite` coupling beyond receiving that buffer. They are unaffected by any
binding swap. The interop marshalling in `interop_bridge.jac` is already
`llvmlite`-independent (pure ctypes `CFUNCTYPE`/`cast`/`py_func_table`); it
touches LLVM at exactly one line, so re-routing that single `add_symbol`
carries the whole interop layer across -- the issue is right about this.

### Symbol-export reality (the blocker)

Measured on the shipped artifact:

```
$ nm -D --defined-only .../llvmlite/binding/libllvmlite.so
  LLVMPY_*  exported : 312
  raw LLVM* exported : 0
```

LLVM is statically linked *inside* `libllvmlite.so` but its `llvm-c` symbols are
**hidden** -- llvmlite's CMake exports only its own `LLVMPY_*` shim. Consequences:

- **You cannot bind `llvm-c` against the current `.so`.** The symbols are not in
  the process image to resolve via `RTLD_DEFAULT`. Issue criterion #1 (a curated
  build that *exports* `llvm-c`) is therefore load-bearing for the LLVM-C plan,
  not a "nice to have."
- **You *can* bind the 312 `LLVMPY_*` symbols today**, with no new build. That is
  the cheapest way to delete the *Python* `binding` package while reusing the
  shipped native shim -- at the cost of not reducing binary size and not removing
  the `.so`.

## Two viable bindings -- pick deliberately

| | **A. Bind `LLVMPY_*` (reuse shipped `.so`)** | **B. Bind `llvm-c` (issue's target)** |
|---|---|---|
| New LLVM build required | No | **Yes** (host-only MCJIT, `llvm-c` exported, into `build.zig` as a dedicated native unit) |
| Removes Python `binding` marshalling | Yes | Yes |
| Removes `libllvmlite.so` / shrinks binary | **No** | Yes (the issue's 167 MB → tens-of-MB goal) |
| `enable_jit_events` | Works (shim exposes it) | Needs ~20-line C shim |
| Drops `llvmlite` from `jac.toml` | **No** (still need the `.so` + `llvmlite.ir`) | Only after `llvmlite.ir` is also replaced |
| Effort | Lower; no toolchain work | Higher; LLVM build + packaging on 4 platforms |

Neither option alone closes #6925, because both still leave `llvmlite.ir` in
place. Option A is the natural *first* increment (proves the marshalling
contract in pure Jac with zero build-system risk); Option B is required to hit
the size goal; the `ir` reimplementation is required to drop the package. They
are independent and can land in that order.

## Corrected phased plan

Each phase is independently shippable and independently verifiable against the
existing `na` suite (`jac/tests/compiler/passes/native/` plus the
`na_py_interop*` interop fixtures, which already exercise `na`↔`sv`, `na`↔py,
and `na`↔`na`).

1. **P0 -- Pure-Jac binding over `LLVMPY_*`, behind a flag.** Reimplement the
   `llvmlite.binding` surface (the ~30 entry points above) in Jac via ctypes
   against the already-exported `LLVMPY_*` ABI. Run *parallel* to the existing
   path; default unchanged. Re-route `interop_bridge.jac`'s single `add_symbol`.
   Removes the Python `binding` marshalling dependency with no build-system risk.
   *Gate:* parity harness -- same modules, both paths, identical JIT behaviour and
   byte-identical `emit_object`/`as_bitcode`.
2. **P1 -- Flip default to the Jac binding; delete `import llvmlite.binding`** from
   `na_compile_pass`, `wasm_build`, and the `codeinfo` type imports. `llvmlite`
   stays pinned (still needed for `.ir` + the `.so`).
3. **P2 -- Curated host-only MCJIT LLVM**, `llvm-c` symbols exported, statically
   linked into the `jac` binary as a dedicated native unit (launcher stub
   unchanged), wired through `build.zig`/`mkpayload.sh`. Re-point the P0 binding
   from `LLVMPY_*` to `llvm-c`; add the `enable_jit_events` shim. *Gate:* `na`
   suite green on the new artifact + size comparison vs the 160 MB `.so`.
4. **P3 -- Replace `llvmlite.ir`** with a pure-Jac IR emitter (or LLVM-C
   `IRBuilder` path) across `na_ir_gen_pass`, `abi`, `primitives_native`, and the
   type-evaluator. *Gate:* byte-identical IR for the suite, then the package pin
   leaves `jac/jac.toml` and `llvmlite` is gone from the payload.

Acceptance criteria from #6925 map onto these phases; the only new requirement
this validation adds is **P3**, without which "remove `llvmlite`" is unreachable.

## Risks

- **Marshalling lifetimes** (both binding options): disposing C-allocated
  messages/memory buffers, opaque-handle ownership, out-param error strings.
  This is where subtle JIT corruption hides; the parity harness is the guardrail.
- **`enable_jit_events` on `llvm-c`** (Option B only): no clean MCJIT path --
  budget the C shim early or accept losing live GDB JIT registration.
- **`llvmlite.ir` scope (P3):** by call volume this is the dominant cost and the
  issue's effort estimate excludes it. Treat it as its own project.
- **LLVM build packaging (P2):** host-only MCJIT across all four shipped
  platforms; symbol-visibility must keep `llvm-c` exported (the exact thing
  llvmlite's CMake hides).

## References

- `jac/jaclang/compiler/passes/native/na_compile_pass.jac`, `.../impl/na_compile_pass.impl.jac` -- current binding usage
- `jac/jaclang/compiler/passes/native/wasm_build.jac` -- second binding consumer
- `jac/jaclang/compiler/passes/native/na_ir_gen_pass*`, `compiler/targets/abi.jac`, `primitives_native.jac` -- `llvmlite.ir` consumers (P3 surface)
- `jac/jaclang/jac0core/interop_bridge.jac` -- single `add_symbol` LLVM touchpoint
- `jac/jaclang/jac0core/codeinfo.jac` -- `ModuleRef` / `ExecutionEngine` type imports
- `jac/jaclang/compiler/passes/native/{elf,macho,pe,wasm}_linker*` -- `emit_object` byte consumers (unaffected)
- `jac/jac.toml` -- the `llvmlite>=0.47.0` pin (leaves only after P3)
- `jac/launcher/mkpayload.sh`, `jac/build.zig`, `jac/launcher/launcher.zig` -- payload + binary build (P2)
- LLVM `llvm-c/*.h` -- the stable C API (Option B); numba/llvmlite `ffi/*` -- reference only
