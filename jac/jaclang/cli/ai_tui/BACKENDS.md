# `jac ai --tui` Backend

See `ARCHITECTURE.md` for the renderer module stack and data flow, and
`PROTOCOL.md` for the wire grammar (both still describe the NA renderer the embed
host links).

`jac ai --tui` has **one** backend: the self-hosting **embed host**. The former
in-process (`libtui.so` via ctypes) and subprocess (`jac-na-tui` sidecar)
transports -- and the `JAC_AI_TUI_BACKEND` selector -- are retired. Both ran the
byLLM agent in the *parent* jac interpreter with the NA layer as only the
renderer; the embed host runs the whole stack self-contained.

## The embed host

- **Binary:** `jaclang/cli/ai_tui_na/bin/jac-ai-tui`, compiled from
  `ai_tui_na/host_embed.na.jac` by `ai_tui_na/build_embed.sh`.
- It **is** the host: the renderer is linked Jac and the byLLM agent runs in an
  embedded CPython that `libjacpyembed` brings up. One process, no IPC, no
  ctypes seam, no agent-in-the-parent.
- **Dispatch:** `jaclang/jac0core/impl/runtime.impl.jac` (`JacCmd.run_ai_agent`)
  routes `req.tui` to `jaclang/cli/ai_tui/run_tui_embed.jac`, which `execve`s the
  host so it owns the controlling terminal with no relay layer.

## Two build variants (same source, same single backend)

| Variant | Produced by | Self-boots? | Used by |
| ------- | ----------- | ----------- | ------- |
| **Trailered** (self-contained, ~109 MB) | `build_embed.sh` | yes -- carries its own CPython+jaclang payload | dev tree (`_ensure_embed_host` compiles it on first launch) |
| **Trailerless** (~472 KB + ~11 MB shim) | `build_embed.sh --no-trailer` | no -- borrows a runtime via `JAC_RT_DIR` | the fused `jac` payload (`launcher/payload.zig` `buildEmbed`) |

The trailerless variant is what ships: baking a second ~108 MB runtime copy into
every binary is avoided by having the host reuse the fused CLI's already
materialized `rt/<hash16>` tree. `launcher/pyembed.zig` honors `JAC_RT_DIR` (gated
on the tree's `.ok` marker), falling back to the trailer path when it is unset.

## Launch contract (`run_tui_embed.impl.jac`)

The dispatch builds the child env, then `execve`s the host:

| Variable | Meaning | Source |
| -------- | ------- | ------ |
| `JAC_AI_UI_PROJECT` / `_FILES` / `_MODEL` / `_NCTX` / `_MODEL_PRESETS` / `_RESUME` / `_CONTINUE` / `_SESSION` / `_ACTIVE` | the agent UI contract (set via `tui_shared._configure_ui_env`) | `AgentRequest` + project scan |
| `JAC_AI_TUI_EMBED_REAL=1` | select the real agent over the boot stub | always |
| `JAC_AI_TUI_BYLLM_SRC` / `JAC_AI_TUI_DEPS` | byLLM + LLM-stack sys.path seams -- the **dev / `-Dskip-byllm` fallback** when byLLM isn't payload-bundled | `tui_shared._embed_byllm_seams` (`find_spec`, never imports) |
| `JAC_RT_DIR` | the fused CLI's materialized rt, so the trailerless host reuses it | set only when the parent itself runs fused (`JAC_STANDALONE=1`) |

When byLLM is bundled (the default -- see below) the borrowed rt's `site` already
holds it, so the seams resolve to that same dir (harmless) or stay unset; model
presets then compute normally even in a fused parent. The seams (and the guarded
`_MODEL_PRESETS` import) remain the path for a dev tree or a `-Dskip-byllm` build,
where byLLM is reached from the surrounding venv instead.

Debugging: `JAC_AI_TUI_DEBUG_LOG=<path>` appends a frame/command trace.

## byLLM is bundled (default)

A normal release build bundles byLLM + its LLM stack into the payload `site`, so
the shipped `jac ai --tui` runs the real agent **fully offline** -- no runtime
seams. The wiring (`launcher/payload.zig` `buildByllm`, driven by build.zig's
`-Dskip-byllm` opt-out / `-Dbyllm-dir` override):

- byLLM is pure Jac+Python source, copied from the `../jac-byllm` checkout like
  jaclang, plus a synthesized `byllm-<ver>.dist-info` carrying its `[jac]` entry
  points (read from byllm's `jac.toml`) so the plugin still registers via
  `entry_points(group='jac')`. Its three entry-point modules import lazily, so
  registering them costs plain `jac` commands nothing.
- The deps (litellm + the openai/pydantic/tiktoken/tokenizers closure, loguru,
  httpx, pillow ≈ 200 MB) are `pip install --target site`-ed, pinned to byllm
  `jac.toml`'s `[dependencies]` constraints, as cp314-ABI wheels (matches the
  bundled CPython 3.14). Run **after** the JIR precompile so the precompiler's
  jaclang-only walk never touches byLLM's `.jac` modules (they JIT on first run).

`-Dskip-byllm` drops all of this (faster build) and falls back to the runtime
seams above; linked-source / `-Ddev` builds never bundle it (no `site` to install
into). Mirrors the desktop host's `_scale_runtime_hook_py`, which still defers
bundling.

## Renderer test harness (not a backend)

`jaclang/cli/ai_tui/tui_host.jac` (`TuiHost`, ctypes over `bin/libtui.so`) and
`tests/cli/test_ai_tui_host.jac` survive as the in-process **test harness** for
the *same* NA renderer the embed host links -- they exercise the TuiState/
DiffEngine parser, key handling, and gated-render invariants without booting a
full embedded interpreter. `libtui.so` is built by `ai_tui_na/build.sh` on a dev
tree and is **not** shipped in the payload.
