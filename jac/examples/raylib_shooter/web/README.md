# Jac Cube Shooter - WASM / WebGL build

The **same** `shooter.na.jac` that the native demo links against `libraylib.so`,
here compiled to a browser `.wasm` module and rendered with WebGL - a *fourth*
target for one unchanged rlgl source.

```bash
./demo.sh           # builds shooter.wasm and serves http://localhost:8099
# then click the canvas to capture the mouse:
#   WASD move · mouse/arrows aim · Space fire · Tab release the cursor
```

## How it works

`jac nacompile --target wasm32 shooter.na.jac -o shooter.wasm` runs the native
LLVM backend at the `wasm32-unknown-unknown` triple and links the single
relocatable object into an instantiable module with the **pure-Jac wasm linker**
([`compiler/passes/native/wasm_linker.jac`](../../../jaclang/compiler/passes/native/wasm_linker.jac)),
with no `wasm-ld` or emscripten dependency.

The game's `import from raylib { ... }` block (`rlVertex3f`, `rlColor4ub`,
`rlTranslatef`, `IsKeyDown`, ...) does not resolve to a shared library here.
Undefined externs simply **become the module's wasm imports**, and the WebGL
shim in [`raylib_web.mjs`](./raylib_web.mjs) supplies them: it emulates rlgl's
immediate mode (a projection/modelview matrix stack + an `rlBegin`/`rlVertex3f`
batch) on one WebGL shader, and maps keyboard/mouse/pointer-lock to raylib's
scalar input calls. The small libc/runtime surface the Jac native runtime needs
(`malloc`/`free`/`memcpy`, `__multi3`, ...) is provided as `env` imports too.

The only source change vs the native build is the entry shape: the blocking
`with entry { while !WindowShouldClose() ... }` loop is split into `init()` (once)
and `frame()` (per `requestAnimationFrame`), because a browser tab cannot block
its main thread. All state already lived in module globals, so the split is
mechanical.

## Files

| File | Role |
|------|------|
| `shooter.na.jac` | the game (native rlgl source + `init()`/`frame()` entry) |
| `raylib_web.mjs` | WebGL shim: the `env` import object (rlgl + input + runtime) |
| `index.html`     | canvas + HUD; instantiates the wasm and drives the rAF loop |
| `demo.sh`        | build (`nacompile --target wasm32`) + serve |
| `shooter.wasm`   | build output (git-ignored) |

## Build surface (`int` is `i64`)

Jac `int` lowers to wasm `i64`, so any exported function taking/returning `int`
needs `BigInt` at the JS boundary (`e.get_score()` returns a BigInt). The hot
rlgl/input surface is all `i32`/`f32`, so it stays `BigInt`-free.
