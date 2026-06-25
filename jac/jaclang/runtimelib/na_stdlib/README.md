# Bundled native standard library (`na_stdlib`)

Pure-Jac `.na.jac` modules shipped with jaclang that implement a
Python-congruent **standard library for the native (na) compiler pathway**
(issues [#6404] / [#6940]). This is **Mechanism B**: ordinary Jac compiled and
linked like user code, with zero per-module backend work.

## How resolution works

`jaclang.jac0core.codeinfo.resolve_native_module` is the single shared resolver
used by `BoundaryAnalysisPass`, `NaIRGenPass`, and `NativeCompilePass`. It
searches **nearest-wins**:

1. the importing project's own tree (a flat sibling, then the dotted hierarchy
   walked up to the filesystem root), then
2. this bundled root (`native_stdlib_root()`).

So `import from os.path { normpath }` binds CPython's `posixpath` on the sv
(Python) pathway and `na_stdlib/os/path.na.jac` on the na (native) pathway (the
*same source* on both), while a user module of the same name always shadows the
bundled one. A bundled module links through the existing cross-module machinery
(binding population, then extern forward-decl, then `link_in`), on both the AOT
(`jac nacompile`) and JIT execution paths.

## Shipped modules

- **`os/path.na.jac`** (#6940 Phase 0) -- pure-string POSIX path helpers
  (`normpath`, `dirname`, `basename`, `split`, `splitext`, `isabs`).
- **`json.na.jac`** (#6940 Phase 1) -- a recursive-descent `loads` over boxed
  `any` (dict/list/str/int/float/bool/None) plus a `dumps` serializer matching
  CPython's default `(', ', ': ')` separators and insertion-ordered keys.
  Two documented divergences: `dumps` of a bare float uses the native
  `str(float)` (`%g`), not CPython's shortest-round-trip repr (parity is gated on
  the Ryu float repr, #6940 Phase 0.3); and only the control set + JSON
  metacharacters are escaped, so congruence holds for ASCII payloads
  (`ensure_ascii` of non-ASCII is a follow-up).

The syscall-backed `os` / `os.path` entry points (`makedirs`, `realpath`,
`mkdir`, `exists`, ...) are Mechanism-A/H compiler intercepts, reached via the
flat `import os`, not bundled here (see
`compiler/passes/native/na_ir_gen_pass.impl/os.impl.jac`).

## Adding a module

1. Drop `<name>.na.jac` (or `<pkg>/<name>.na.jac` for a dotted import) here,
   exporting its API with `def:pub`.
2. Use only the native-supported subset; prefer typed containers
   (`list[str]`, `dict[str, any]`). A bare `list = []` defaults to `i64`
   elements. An empty `list[any] = []` then grown with `.append(x)` lowers and
   boxes correctly, but a `list[any]` *literal* with scalar elements
   (`[1, 2, 3]`) does not yet box them -- build `any`-lists via `.append` (or
   `json.loads`). `dict[str, any]` literals box their values fine. Unbox a
   boxed scalar before operating on it (`i: int = some_any; str(i)`), and check
   container/None branches with `isinstance` -- `x is None` does not lower to a
   branch condition on the native pathway.
3. Add a tri-backend equivalence fixture
   (`jac/jaclang/compiler/tests/fixtures/prim_<name>.jac`) and register it in
   `test_prim_equivalence.jac` with `require=["na"]` so sv/na congruence is
   enforced, not assumed.

## Mechanism / portability

- **B (here)**: pure-Jac on primitives; portable to every native target
  (ELF/Mach-O/PE/WASM). Preferred.
- **A**: compiler intrinsics over libm/libc/syscalls (`math`, `time`, `os`,
  `random`, `struct`); native-host only.
- **F**: thin FFI wrappers over a system C library (`zlib` over libz, TLS over
  libcurl); native-host only.

Functions that need a syscall (`os.path.realpath`, `exists`, ...) stay as
Mechanism-A intercepts, not here.

[#6404]: https://github.com/jaseci-labs/jaseci/issues/6404
[#6940]: https://github.com/jaseci-labs/jaseci/issues/6940
