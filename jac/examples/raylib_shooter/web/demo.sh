#!/usr/bin/env bash
#
# Build & serve the WASM/WebGL build of the Jac cube shooter.
#
#   1. compile shooter.na.jac -> shooter.wasm with `jac nacompile --target wasm32`
#      (the pure-Jac wasm linker; no wasm-ld / emscripten)
#   2. serve this directory over HTTP and open the page
#
# The same rlgl source that the native build links against libraylib.so is here
# compiled to wasm; its `import from raylib { ... }` externs become the module's
# wasm imports, satisfied by the WebGL shim in raylib_web.mjs.
#
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"          # repo root
PORT="${PORT:-8099}"

# Resolve a `jac` CLI: prefer the repo venv, else PATH.
JAC="$ROOT/.venv/bin/jac"
command -v "$JAC" >/dev/null 2>&1 || JAC="jac"

echo "▶ Building shooter.wasm …"
"$JAC" nacompile --target wasm32 "$HERE/shooter.na.jac" -o "$HERE/shooter.wasm"

URL="http://localhost:${PORT}/index.html"
echo "▶ Serving on ${URL}  (Ctrl-C to stop)"
( sleep 1; (command -v xdg-open >/dev/null && xdg-open "$URL") \
  || (command -v open >/dev/null && open "$URL") || true ) >/dev/null 2>&1 &
exec python3 -m http.server "$PORT" --directory "$HERE"
