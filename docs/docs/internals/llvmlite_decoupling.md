# Decoupling `na` from the Python `llvmlite` Dependency

> **Status:** Implementation RFC for [issue #6925](https://github.com/jaseci-labs/jaseci/issues/6925).
> **Goal:** remove the Python **`llvmlite`** package from the runtime entirely and
> link LLVM **directly into the Zig `jac` binary**, using **`py2jac`** to bootstrap
> the Jac-side reimplementation. Every fact below was measured against the tree
> and the upstream llvmlite checkout in `_planning/llvmlite/`.

## Overview

Native (`na`) Jac compiles to LLVM IR and JITs it via the Python `llvmlite`
package, which bundles a ~160 MB `libllvmlite.so` into the runtime payload. The
goal here is to delete that Python dependency and the bundled `.so`, fold LLVM
into the `jac` binary that Zig already builds, and reimplement llvmlite's two
Python layers in Jac -- bootstrapped mechanically with `py2jac` rather than
hand-written from scratch.

This is an **internals** document; it assumes the codespace model from
[Compiler Architecture](compiler_architecture.md) and the boundary model from
[Cross-Codespace Interop](interop.md).

## The shape of llvmlite (why this is tractable)

`llvmlite` is not one thing. It is three layers plus LLVM, and they decouple
cleanly:

| Layer | Source | Size | Nature | Plan |
|---|---|---|---|---|
| **`llvmlite.ir`** | `llvmlite/ir/*.py` | 4,424 LOC | **pure Python** IR *builder* (emits textual LLVM IR) | **`py2jac` -> Jac** |
| **`llvmlite.binding`** | `llvmlite/binding/*.py` | 4,358 LOC | **ctypes** marshalling over the `LLVMPY_*` C ABI | **`py2jac` -> Jac** |
| **ffi shim** | `ffi/*.cpp` | 4,447 LOC | **C++** wrapping LLVM's C++ API, exports `LLVMPY_*` | **compile with Zig, link into binary** |
| **LLVM** | upstream | tens of MB (host-only) | static libraries | **statically linked into the binary** |

**The key insight:** keep llvmlite's battle-tested C++ shim and statically link
it (plus LLVM) into the `jac` binary; translate only the two *Python* layers
with `py2jac`. Because the native ABI (`LLVMPY_*`) is preserved exactly, the
binding becomes a near-mechanical translation and every behaviour the `na` pass
already relies on -- including `enable_jit_events`, which has no clean LLVM-C
path -- keeps working unchanged. This is strictly less risky than the issue's
"rebind against LLVM-C" framing, and reuses far more existing, proven code.

### What we measured about the current artifact

- `libllvmlite.so` exports **312 `LLVMPY_*`** symbols and **0 raw `LLVM*`**
  symbols. That is deliberate: `ffi/CMakeLists.txt` sets
  `CXX_VISIBILITY_PRESET hidden` and exports only the shim. So binding LLVM-C
  directly is impossible against today's `.so` -- but the `LLVMPY_*` ABI we keep
  is exactly what `binding` already calls.
- The payload tool pip-installs llvmlite from the `jac.toml` spec into the
  bundled `site/` at `jac/launcher/payload.zig:330-332`; `jac/jac.toml:10` pins
  it. Those are the two removal points.
- The launcher (`jac/launcher/launcher.zig`) links libc only and **dlopens the
  bundled libpython in-process**. So symbols linked into the `jac` executable
  are reachable from the embedded interpreter's `ctypes.CDLL(None)` -- provided
  they are in the binary's dynamic symbol table (see Part 1).

## Target architecture

```
 TODAY                                   AFTER
 jac binary (libc launcher)              jac binary (libc launcher)
   -> dlopen libpython                     -> dlopen libpython
        -> import llvmlite (Python pkg)         -> import jaclang...._llvm  (Jac, py2jac'd)
             ir/      (pure Python)                  ir/      (pure Jac)
             binding/ (ctypes)  ──┐                  binding/ (ctypes)  ──┐
   payload/site/llvmlite/         │                                       │ CDLL(None)
     libllvmlite.so  ~160 MB  ◄───┘ CDLL(path)   [LLVMPY_* shim + LLVM] ◄─┘
       (shim + LLVM, from wheel)               statically linked INTO the jac binary
```

The `.so` and the Python package both disappear; the shim+LLVM move into the
binary; the two Python layers become vendored Jac.

## Part 1 -- Native: LLVM + shim into the `jac` binary

1. **Compile `ffi/*.cpp` with Zig.** Zig compiles C++ via its bundled clang and
   ships its own libc++ (`link_libcpp = true`), which sidesteps the host
   `libstdc++` coupling today's `.so` carries. Add the shim as a **dedicated
   native-runtime compilation unit** in `build.zig`, linked into the final `jac`
   executable -- *not* folded into the hot launcher path, which must stay
   libc-only and run before Python. The shim's symbols sit dormant until the
   native pass first calls one.
2. **Provide host-only LLVM static archives.** `ffi/CMakeLists.txt` lists the
   components: `mcjit orcjit OrcDebugging AsmPrinter AllTargetsCodeGens
   AllTargetsAsmParsers`. `na` is **MCJIT-only**, so drop `orcjit` /
   `OrcDebugging` (and exclude `ffi/orcjit.cpp`, 379 LOC) and build
   `LLVM_TARGETS_TO_BUILD=host`. Source the archives via a **pinned fetch step**
   that mirrors the existing `payload fetch-pbs` / `fetch-typeshed` pattern
   (`payload fetch-llvm <os-arch>`), so contributors download prebuilt static
   libs rather than building LLVM locally -- consistent with how the bundled
   CPython and typeshed are already provisioned. (Build-from-source stays
   available as a fallback for unsupported triples.)
3. **Export `LLVMPY_*` from the binary.** The shim's CMake hides everything;
   here we must do the opposite for the ~312 `LLVMPY_*` entry points so
   `ctypes.CDLL(None)` (RTLD_DEFAULT over the process image) resolves them.
   Link the `jac` executable with an exported-symbol list limited to `LLVMPY_*`
   (keep all other symbols, including raw `LLVM*`, hidden -- no namespace
   pollution, smaller dynamic table than blanket `--export-dynamic`).

**Result of Part 1:** the ~160 MB `libllvmlite.so` leaves the payload; a pruned
host-only LLVM + the shim live in the `jac` binary; `LLVMPY_*` is callable from
the embedded interpreter exactly as before.

## Part 2 -- Jac binding (`py2jac` from `binding/*.py`)

1. **Translate** `llvmlite/binding/*.py` with `py2jac` into a vendored package,
   e.g. `jac/jaclang/compiler/passes/native/_llvm/binding/`.
2. **Re-point the loader.** `binding/ffi.py` does `ctypes.CDLL(<path to .so>)`;
   change it to `ctypes.CDLL(None)` so it binds the in-binary shim. This file
   uses `__slots__` + `__getattr__` for its lazy `ffi.lib.LLVMPY_*` function
   table; both are supported in Jac, but because it is small and the most
   native-coupled piece, hand-authoring the Jac loader (rather than shipping
   `py2jac` output verbatim) is the cleaner choice.
3. **Apply the fix-up pass** (Part 4).
4. **Re-point consumers:** `na_compile_pass(.impl)`, `wasm_build`, the
   `ModuleRef`/`ExecutionEngine` type imports in `codeinfo`, and the single
   `add_symbol` touchpoint in `interop_bridge`.

## Part 3 -- Jac IR builder (`py2jac` from `ir/*.py` -- the bulk)

`llvmlite.ir` is pure Python with **no native dependency** -- it builds an
in-memory object graph and emits textual IR. Translating it removes a dependency
outright (nothing native to link).

1. **Translate** `llvmlite/ir/*.py` (builder, instructions, module, types,
   values, ...) with `py2jac` into `.../_llvm/ir/`.
2. **Apply the fix-up pass** (Part 4). The `@contextlib.contextmanager` + `yield`
   helpers in `builder.py` (`goto_block`, `if_then`, ...) translate -- Jac
   supports generators, decorator factories (`@functools.wraps`), and the dunder
   surface these use.
3. **Re-point consumers:** `na_ir_gen_pass` (+ its impl tree), `compiler/targets/abi`,
   `primitives_native`, `type_evaluator.impl/imported`, `jac0core/impl/unitree`.
4. **Validate by golden IR.** The current path already produces textual IR fed to
   `parse_assembly`; assert the Jac builder emits **byte-identical** IR for every
   module in the `na` suite before flipping the default.

## Part 4 -- The `py2jac` fix-up pass

`py2jac` is a faithful first-draft engine, not a finishing tool. Measured on real
llvmlite source (`ir/types.py`, `binding/executionengine.py`), it gets the hard
parts right and fails in three concentrated, **mechanical** ways:

| What `py2jac` gets RIGHT (leave alone) | What needs a fix-up codemod |
|---|---|
| bare `super.method` (the dominant Jac idiom), `@property`/`@classmethod`/`@staticmethod`, `__new__` (Jac `class` *invokes* it; instance-cache semantics match Python), ctypes `.argtypes`/`.restype` (preserved), `__str__`/`__eq__`/`__hash__`/`__repr__`, `with ... as` context managers, `yield`, `__getattr__` | **(1) `has` declarations:** emits Python's implicit `self.x = ...` but **zero** `has x: T;`. In `class` mode the checker then can't see any instance attribute -- one 20 KB module produced ~43 `E1032 "Type is Unknown"` + `E1030/E1031`. Synthesize `has` decls from `__init__`/`__new__`/class-body assignments. |
| | **(2) `del x` -> `delete(x,)`:** confirmed runtime `NameError: name 'delete' is not defined`; silently breaks e.g. `_StrCaching`'s cache invalidation. Rewrite to the native `del` statement. |
| | **(3) no type inference:** every param `: Any`, every return `-> object`. Type at least the public surface to pass `jac check` and meet the repo's type-safety bar. |

Two of the three (`has`, `del`) are pure syntactic codemods over the vendored
output. **Recommendation:** fix `has`-emission *inside `py2jac`* -- it is the
single highest-leverage gap and pays off for every future Python->Jac port, not
just this one. Type annotations (3) are the only inherently manual part, bounded
to the public API surface.

## Part 5 -- Remove the package

- Delete the `llvmlite` pin from `jac/jac.toml:10`.
- Delete the pip-install block at `jac/launcher/payload.zig:330-332`; `llvmlite`
  no longer lands in the payload `site/`.
- **License:** llvmlite is BSD-2-Clause. Carry its `LICENSE` (and
  `LICENSE.thirdparty`) into the vendored `_llvm/` directory and attribute the
  translation -- the Jac code is a derived work.

## Phasing (each phase independently verifiable)

The `na` suite (`jac/tests/compiler/passes/native/` plus the `na_py_interop*`
fixtures, which already exercise `na`<->`sv`, `na`<->py, `na`<->`na`) is the gate
throughout.

1. **Native unit lands.** `build.zig` compiles the shim, links host-only LLVM,
   exports `LLVMPY_*`. Smoke test: from the bundled interpreter,
   `ctypes.CDLL(None).LLVMPY_LinkInMCJIT` resolves. No Jac changes yet; the
   wheel still drives `na`.
2. **Vendored Jac binding behind a flag.** Runs parallel to the wheel; parity
   harness asserts identical JIT behaviour and **byte-identical**
   `emit_object`/`as_bitcode`.
3. **Vendored Jac `ir` builder.** Golden byte-identical IR across the suite, then
   flip both Jac layers to default and delete `import llvmlite.*`.
4. **Drop the package.** Remove the `jac.toml` pin and the `payload.zig`
   install; `na` suite green on the wheel-free binary; record the size delta vs
   the 160 MB `.so`.

## Risks

- **LLVM static-lib sourcing** -- pin a version, host prebuilt host-only archives
  per shipped platform; keep a build-from-source fallback. Largest logistical
  item.
- **libc++ / RTTI** -- the shim builds `-fno-rtti` against LLVM in most configs;
  match LLVM's RTTI setting or the link fails (the CMake has the same dance).
- **Symbol export** -- only `LLVMPY_*` must enter the dynamic table; verify the
  embedded interpreter resolves them and that nothing else leaks.
- **`py2jac` fix-up tail** -- mostly mechanical (`has`, `del`, types), but spot-
  check the generator/context-manager helpers in `ir/builder.py` and the
  `__getattr__` loader after translation.
- **License/attribution** -- vendoring a translation of BSD-2 code requires
  carrying the notice.

## References

- `_planning/llvmlite/` -- upstream checkout: `ir/*.py` (4,424 LOC, py2jac in), `binding/*.py` (4,358 LOC, py2jac in), `ffi/*.cpp` (4,447 LOC, Zig-compiled shim), `ffi/CMakeLists.txt` (LLVM component list)
- `jac/jaclang/compiler/passes/native/na_compile_pass.jac` + `impl/` -- binding consumer; `enable_jit_events` at `impl/na_compile_pass.impl.jac:262`
- `jac/jaclang/compiler/passes/native/na_ir_gen_pass*`, `compiler/targets/abi.jac`, `primitives_native.jac` -- `llvmlite.ir` consumers
- `jac/jaclang/jac0core/interop_bridge.jac` (single `add_symbol`), `codeinfo.jac` (`ModuleRef`/`ExecutionEngine`)
- `jac/launcher/payload.zig:330-332` (payload install), `jac/jac.toml:10` (pin), `jac/build.zig`, `jac/launcher/launcher.zig` (in-process libpython dlopen)
- `jac py2jac <file.py>` -- the Python->Jac translator (`cli/commands/transform.jac` -> `PyastBuildPass`)
