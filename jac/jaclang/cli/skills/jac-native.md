---
name: jac-native
description: Compiling Jac to a standalone native binary with `jac nacompile` - the `.na.jac` compute subset, linking precompiled C libraries via the native FFI import, what silently breaks, and the build/run verbs. Load when building a native binary, a single-file zero-dependency CLI, or any `.na.jac` file (incl. one that calls a C shared library).
---

A `.na.jac` file compiles through LLVM to a standalone, zero-dependency executable you can ship to machines that have neither Jac nor Python. It runs a **compute + C-FFI subset** of Jac: `def` functions, a `with entry` block, `glob` constants, and `obj` structs - no graph/OSP runtime and no Python. Beyond pure compute, it can link directly against a precompiled C shared library (no C compiler or system linker required).

```jac
# sum.na.jac
def compute_sum(n: int) -> int {
    total: int = 0;
    i: int = 1;
    while i <= n {
        total = total + i;
        i = i + 1;
    }
    return total;
}

with entry {
    print(f"Sum of 1 to 10: {compute_sum(10)}");
}
```

```bash
jac nacompile sum.na.jac -o sum    # emits the native binary `sum`
./sum                              # -> Sum of 1 to 10: 55
```

## What the subset supports

- `def` functions with typed params/returns; recursion and loops; `_`-prefixed private helpers.
- Types: `int`, `float`, `bool`, `str`, **plus C-ABI fixed-width numerics** `i32`, `i64`, `u8`, `f32`, `f64` (use these in FFI signatures so they match the C side). `glob` module-level constants (incl. hex literals like `0x1701`) and `obj` structs (`has` fields) also work.
- Control flow: `if/elif/else`, `while`, `for ... in range(...)`; arithmetic, comparisons, `//`, augmented assignment (`+=`), and `int(...)`/`float(...)` casts.
- `match` including structural patterns: sequence `case [a, b]`, star `case [first, *rest]`, mapping `case {"k": v}`, and class/archetype `case Point(x=0, y=ay)` (plus value/OR/wildcard/`as`/guards).
- Containers with their methods: `list`, `dict` (`get`/`pop`/`update`/`clear`/`keys`/`values`/`items`/...), `set` & `frozenset` (`add`/`remove`/`discard`/`union`/`intersection`/...), `tuple`; and a broad `str` method surface (`upper`/`lower`/`strip`/`split`/`join`/`find`/`replace`/`startswith`/`endswith`/...).
- `complex` numbers: `complex(re, im)`, `.real`/`.imag`, and `+ - * /`.
- Nested `def`s, including closures that capture enclosing-function locals (and recurse).
- `isinstance(x, T)` (inheritance-aware for `obj`/`node`/`edge`/`walker` archetypes) and `type(x)` (returns the type name as a `str`).
- `try`/`except`/`finally`, `raise`, and custom exception classes (`obj MyError(Exception)`).
- `f"..."` formatting and `print(...)`.
- A `with entry { ... }` block - the program's entry point.
- Booleans are `True` / `False` (capitalized). Lowercase `true`/`false` parse as undefined names and fail with a misleading `E1002: Cannot return <Unknown>, expected bool` - see `jac-core-cheatsheet`.

## Calling C libraries (the native FFI) - how native does graphics, I/O, etc.

A native binary has no Python runtime, so anything beyond pure compute comes from **linking a precompiled C shared library**. Declare its symbols in an `import from "<path-to-.so/.dylib>" { ... }` block; each `def` becomes an `extern` the Jac native linker resolves out of the library at load time (recorded as a `DT_NEEDED` ELF entry / `LC_LOAD_DYLIB` on macOS - there is no `cc`/`ld` step).

```jac
import from "./libraylib.so" {
    def InitWindow(width: i32, height: i32, title: str) -> None;
    def WindowShouldClose() -> bool;
    def rlVertex3f(x: f32, y: f32, z: f32) -> None;
    def rlColor4ub(r: u8, g: u8, b: u8, a: u8) -> None;
    def CloseWindow() -> None;
}

with entry {
    InitWindow(800, 600, "jac native");
    while not WindowShouldClose() {
        rlColor4ub(230, 41, 55, 255);
        rlVertex3f(-0.5, -0.5, 0.0);
    }
    CloseWindow();
}
```

- **Match the C ABI with fixed-width types** in the signatures (`i32`, `u8`, `f32`, `f64`, `bool`, `str`), not bare `int`/`float`.
- **Keep FFI calls scalar.** Passing or returning a multi-field struct *by value* (a 3-float `Vector3`, a `Camera3D`, a `Color`) does not reliably round-trip yet - bind the library's scalar entry points instead (e.g. raylib's `rlVertex3f`/`rlColor4ub`/`rlClearColor` rather than `DrawCube(Vector3,…)`/`ClearBackground(Color)`). An int return read straight into `float(...)` is a known safe workaround for some bindings.
- The `.so`/`.dylib` must exist at the import path at both compile and run time.

## Pitfalls

- **The file MUST be named `*.na.jac`**, built with `jac nacompile <file> -o <name>`, then run `./<name>`. (`jac run` is the interpreted path, not native.)
- **A `with entry { }` block is REQUIRED.** Without one, `jac nacompile` hard-errors: *"No entry point found."* A bare library of `def`s does not produce a binary.
- **⚠ Arbitrary Python stdlib imports do NOT work** - this is a native binary with no Python. Only a curated set is lowered (`sys`, `math`, `time`, `os`, `random` - e.g. `import math; math.pi` and `math.sqrt(x)` now work); any other `import json`-style module is rejected at compile time (`E5090`), **not** silently dropped. This is the Python stdlib - it is **distinct from** the C-FFI `import from "...so" { … }` above, which is the supported way to pull in external functionality.
- **Unsupported builtins fail loud, not silent.** A builtin the native subset cannot lower (e.g. `sum(range(...))`) is now a compile error (`E5090`), not a binary that prints garbage. Builtins that can *never* exist in a native binary - `eval`/`exec`/`compile`/`globals`/`locals`/`vars`/`dir`/`getattr`/`setattr`/`hasattr`/`delattr` - report `E5091` with the reason (no interpreter / no runtime reflection). `bytes(...)` construction is not lowered yet (`E5090`).
- **No graph / OSP / async in native.** Nodes, edges, walkers, `spawn`, `visit`, `report`, persistence (`root`), `async`, and `by llm` belong to the interpreted/served runtimes - not the native subset. (`obj`/`node`/`edge`/`walker` archetypes still compile as structs with methods, and `isinstance` understands their hierarchy - it is the graph *traversal* semantics that are out of scope.)
- The binary's stdout is exactly what you `print` - none of the `jac run` setup/compile chatter.
