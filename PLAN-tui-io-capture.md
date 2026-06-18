# Plan: Capture Leaked I/O Through the TUI Pipeline

> **Context:** During `jac ai --tui`, model answer text, byllm loguru errors, and
> LiteLLM error footers bleed through the real terminal even though structured
> agent events are captured via `ui_stream()` → IPC frames → sidecar transcript.
>
> **Goal:** Route all UI-visible output through `agent.bus` so the TUI transcript
> is the single surface. No `PROTOCOL.md` changes (unless the `tool`-kind
> decision requires it) - use existing `error` / `system` event kinds.
>
> **Status:** Implemented (Phases 0–2, including 2c order-independent dedup).
> Implementation steps 1–8 complete. Tests cover Phase 1 (stdout gating,
> tool→call routing) and Phase 2 (loguru sink capture, litellm footer gate, and
> both dedup orderings). Phase 3 (StderrRelay) intentionally skipped; steps 9+
> optional.
>
> **Backend:** The **NA** sidecar (`jac-super/jac_super/ai_tui_na/`).

## Scope: TUI only

This is a **TUI-only** problem. `jac ai --ui` spawns the agent in a child process
with `stdout`/`stderr` redirected to `/tmp/jac_ai_ui.log` (`_run_ui_server`,
`ai_agent.impl.jac:3358`), so the same writes land in the log file harmlessly -
no visible leak exists in the web path today. The shared bus seam is still the
right unification for code cleanliness, but there is no `--ui` bug to fix.

## Problem

`jac ai --tui` only captures **structured bus events**. Four other output paths
still hit the real terminal (the Python agent shares the terminal with the NA
sidecar, which paints on the `/dev/tty` alt-screen):

| Leak | Source | File | Mechanism |
|------|--------|------|-----------|
| Answer/reasoning text | `out.write()` in `render_stream` | `ai_agent.impl.jac:2011` | raw `sys.stdout.write`, not gated |
| byllm errors | loguru `logger.error()` | `byllm/llm.impl/model.impl.jac:197+` | loguru default sink (bound at import; **not** `sys.stderr`) |
| LiteLLM footers | litellm `print()` | `litellm/.../exception_mapping_utils.py:250` | raw `print()` to **stdout**, gated by `litellm.suppress_debug_info` |
| Agent exceptions | `console.error()` in except block | `ai_agent.impl.jac:2197` | routes to `sys.stderr` at call time |

`JAC_AI_SUPPRESS_TERM_OUTPUT=1` (set in `run_tui_session.impl.jac:91`) only gates
`_term_print()`. It does **not** gate raw `sys.stdout.write()`, loguru, litellm
`print()`, or `console.error`.

### Why a stderr relay is not the answer

A naïve fix - replace `sys.stderr` with a relay that forwards lines to the bus -
**misses two of the three infra leaks**, verified empirically against the repo's
own loguru:

- **loguru binds its sink at import time.** Reassigning `sys.stderr` after import
  does **not** redirect `logger.error()` (confirmed: captured output was empty).
  byllm's errors go to loguru's default sink, so a stderr relay cannot see them.
- **The litellm footer is a `print()` to stdout**, not stderr
  (`exception_mapping_utils.py:250`). A stderr relay cannot see it either.

So the only stderr writer a relay would catch is `console.error` (dynamic
`sys.stderr` lookup) - and that path is already rerouted to the bus by Phase 1.
The real fix is **at the source, on the application boot seam**, not downstream.

## Design principle

**One seam for all UI-visible text, installed once at boot:**

```
any output  →  agent.bus  →  ui_stream()  →  IPC frames  →  NA transcript
```

`ui_configure()` (`ai_agent.impl.jac:2887`) is the single boot seam already
called by both `run_tui_session` and the `--ui` server. It sets
`agent.bus.active_feed = True` and is the right place to install process-global
output redirection (loguru sink + litellm flag), so the agent never has to know
which UI mode is active.

Do **not** pollute low-level libraries (byllm) with UI-mode awareness - that
couples an LLM library to the agent's UI concept. byllm keeps calling
`logger.error()`; the agent decides where loguru writes.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Leak sources                                                │
│  render_stream stdout │ byllm loguru │ litellm │ console.err│
└───────────┬─────────────────┬──────────────┬────────────────┘
            │                 │              │
   Phase 1: gate writes   Phase 2: reconfigure loguru sink
                          (at ui_configure) + suppress_debug_info
            │                 │              │
            ▼                 ▼              ▼
                    agent.bus (emit / emit_stream)
                              ▼
                    ui_stream() → IPC → jac-na-tui transcript
```

## AI output capture (existing - Phase 1 closes the parallel path)

AI output is **already captured** on the bus for TUI/`--ui` sessions. Phase 1's
job is to make the bus the **only** path by killing the parallel terminal
writes - not to invent a new capture path.

### End-to-end pipeline (working today)

```
byLLM StreamEvent (thought | chunk | tool_call | …)
        │
        ▼
TurnRenderer.render_stream()          TurnRenderer.route_stream_event()
  (phase ReAct loop)                    (QA routing call)
        │                                        │
        ├─ emit_stream("reasoning", tok)         └─ emit_stream("reasoning", tok)
        ├─ emit_stream("answer", tok)
        ├─ emit("tool", …)          ← tool invocation label
        ├─ emit("tool_result", …)   ← tool output (truncated)
        └─ emit_call(…) via _emit_call_usage  ← token counts
        │
        ▼
agent.bus (AgentEventBus)  emit / emit_stream → publish() → subscriber queue
        │
        ▼
ui_stream()  - first yield: full snapshot; then per-emit deltas
        │
        ▼
run_tui_session._write_frame()  - TYPE:full|delta, EV:id:kind:node:text
        │
        ▼
jac-na-tui ipc.na.jac  - parse frame → TuiState.events
        │
        ▼
feed.na.jac build_rows()  - wrap + markdown (answers/reasoning)
        │
        ▼
screen.na.jac  - colored transcript rows in the framed UI
```

`ui_configure()` sets `agent.bus.active_feed = True` at TUI boot. Without that
flag, `emit` / `emit_stream` are no-ops and nothing reaches the sidecar.

### Event kinds - what is AI output vs control plane

| Bus `kind` | Source | AI / user visible? | In PROTOCOL.md? | Leak risk |
|------------|--------|--------------------|-----------------|-----------|
| `user` | `ui_send` → `begin_turn` | user input | ✓ | none |
| `answer` | `render_stream` `chunk` → `emit_stream` | model final text | ✓ | **stdout `out.write(tok)` duplicates** → Phase 1 |
| `reasoning` | `render_stream` `thought`, `route_stream_event` | model thinking (verbose) | ✓ | **stdout `out.write(cleaned)` duplicates** → Phase 1 |
| `phase` | `bus.enter(phase)` | phase label (Plan/Build/QA) | ✓ | none |
| `call` | `emit_call` via `_emit_call_usage` | token-usage row | ✓ | none |
| `system` | connect/stop/settings msgs | status text | ✓ | none |
| `error` | `_ui_turn_worker`, settings | failure text | ✓ | **loguru + litellm footers duplicate** → Phase 2 |
| `tool_result` | `flush_result` → `emit` | tool stdout/stderr (truncated) | ✓ | none (subprocess captured) |
| `tool` | `render_stream` `tool_call` → `emit` | tool invocation summary | **✗ not in PROTOCOL enum** | **see "tool-kind gap" below** |
| `status` | `set_status` | drives status pill only (not transcript) | ✗ (control) | none |

PROTOCOL.md (`PROTOCOL.md:72`) canonical kind enum: `user, answer, reasoning,
system, error, phase, call, tool_result`. **`tool` is not in it.** The agent
*does* emit `tool` (`render_stream`), and the NA renderer renders it via the
generic plain-wrap fallback (`feed.na.jac` returns prefix `"  "` for unmapped
kinds). The `#` prefix in the transcript belongs to `call`, not `tool`.

### ⚠️ tool-kind gap (adjacent bug surfaced by Phase 1)

Today the tool-invocation label reaches the terminal via `_term_print(...)`
(the `tool_call` branch in `render_stream`) **and** the bus via
`emit("tool", …)`. Phase 1 kills the terminal line. Because `tool` is not in
the PROTOCOL enum, it renders only via the NA generic fallback (no visible
prefix), so after Phase 1 tool invocations may effectively disappear from the
transcript while `tool_result` still shows. Decide before/with Phase 1:

- **(a)** Add `tool` to the PROTOCOL enum + a renderer prefix (small protocol
  change), or
- **(b)** Re-route the invocation label onto the existing `call` kind, or
- **(c)** Accept that invocations are summarized by the following `tool_result`.

This is its own decision; the plan should not silently drop tool labels.

### Streaming mechanics (`emit_stream`)

Reasoning and answer tokens arrive one at a time from byLLM. `emit_stream`
appends to the trailing event when `kind` and `streaming` match, then re-publishes
the grown event so `ui_stream()` yields a delta per token burst
(`AgentEventBus.emit_stream`, `ai_agent.impl.jac:1311`). The TUI sidecar upserts
by `id`, so the transcript grows in place without one event per token flooding
the ring buffer.

### What Phase 1 changes for AI output

**Before (broken):** every answer/reasoning token goes to **two** sinks:

```jac
out.write(tok);                        // ← leaks to real terminal
agent.bus.emit_stream("answer", tok);  // ← correct TUI path
```

**After (target):** in UI mode, terminal sink is off; bus is the only sink:

```jac
if _term_output_enabled() {
    out.write(tok);   // CLI jac ai only
}
agent.bus.emit_stream("answer", tok);   // always
```

Same for reasoning (`thought` → `cleaned`) and the `\r ● thinking…` spinner.

`route_stream_event` (`ai_agent.impl.jac:2552`) already only calls
`emit_stream` - no stdout writes. No change needed there.

## Phase 0 - One "UI mode" signal (no alias)

**Goal:** One env var, one helper, describing *state* ("agent drives a UI") not
*mechanism* ("suppress terminal").

Today: `JAC_AI_SUPPRESS_TERM_OUTPUT=1` set by `run_tui_session.impl.jac:91`,
read by `_term_output_enabled()` (`ai_agent.impl.jac:338`). The name describes a
mechanism and reads awkwardly as the concept generalizes to loguru/litellm
capture.

**Decision (pick one, do not alias both):**

- **(recommended) Full migration:** rename to `JAC_AI_UI_ACTIVE`, update the
  three sites (`run_tui_session.impl.jac:90-91,170-172`,
  `ai_agent.impl.jac:338-339`) and the existing test
  (`test_ai_tui_bridge.jac:162`), drop the old name. Clean, no divergence debt.
- **(minimal) Keep the name:** leave `JAC_AI_SUPPRESS_TERM_OUTPUT` as the single
  signal; do not introduce a second var.

Either way: **one name, one helper.** Fold the env check into the existing
`_term_output_enabled()` (it already encodes "may I print?"). Do not add a
parallel `_ui_mode_active()` - two functions drift. Call `_term_output_enabled()`
everywhere below, including Phase 2's loguru/litellm wiring.

**Files:** `jac-super/jac_super/ai_agent/impl/run_tui_session.impl.jac`,
`jac/jaclang/cli/impl/ai_agent.impl.jac`,
`jac-super/tests/test_ai_tui_bridge.jac`.

---

## Phase 1 - Stop stdout duplication (highest impact)

**Goal:** Answer/reasoning only goes to the bus in UI mode.

In `TurnRenderer.render_stream` (`ai_agent.impl.jac:2011`):

1. Gate every `out.write()` / `out.flush()` on `_term_output_enabled()`:
   - reasoning tokens (`thought` → `cleaned`)
   - answer tokens (`chunk` → `tok`)
   - thinking spinner (`\r ● thinking…`)
   - `clear_think()` / `end_line()` cursor tricks

2. **Always** keep `agent.bus.emit_stream(...)` - that path is correct.

3. In the `except` block (`ai_agent.impl.jac:2197`): replace bare
   `console.error(...)` with a bus emit in UI mode:

```jac
if not _term_output_enabled() {
    agent.bus.emit("error", {"text": f"agent error: {e}"});
} else {
    console.error(f"agent error: {e}");
}
```

   (`_ui_turn_worker` already emits this same message on its own except path, so
   this keeps `render_stream` failures consistent and dedups against the worker.)

1. Audit other direct stdout users in the agent path:
   - `route_stream_event` - already bus-only ✓
   - tool subprocess output - already captured into `tool_result` ✓
   - `console.print` in help/guides - only on explicit commands ✓

**Resolve the tool-kind gap** (see above) alongside this phase so killing the
terminal line doesn't hide tool invocations.

**Test:** Extend `jac-byllm/tests/test_ai_agent.jac` `capturing()` (line 80):

- set `JAC_AI_UI_ACTIVE=1` (or `JAC_AI_SUPPRESS_TERM_OUTPUT=1` if keeping the
  name), `active_feed=True`
- run `render_stream` with fake stream
- assert stdout capture is empty
- assert bus events contain answer/reasoning

**Expected result:** Fragmented "Plan: / Jaseci ecosystem" bleed stops.

---

## Phase 2 - Source-level capture at the boot seam (the real infra fix)

**Goal:** Route byllm loguru errors and litellm footers into the bus **at the
source**, via `ui_configure`. This replaces the originally-proposed
`StderrRelay`, which provably cannot catch either leak (see "Why a stderr relay
is not the answer").

`ui_configure()` (`ai_agent.impl.jac:2887`) is the single boot seam for both
TUI and `--ui`. It already sets `active_feed = True`. Add two install-time
operations there, guarded by UI mode being active (`not _term_output_enabled()`):

### 2a. Reconfigure the loguru sink → bus

loguru's `logger` is a process-global singleton shared by byllm and the agent
(byllm does `import from loguru { logger }`). A loguru sink is a **callable
that receives a structured record** - no ANSI to strip, no text to classify:

```python
def _install_loguru_bus_sink():
    from loguru import logger
    logger.remove()  # drop the default stderr sink - the one thing a relay can't do
    def _sink(message):
        record = message.record
        text = record["message"]
        exc = record.get("exception")
        if exc is not None:
            text += "\n" + "".join(traceback.format_exception(exc.type, exc.value, exc.traceback))
        # Level → bus kind: structured, not regex on rendered text.
        kind = "error" if record["level"].no >= logger.level("ERROR").no else "system"
        _bus_emit_guarded(kind, f"provider: {text}")
    logger.add(_sink, level="WARNING")
```

- `logger.remove()` is what makes byllm's `logger.error()` stop hitting the
  terminal - the one thing a stderr relay could not do.
- Level → bus kind mapping is structured, not regex on rendered text.
- byllm is **untouched** - it keeps calling `logger.error()`. No layering
  violation, no coupling of an LLM library to the agent's UI mode.

### 2b. Suppress the litellm footer

The footer is `print()` to **stdout** gated by
`litellm.suppress_debug_info` (`exception_mapping_utils.py:250`, verified).
One line in `ui_configure`:

```python
import litellm
litellm.suppress_debug_info = True
```

No `LITELLM_LOG` env guessing, no monkeypatch. The actual error text still
propagates as an exception → caught by the agent → emitted on the bus.

### 2c. Dedup against the agent's own error emit

`_ui_turn_worker` already emits `bus.emit("error", {"text": f"provider: {e}"})`
for the same LLM failure. To avoid a duplicate row, dedup on **structured
signal** (the exception type/message within a short window) inside the sink -
not on rendered stderr text. Unify the wording while you're there (see Success
criteria).

**Ordering reality (implemented):** byllm calls `logger.error(...)` **then**
`raise` (`model.impl.jac:196-215`), so the loguru sink fires **before** the
worker's `except` ever runs. A one-directional "register then the sink skips"
scheme therefore double-emits in practice. The fix is bidirectional and
order-independent:

- `_ui_bus_emit_guarded` **remembers** every `error` it surfaces (the sink path),
  so a later worker emit for the same failure collapses onto that row.
- The worker / `render_stream` except paths **check** `_ui_is_duplicate_provider_error`
  *before* emitting and `register_ui_provider_error` *after*, so a sink emit that
  already happened suppresses them - and a non-provider error (tool bug, agent
  logic) with no prior loguru row still surfaces.
- `_ui_provider_fingerprint` normalizes away both decorations - the `provider:`
  bus prefix and byllm's `LLM <Kind>Error:` loguru label - so the worker's bare
  `str(exc)` and the labelled loguru record collapse to the same key. Without
  this the two texts diverge after `provider:` and front-truncation (`[:240]`)
  drops the discriminating tail.

Covered by the realistic-order regression test in `test_ai_tui_bridge.jac`
("ui output capture dedups when the loguru sink fires before the worker emit").

### Thread safety

In TUI the LLM call runs on the cmd-reader thread while `ui_stream()` is drained
on the stream-writer thread. A loguru sink that calls `bus.emit(...)` must:

- be safe to call from any thread (loguru invokes sinks on the logging thread),
- guard reentrancy with a thread-local flag (`_emitting`) so a log emitted *from
  inside* the bus path doesn't recurse into the sink. Wrap the emit in
  `_bus_emit_guarded` above.

**Test:** `jac-byllm/tests/test_byllm.jac` with UI mode active + mocked APIError:
assert no line reaches the real terminal and exactly one `error` event reaches
the bus (not two).

---

## Phase 3 - StderrRelay (rejected)

After Phases 1–2, Python should write almost nothing to the terminal. A stderr
relay is **not** required for correctness and was **not** implemented - the plan's
own analysis (see "Why a stderr relay is not the answer") shows it only catches
dynamic `sys.stderr` writers, which Phase 1 already routes at the source.
Monkeypatching `sys.stderr` in a Python shim was rejected as brittle slop.

If belt-and-suspenders is ever needed, prefer OS-level fd redirect in the TUI
launcher (same idea as `--ui`'s child-process log redirect), not a Python
file-like wrapper.

---

## Phase 4 - TUI presentation (optional polish)

No protocol change; renderer already styles `error` (red bold) and `system`
(cyan).

Optional UX in `feed.na.jac` / `screen.na.jac`:

- Prefix infra errors: `⚠ provider:` for loguru-relayed provider text
- Collapse consecutive duplicate errors
- `/verbose` toggle for relayed `system` lines

---

## Phase 5 - NA sidecar hardening (belt and suspenders)

After Phases 1–2, Python should write almost nothing to the terminal.

Optional: redirect Python **stdout** to `os.devnull` during session (only after
Phase 1 verified - makes debugging harder).

Do **not** redirect sidecar debug stderr (`[tui] starting`) during normal use;
gate behind `JAC_AI_TUI_DEBUG_LOG`.

---

## Implementation order

| Step | Effort | Impact | Risk | Status |
|------|--------|--------|------|--------|
| 1. Decide tool-kind gap (a/b/c) | Small | Unblocks Phase 1 | Low | Done |
| 2. Phase 0 single env var + helper | Small | Foundation | Low | Done |
| 3. Gate `render_stream` stdout | Small | High | Low | Done |
| 4. Fix except → bus.emit | Tiny | Medium | Low | Done |
| 5. Phase 2a loguru sink at ui_configure | Medium | High | Medium (threading) | Done |
| 6. Phase 2b litellm.suppress_debug_info | Tiny | High | Low | Done |
| 7. Phase 2c structured dedup | Small | Medium | Low | Done |
| 8. Tests (Phase 1 + Phase 2) | Medium | - | - | Done |
| 9. TUI prefix polish | Small | Nice | Low | Optional |

### PR split

1. **PR A:** Phase 0 + Phase 1 + tool-kind decision + tests (fixes answer/reasoning bleed)
2. **PR B:** Phase 2 (loguru sink + litellm flag + dedup) + tests (fixes byllm/litellm bleed)
3. **(optional) PR C:** Phase 3 StderrRelay defense-in-depth

---

## Testing matrix

| Scenario | Assert |
|----------|--------|
| TUI mode + streaming answer | stdout empty; bus has `answer` events; IPC frame reaches sidecar |
| TUI mode + verbose reasoning | no stdout; bus has `reasoning` events |
| OpenRouter 500 | one `error` event in transcript; no loguru line on terminal |
| Auth failure | `needs_key=1` frame + `error` event; no duplicate stderr |
| Non-TUI `jac ai` | stdout/stderr behavior unchanged |
| `jac ai --ui` web | same bus events; no web regression (child already redirects fds) |

---

## Non-goals (for now)

- Capturing sidecar debug stderr into transcript
- New IPC event kinds (`log`, `stderr`) - use existing `error`/`system`
- Redirecting `/dev/tty` on the Python parent process
- Silencing errors entirely - they should appear in transcript, not vanish

---

## Success criteria

A failed OpenRouter call during `jac ai --tui` should show **only** in the
framed transcript - exactly one `error` row (deduped across the loguru sink and
the worker's except path; wording unified in Phase 2c), e.g.:

```
│ ! provider: LLM call failed with APIError: ... │
```

Nothing should print through the raw terminal underneath the alt screen.

---

## Key file references

| File | Role |
|------|------|
| `jac/jaclang/cli/impl/ai_agent.impl.jac` | `_term_output_enabled`, `render_stream`, `ui_configure` (boot seam), `route_stream_event` |
| `jac-super/jac_super/ai_agent/impl/run_tui_session.impl.jac` | Sets UI-mode flag, spawns sidecar, IPC |
| `jac-byllm/byllm/llm.impl/model.impl.jac` | `logger.error` on LLM failures (left untouched - loguru sink handles capture) |
| `jac-super/jac_super/ai_tui/PROTOCOL.md` | Frame format + kind enum (only touched if tool-kind decision = (a)) |
| `jac-super/jac_super/ai_tui_na/feed.na.jac` | Transcript rendering, event-prefix mapping |
| `jac-super/jac_super/ai_tui_na/screen.na.jac` | Colored transcript rows |
| `jac-byllm/tests/test_ai_agent.jac` | `capturing()` helper for stdout tests |
| `jac-super/tests/test_ai_tui_bridge.jac` | TUI session / IPC tests (env-var assertion to update) |

## Related plans

- `PLAN.md` - NA TUI architecture (pi-inspired renderer, libc tty, component spine)
- `jac-super/jac_super/ai_tui/PROTOCOL.md` - IPC contract (only change if the tool-kind decision requires it)

## Status log

| Date | Step | Notes |
|------|------|-------|
| 2026-06-18 | 7 | **Phase 2c complete:** bidirectional provider-error dedup (`_ui_provider_fingerprint` strips `provider:` and `LLM …Error:` labels; `_ui_bus_emit_guarded` remembers sink emits; worker/`render_stream` except paths check before emit). Commit `f4fb377ee`. |
| 2026-06-18 | 8 | **Tests complete:** `test_ai_tui_bridge.jac` covers loguru-before-worker dedup ordering, single loguru handler after `logger.remove()`, and `litellm.suppress_debug_info` gate. Step 8 closes the Phase 1 + Phase 2 test matrix for this plan. |
