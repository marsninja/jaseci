# Plan: Move the NA TUI in-process with the agent (sv) server

> **Context:** Today `jac ai --tui` runs as **two OS processes** - the `jac ai`
> Python/sv control plane (agent loop, bus, `ui_stream()`) and a sidecar binary
> `jac-na-tui` (libc FFI, ANSI render, keyboard), glued by a frozen text
> protocol over pipes (`PROTOCOL.md`). The control plane and sidecar share no
> memory; frames go child.stdin → child, commands come back child fd3 → parent.
>
> **Goal:** Collapse the two processes into one. Load the NA TUI as an
> **in-process native module** driven directly by the sv agent control plane via
> the `sv ↔ na` bridge (docs.jaseci.org/internals/interop, rows 7/8 JIT or row
> 13 AOT). Keep a clean, frozen communication seam so the agent and the TUI still
> evolve independently and a future external renderer can still speak the text
> protocol.
>
> **Status:** Design validated by spike (2026-06-18). The load-bearing
> integration unknowns are resolved: `nacompile --shared` + `ctypes.CDLL` under
> CPython works (after a one-line-class compiler fix, §11.1), and the na→sv
> direction is done with a **pull-based command queue** rather than callback
> pointers (§4/§5) - which the AOT path does not support and does not need.
> Remaining decisions in §15 are policy (fallback default), not feasibility.
>
> **Backend:** NA sidecar (`jac-super/jac_super/ai_tui_na/`) + a new sv-side
> host module under `jac_super/ai_agent/`.

Reference: `jac-super/jac_super/ai_tui/ARCHITECTURE.md`,
`PROTOCOL.md`, `PORTING.md`; interop matrix in
`docs/docs/internals/interop.md`.

---

## 1. Threat model: the Textual objection is dead, but it was never the real one

`ARCHITECTURE.md` lists the original reason for subprocess separation:

> *"Python TUI (Textual) event loop conflicted with the byLLM async agent
> loop."*

**Correction grounded in the code:** there is **no asyncio anywhere** in this
control plane. The agent runs synchronously in per-turn **daemon threads**
(`ui_send` → `threading.Thread(target=_ui_turn_worker, …, daemon=True).start()`,
`ai_agent.impl.jac:3144`); the bus is a plain `queue.Queue`; `ui_stream()` is a
blocking generator on `q.get(timeout=3.0)` (`ai_agent.impl.jac:3297`). So the
"two event loops fighting on one interpreter" problem **never existed in this
codebase**. The in-process design does not introduce a second event loop either

- it adds one extra **plain blocking thread** that drives the native renderer
through ctypes.

The GIL mechanics that make that thread *workable* are real:

1. **ctypes `CDLL` foreign calls release the GIL** for the duration of the
   native call. The native `poll(50ms)` does *not* hold the GIL - the byLLM
   turn thread keeps running. The 50 ms is spent in native `poll(2)`, GIL-free.
2. **There is no native→Python callback.** When the user hits Enter, native
   enqueues `"SEND:…"` into a module-glob command queue; the ticker thread (which
   made the ctypes call and already holds the GIL on return) pulls it via
   `tui_next_command()` and runs `ui_send(prompt)` (a cheap enqueue). No GIL
   re-acquisition from foreign code, no callback-pointer lifetime to manage.

**But the GIL is not the hard part, and "responsiveness of a separate process"
is the wrong claim.** Going in-process gives up three things the subprocess
model provided for free, and *adds* coupling the subprocess model did not have:

- **Scheduling coupling (perf):** the subprocess renderer has its own OS
  scheduler, fully immune to CPython. In-process, render/echo tail-latency
  becomes coupled to **GIL contention** with the byLLM turn thread (pure-Python
  token/markdown work) and to the **new render lock** (§9). The native calls are
  GIL-free, but the Python glue around them is not. This can make input latency
  under load *worse*, not better - see §9.
- **Crash isolation (correctness):** a fault in the native renderer used to kill
  only the sidecar; now it kills the whole `jac ai` process, losing the agent,
  the conversation, and any in-flight turn. The native layer does raw libc FFI
  with manual `calloc`+`memset` for `pollfd`/`termios` and has a documented
  history of memory-corruption bugs (NUL-drop in `chr()`+concat). See §12.
- **fd/tty separation (correctness):** the sidecar remapped its fds so the
  agent's stdout never touched the renderer's tty. In-process there is one set
  of fds; any stray write to stdout/stderr corrupts the alt-screen. See §12.

**Honest motivation.** The win from in-process is *not* performance - it is
operational: no first-run compile latency, no `setsid`/`JAC_AI_TUI_TTY`
plumbing, no fd-3 remap, one shipped artifact instead of a spawned binary. The
plan should be justified on those grounds, and must pay explicitly for the three
costs above (§9, §12) rather than assume the subprocess boundary "was paying for
a problem we no longer have."

---

## 2. Target architecture (one process)

```
┌─────────────────────────────────────────────────────────────────────┐
│  jac ai --tui   (single OS process; sv codespace + JIT/AOT na TUI)   │
│                                                                      │
│  ┌──────────────────────────────┐    ┌────────────────────────────┐ │
│  │  sv control plane            │    │  na TUI module (libtui.so) │ │
│  │  (Python; agent + bus)       │    │  (JIT'd in-proc, or CDLL)  │ │
│  │                              │    │                            │ │
│  │  agent.bus / ui_stream()     │    │  TuiState, feed, screen,   │ │
│  │  ui_send/stop/reset/apply    │    │  diff, editor, overlay,    │ │
│  │  byLLM loop (sync threads)   │    │  libc_tty (poll/read/write)│ │
│  │                              │    │                            │ │
│  │  run_tui_in_process:         │    │  :pub tui_init(...)        │ │
│  │    feeder thread ──frame──►  │────│► tui_apply_frame(blob)     │ │
│  │    ticker thread ──tick───►  │────│► tui_wait_key(50ms)/handle │ │
│  │                              │    │  tui_render()              │ │
│  │  ◄──pull next_command()───── │◄───│  cmd queue (obj glob)      │ │
│  │      (str return, drained)   │    │  tui_quit_requested()      │ │
│  └──────────────────────────────┘    └─────────────┬──────────────┘ │
│                                                    │ fd ≥ 10        │
│                                                    │ (tty, not 0/1) │
└────────────────────────────────────────────────────┼────────────────┘
                                                     ▼
                                        /dev/pts/N  (keyboard + ANSI)
```

- **Frames** (parent → child stdin) become a ctypes call
  `tui_apply_frame(blob: str)` where `blob` is the **exact same `KEY:VALUE\n…\n---`
  text** `_write_frame` emits today. Native parses it with the same grammar.
- **Commands** (child fd3 → parent) become a **pull queue**: native enqueues the
  command string into a module-glob `CmdQueue` (an `obj`), and the host drains it
  via `tui_next_command() -> str` after each key dispatch. The command string is
  the **exact same `SEND:`/`STOP`/`RESET`/`QUIT`/`APPLY:` text**. (Native does
  *not* call back into the host via a function pointer - the AOT `.so` path has no
  supported mechanism for that, and the pull queue is simpler; see §4.)
- The **TTY is still opened directly by native** (`tty_open` → fd ≥ 10) and all
  rendering/keyboard stays in libc FFI. The sv process keeps its own stdout/stderr
  for logs (gated by `JAC_AI_UI_ACTIVE=1`, as today).

This is the interop matrix's **`sv → na`** (row 7: sv calls native `:pub`
exports through a ctypes trampoline) and **`na → sv`** (row 8: native calls
Python functions registered as JIT/`add_symbol` symbols, or via callback pointers
passed at init) - both inside one address space, "two ctypes hops" as the doc
puts it.

---

## 3. The keystone insight: the text protocol is the in-process API

The lowest-risk migration preserves the **byte-for-byte frame and command
grammar** and only swaps the transport. Concretely:

| Today (pipes)                         | In-process (ctypes)                        |
| ------------------------------------- | ------------------------------------------ |
| `_write_frame(proc.stdin, frame)`     | `tui_apply_frame(_frame_blob(frame))`      |
| `for line in proc.stdout: dispatch`   | host drains `tui_next_command()` after key |
| `tty_read_line()` (reads stdin fd 0)  | parse the blob string passed in            |
| `ipc_send_cmd(fd, "SEND:…")`          | enqueue "SEND:…" into the native cmd queue |
| `proc.wait()`                         | `tui_wait_key(50)` + `tui_handle_key(k)` (§5) |

Net change to the native parser (`ipc.na.jac`): split `ipc_read_frame_v2` into
`ipc_parse_frame(state, blob)` that iterates `blob.split("\n")` instead of
calling `tty_read_line()`. The existing `_parse_ev_val` / `ipc_apply_line` /
`_unescape` logic is **reused unchanged**. The control plane's `_ev_line`,
`_esc_text`, `_write_frame`-assembly logic is **reused unchanged** - it just
joins into a string and hands it to ctypes instead of a pipe.

This keeps `PROTOCOL.md` authoritative: the *logical* protocol (frame fields,
command set, escaping, upsert-by-id invariants) is identical. Only the
"Transport" section changes. A future external renderer can still speak the text
protocol over pipes; the in-process path is the zero-copy fast path.

---

## 4. Bridge mechanism: AOT `.so` + ctypes (primary), JIT mixed-file (alternative)

The interop doc offers two ways to put native code in-process. Both are valid;
we pick one as primary.

### Primary: AOT shared library (`jac nacompile --shared`) + thin ctypes shim

`jac nacompile tui.na.jac --shared -o libtui.so` emits a C-ABI `.so` whose
`:pub` surface is the TUI API. The sv side `ctypes.CDLL`s it.

- **Why primary:** deterministic build, **no LLVM/llvmlite at agent runtime**
  (the TUI builds once, ships as an artifact), the TUI already builds via
  `jac nacompile` so `--shared` is a one-flag delta, the ctypes binding is ~50
  lines of auditable Python, and it is exactly the documented row-13 pattern
  (`na → C host`, consumed from Python via ctypes).
- **na → sv direction: a pull queue, not callbacks.** The interop doc only
  documents native→Python callbacks via the JIT `llvm.add_symbol` path (row 8);
  an AOT `.so` loaded by foreign ctypes has **no supported way to invoke a host
  function pointer** passed at init (the "C → Jac callbacks" vtable mechanism is
  the *reverse* direction). So instead of `on_command`/`on_quit` callbacks,
  native **enqueues** command strings into a module-glob `CmdQueue` (an `obj`),
  and the host **pulls** them via `tui_next_command() -> str` (returns `""` when
  drained) and `tui_quit_requested() -> int`, called by the ticker right after
  `tui_handle_key` while it still holds the render lock. This is strictly
  simpler than callbacks: no `CFUNCTYPE` keep-alive footgun, no callback
  reentrancy, and no render-lock→bus-lock ordering hazard (the old §9/§16 risks
  evaporate). **Spike-validated 2026-06-18:** frame blob crosses in via
  `c_char_p`, commands return via `str` (`c_char_p`), multibyte UTF-8 survives
  both directions, the queue drains and refills across calls.
- **Object lifetime:** the TUI owns its own `TuiState` in native memory (a
  module-level `glob`); it never crosses the ABI as a Jac object, so no
  `jac_retain`/`jac_release` dance is needed. Only scalars + the frame `str`
  (c_char_p) cross. This sidesteps the `NativeStructView`/handle machinery
  entirely - a big simplification.

### Alternative: mixed-file JIT (rows 7/8, `llvm.add_symbol` callbacks)

A `.sv.jac`/default module imports the `.na.jac` TUI module; the compiler
auto-synthesizes the ctypes trampolines (`PyastGenPass._gen_native_interop_stubs`)
and `interop_bridge.register_py_callbacks` wires na→sv Python callbacks via
`llvm.add_symbol` at engine creation. No hand-written ctypes.

- **Why not primary:** requires LLVM at runtime (slower agent cold-start, larger
  dependency surface), and the auto-bridge is harder to debug than 50 lines of
  explicit ctypes. It is the more "integrated" choice and pairs best with a
  future where the TUI ships as part of the `sv` graph rather than as a separate
  build artifact. **Revisit if/when we want the compiler to own the seam.**

> **Decision needed (§15-A):** AOT `.so` + ctypes (recommended) vs JIT
> mixed-file. The rest of the plan is written for the AOT path; the JIT path
> changes only the binding layer (§6, §8), not the TUI source or the protocol.

---

## 5. The in-process TUI API (the new frozen seam)

New `:pub` exports on the native side (file: `ai_tui_na/host.na.jac`, the
**only** file the sv side talks to). Everything else stays internal:

```jac
# host.na.jac  - the C-ABI surface the sv host dlopens.
# Scalars by value; str (c_char_p) for the frame blob. TuiState lives in native
# memory as a module glob and never crosses the ABI.

# One-time setup. No callback pointers - na → sv is a pull queue (see below).
# Returns 0 on success, non-zero error code otherwise. Idempotent: a second
# call re-inits.
def:pub tui_init(
    project: str,
    files_env: str,        # newline-separated file list (same as JAC_AI_UI_FILES)
    presets_env: str,      # newline-separated model presets
    tty_dev: str           # /dev/pts/N or "" for /dev/tty default
) -> int;

# Apply one frame. `blob` is the exact KEY:VALUE\n…\n--- text from PROTOCOL.md.
# Parses into the in-process TuiState. Thread-safe vs tui_render (host holds the
# lock; see §9). Returns 0 on a clean parse.
def:pub tui_apply_frame(blob: str) -> int;

# Block on poll(2) over the tty fd for up to `timeout_ms`. PURE I/O: does NOT
# touch TuiState, does NOT dispatch, does NOT render - it only waits for a byte
# and reads the raw key sequence into a caller-owned scratch buffer. Safe to call
# LOCK-FREE (the GIL is released for the poll). Returns the number of key bytes
# available (0 on timeout, -1 on tty error). The bytes are retrieved by the host
# and handed to tui_handle_key under the lock. See §9 for why poll and dispatch
# must be separated.
def:pub tui_wait_key(timeout_ms: int) -> int;

# Apply one keystroke to TuiState (scroll, overlay, prompt edit, etc.) and maybe
# enqueue a command into the native CmdQueue. MUTATES TuiState - the host MUST
# hold the render lock around this (it races tui_apply_frame and tui_render
# otherwise; handle_key takes the whole `state`). Returns 1 if the key requested
# quit, 0 otherwise.
def:pub tui_handle_key() -> int;

# Drain the native command queue, one command per call (FIFO), "" when empty.
# The host calls this in a loop right after tui_handle_key, still under the
# render lock, and feeds each line to _dispatch_cmd. The returned str is a fresh
# heap allocation read immediately by ctypes (c_char_p); small per-keystroke
# leak is acceptable for v1 (§16). The queue + its read cursor live in an obj
# glob (NOT a bare scalar glob - those don't persist across calls in NA; §9).
def:pub tui_next_command() -> str;

# 1 if the user requested quit (QUIT command / quit key), else 0. Polled by the
# ticker so quit needs no callback.
def:pub tui_quit_requested() -> int;

# Render if dirty. Walks keyboard-driven state changes + the last applied frame,
# runs screen_render → diff_engine.paint to the tty fd. Host holds the lock
# around this + tui_apply_frame + tui_handle_key. Returns 1 if it painted, 0 if
# nothing changed.
def:pub tui_render() -> int;

# Tear down: leave alt screen, restore termios, close tty. Safe to call once.
def:pub tui_shutdown() -> int;
```

**Why three calls instead of one `tui_tick` (and why `tui_wait_key` ≠
`tui_handle_key`):** the original single-threaded native loop (`tui.na.jac`)
did `poll → handle_key → apply_frame → render` on **one thread**, so it needed
no locks. Splitting the loop across the feeder and ticker Python threads (§8)
makes `TuiState` shared, so every *mutation* of it must be serialized. The
**only** operation that is genuinely safe lock-free is the bare `poll(2)` wait,
because it touches just the tty fd. Key *dispatch* (`handle_key`) mutates scroll
position, overlay state, and the prompt buffer - all of which `screen_render`
reads - so it must run under the lock. Hence:

- `tui_wait_key(50)` - lock-free, GIL-released, blocks the ticker for ≤50 ms
  without blocking the feeder.
- `tui_handle_key()` / `tui_apply_frame()` / `tui_render()` - all under the one
  render lock, because all three read or write `TuiState`.

A previous draft combined poll + dispatch into one `tui_poll_keys` call and
declared it "lock-free." That is a **data race**: it has `handle_key` mutating
`TuiState` with no lock while the ticker renders and the feeder applies frames.
Combining poll with *render* is harmless (both could be locked); combining poll
with *dispatch* is the dangerous pair. See §9.

**Command contract (na → sv), pull model:**

```python
# sv side (Python) - ticker thread, inside the render lock, after handle_key:
while True:
    cmd_b = host.next_command()              # c_char_p; b"" when drained
    if not cmd_b:
        break
    _dispatch_cmd(cmd_b.decode("utf-8", "replace"))  # reuse today's dispatcher
if host.quit_requested():
    stop_evt.set()
```

`_dispatch_cmd` is **reused verbatim** from `run_tui_session.impl.jac` - it
already maps `SEND:`/`STOP`/`RESET`/`QUIT`/`APPLY:` onto `ui_send`/`ui_stop`/
`ui_reset`/`ui_apply_settings`. The only edit: drop the `proc.terminate()` arm
of `QUIT` (there is no process to terminate; quit is signalled via
`tui_quit_requested()` → `stop_evt`).

No `ctypes.CFUNCTYPE`, no keep-alive globals, no native→host call: the queue is
drained by the same thread that dispatched the key, so there is no callback
reentrancy and no second lock acquired from inside native code.

The frozen seam is therefore:

- **In:** one frame blob (`str`) per `ui_stream()` emit - same grammar as
  `PROTOCOL.md` "Frames".
- **Out:** command lines pulled from `tui_next_command()` after each key - same
  set as `PROTOCOL.md` "Commands".

Both directions are spec-identical to today; only the carrier changed.

---

## 6. File changes

### Native side (`jac-super/jac_super/ai_tui_na/`)

| File | Change |
|------|--------|
| **`host.na.jac`** (new) | The `:pub` surface in §5. Holds the module-glob `TuiState` + `DiffEngine`. Orchestrates init/poll/render/shutdown. This replaces `tui.na.jac`'s `with entry { _run() }` main loop with host-driven entry points. |
| `tui.na.jac` | Keep as the **subprocess binary entry** (fallback renderer, §13). Factor `_run`'s body so `host.na.jac` and `tui.na.jac` share the same init/render/shutdown helpers - no duplication. |
| `ipc.na.jac` | Add `ipc_parse_frame(state, blob: str)` (iterates `blob.split("\n")`). `ipc_read_frame_v2` (pipe version) stays for the subprocess fallback. `ipc_send_cmd` gains a no-fd form that **appends to the module-glob `CmdQueue`** instead of writing a pipe. |
| `libc_tty.na.jac` | **Remove** `tty_init_stdio_remap` / `tty_restore_stdio` / `tty_ipc_fd` / the `dup2(1,3)` dance from the in-process path - there is no IPC stdin and no fd-3. `tty_open` keeps opening the tty and relocating to fd ≥ 10 (the relocation logic at `tty_open:153-160` stays - harmless without IPC, keeps us clear of stdio). `_tty_device_path` prefers `/dev/tty` first (we're the foreground session leader now, no `setsid`). Keep the pipe-oriented helpers for the subprocess build. |
| `commands.na.jac`, `input.na.jac`, `overlay.na.jac` | `run_command`/`apply_model`/`handle_key` currently take `ipc_fd: int`. Replace the `ipc_fd` param with an enqueue into the `CmdQueue` glob (or a `TuiState`-level `ipc_fd=-1` sentinel that means "enqueue, don't write fd"). Mutable queue state must be **object fields, never bare scalar globs** (§9). |
| `build.sh` | Add `--shared` target: `jac nacompile tui.na.jac --shared -o bin/libtui.so` (entry-point binary stays for fallback). Keep `--quick`. |
| `test_pickers.na.jac` | Unchanged (pure logic, no TTY). |

### sv side (`jac-super/jac_super/ai_agent/`)

| File | Change |
|------|--------|
| **`tui_host.impl.jac`** (new) | The ctypes binding: `ctypes.CDLL(libtui.so)`, `restype`/`argtypes` for the **eight** exports (`tui_init`, `tui_apply_frame`, `tui_wait_key`, `tui_handle_key`, `tui_next_command`, `tui_quit_requested`, `tui_render`, `tui_shutdown`), and `_dispatch_cmd` (moved here from `run_tui_session.impl.jac`). No `CFUNCTYPE`/keep-alive globals - na → sv is the pull queue. Exposes `TuiHost` with `init/apply_frame/wait_key/handle_key/next_command/quit_requested/render/shutdown`. |
| **`run_tui_in_process.impl.jac`** (new) | The replacement for `run_tui_session` for the in-process path. Owns the feeder + ticker threads, the lock, the lifecycle, env setup (`JAC_AI_UI_*`), `ui_configure`/`ui_stop`, **and the real-fd stdout/stderr redirect** (§12) for the TUI's lifetime. See §8. |
| `run_tui_session.impl.jac` | Keep as the **subprocess fallback** path (§13), selected by `JAC_AI_TUI_BACKEND=subprocess`. `_dispatch_cmd` moves to a shared helper both paths import. |
| `impl/plugin.impl.jac` | `run_ai_agent` chooses in-process vs subprocess via env/flag; default = in-process. |
| `ai_agent.jac` / `agent_api.jac` | No change to the `ui_*` API - both TUI backends consume the same in-process agent surface. |

### Docs

| File | Change |
|------|--------|
| `ai_tui/PROTOCOL.md` | Add **"In-process transport"** section: the frame blob is passed to `tui_apply_frame`; commands are pulled via `tui_next_command()`. Frame/command grammar unchanged. Note the subprocess transport remains a valid alternative. |
| `ai_tui/ARCHITECTURE.md` | New "Process model (in-process)" diagram (§2 above); mark the subprocess model as the fallback. Update the "Why subprocess" table to "Why in-process now" (§1). |
| `ai_tui/PORTING.md` | In-process path inherits the same Linux/WSL-only libc_tty constraint; no change to the porting story. |

---

## 7. What gets removed / simplified

Going in-process **deletes** the most fragile parts of the current design:

- `subprocess.Popen(..., start_new_session=True)` and the `setsid`-driven need
  for `JAC_AI_TUI_TTY` (we're the foreground session; `/dev/tty` works).
- The entire **stdio remap** (`dup2(1,3)`, `dup2(2,1)`, `tty_init_stdio_remap`,
  `tty_restore_stdio`, `tty_ipc_fd`). There is no IPC stdin and no command pipe.
- The **fd-3 collision workaround** in `tty_open` (the `dup2(fd, 10)` dance
  exists *because* fd 3 was reserved for IPC; with no IPC, fd 3 is free, though
  we still relocate to ≥ 10 to stay clear of stdio).
- `proc.stdin`/`proc.stdout` pipe buffering and `bufsize=1` text-mode framing.
- `_ensure_tui_binary`'s "compile on first run" latency (the `.so` is built at
  package/install time; `_ensure_tui_lib` just `dlopen`s).

> **Caveat - not a pure deletion.** Removing the `dup2(1,3)`/`dup2(2,1)` remap
> deletes the *IPC* fd plumbing, but it does **not** mean the agent's stdout/
> stderr are now harmless. They were protected precisely *because* the renderer
> was a separate process. In-process you must add a (simpler) real-fd redirect of
> stdout/stderr away from the alt-screen tty (§12.2). Net fd complexity goes
> down, but it does not go to zero.

---

## 8. Control-plane rewrite: `run_tui_in_process`

Mirrors today's two-thread shape (feeder ≈ `stream_writer`, ticker ≈
`cmd_reader` + `proc.wait`), but both threads call into the same `TuiHost`:

```python
# Sketch - run_tui_in_process.impl.jac
def run_tui_in_process(req) -> int:
    ui_configure()
    host = TuiHost(lib_path=_ensure_tui_lib(pkg_root))
    stop_evt = threading.Event()
    lock = threading.Lock()

    host.init(
        project=agent.ws.cwd,
        files_env=_list_project_files(agent.ws.cwd),   # reused helper
        presets_env="\n".join(_MODEL_PRESETS),
        tty_dev=_foreground_tty(),                      # "" -> /dev/tty
    )

    def _feeder():
        try:
            for frame in ui_stream():
                if stop_evt.is_set(): break
                if frame.get("heartbeat"): continue
                blob = _frame_blob(frame)               # reused from _write_frame
                with lock:
                    host.apply_frame(blob)
        finally:
            pass

    def _ticker():
        while not stop_evt.is_set():
            n = host.wait_key(50)       # lock-free, GIL-released ≤50 ms poll(2)
            cmds = []; quit = False
            with lock:                  # handle_key + drain + render under lock
                if n > 0:
                    host.handle_key()       # mutates TuiState; may enqueue cmds
                    while True:             # drain queue into a local list
                        cmd = host.next_command()   # "" when empty
                        if not cmd:
                            break
                        cmds.append(cmd)
                    quit = bool(host.quit_requested())
                host.render()
            # Dispatch OUTSIDE the render lock: _dispatch_cmd → ui_send takes
            # bus._lock, and we must never hold render-lock while taking it.
            for cmd in cmds:
                _dispatch_cmd(cmd, stop_evt)
            if quit:
                stop_evt.set()

    ft = threading.Thread(target=_feeder,  daemon=True)
    tt = threading.Thread(target=_ticker, daemon=True)
    ft.start(); tt.start()
    try:
        tt.join()            # ticker exits when stop_evt set (quit / interrupt)
    except KeyboardInterrupt:
        stop_evt.set()
    finally:
        stop_evt.set()
        try: ui_stop()
        except Exception: pass
        with lock:
            host.shutdown()
    return 0
```

Notes:

- `_frame_blob` is the body of today's `_write_frame` (`"\n".join(parts)`) -
  **reused**, just not flushed to a pipe.
- `_dispatch_cmd` is today's dispatcher minus the `proc.terminate()` arm.
- `_list_project_files` is reused unchanged (filesystem stays in the control
  plane - the native side still does no FS FFI, preserving the documented
  principle).
- `ui_stream()` is a blocking generator (`q.get(timeout=3.0)`); the feeder
  thread blocks on it exactly as `stream_writer` does today. Heartbeats are
  skipped on both paths.
- **Lock ordering: no longer a hazard.** Commands are drained into a local list
  *under* the render lock but **dispatched after releasing it**, so the
  `_dispatch_cmd` → `ui_send` → `bus._lock` path never runs while the render lock
  is held. The render lock and `bus._lock` are therefore never nested in either
  order. (The pull queue makes this possible; a synchronous native callback
  could not have dispatched outside the lock.) See §9.
- **Stray-output guard:** before `host.init`, redirect the process's own
  stdout/stderr away from the controlling tty for the TUI's lifetime (§12),
  because in-process there is no fd remap protecting the alt-screen.

---

## 9. Threading & GIL analysis (the part that has to be right)

| Concern | Resolution |
|---------|-----------|
| **All three of `apply_frame` / `handle_key` / `render` mutate-or-read `TuiState`** (feeder applies frames; ticker dispatches keys *and* renders) | One `threading.Lock` held around **all three**. The native loop was single-threaded and lock-free; splitting it across two Python threads makes `TuiState` shared, so every state-touching call is serialized. |
| Don't let the 50 ms poll block the feeder | Only `tui_wait_key` runs **lock-free** - it does pure `poll(2)` + raw read, touching just the tty fd, never `TuiState`. The lock is taken *after* the key is in hand, around `handle_key` + `render`. This is why poll and dispatch are **separate calls** (§5); combining them (the earlier `tui_poll_keys` draft) is a data race. |
| 50 ms poll freezing the agent | `host.wait_key` is a ctypes `CDLL` call → **GIL released** for the poll. The byLLM turn thread proceeds. |
| **GIL + lock contention degrading input latency** (the real perf risk) | During streaming, the byLLM turn thread holds the GIL doing token/markdown work, and the feeder holds the **render lock** across `apply_frame`. The ticker's `with lock: render()` then waits on *both*. So echo/render tail-latency is coupled to CPython scheduling - unlike the subprocess renderer, which had its own OS scheduler. Mitigations: (a) keep `apply_frame` cheap (it parses one small delta line in steady state); (b) if it bites, apply into a shadow `TuiState` and swap under a short lock so the lock is never held across a parse or a paint. Measured tuning, not a v1 blocker, but **must be benchmarked** before claiming parity with the subprocess path. |
| Command dispatch & lock ordering | Commands are **pulled** (`tui_next_command`) into a local list under the render lock, then `_dispatch_cmd` runs **after the lock is released** (§8). So `ui_send` → `bus._lock` is never taken while holding the render lock: the two locks are never nested. `_dispatch_cmd` must still **not** call back into the TUI (`apply_frame`/`render`) - it only touches the agent API. No `CFUNCTYPE` lifetime concern, since there is no native→host call. |
| **NA scalar-glob writes don't persist** (spike-confirmed) | A bare `glob g_cursor: int` write does **not** survive across `:pub` calls in NA codegen (reads return the initializer) - true in both `--shared` and executable builds. Object/list-field glob mutation *does* persist (the existing TUI relies on this: `g_tty.fd`, `TuiState` fields). **Rule:** the `CmdQueue` (items + read cursor) and all in-process mutable state live in `obj` glob fields, never bare scalar globs. |
| Feeder vs ticker ordering | A frame applied between two renders is picked up on the next `render()`; `state.dirty` is the gate, same as today. No new race once the lock covers all `TuiState` access. |
| Shutdown | `tui_quit_requested()` (polled by the ticker) / raw-mode QUIT key / `ui_stop` all set `stop_evt` (note: in raw mode Ctrl-C is **not** SIGINT - see §12 - so `except KeyboardInterrupt` is mostly dead; quit flows through the QUIT command). Ticker loop exits; feeder breaks on next `ui_stream()` yield. `host.shutdown()` runs under the lock, once. |
| SIGWINCH | Unchanged: `tui_render` re-reads `TIOCGWINSZ` each paint (today's `_sync_size`). A real signal handler is a separate enhancement, out of scope. |

This is the standard "Python thread + C extension that releases the GIL"
pattern (no native→host callback at all - na → sv is the pull queue) - but note
it converts lock-free single-threaded native code into shared state, so the
**lock must cover every `TuiState`-touching export** (`apply_frame`,
`handle_key`, `next_command`, `render`), and only the bare `poll(2)` wait stays
outside it.

---

## 10. What stays exactly the same

- The **frame grammar** and **command set** (`PROTOCOL.md`) - frozen seam.
- `libc_tty.na.jac` core: `tty_open`, `tty_update_size`, `tty_poll`,
  `tty_read_key`, `tty_write`, raw-termios builder, `TIOCGWINSZ`. (Only the
  stdio-remap helpers are dropped from the in-process path.)
- `terminal.na.jac`, `diff.na.jac`, `screen.na.jac`, `feed.na.jac`,
  `markdown.na.jac`, `tool_block.na.jac`, `editor.na.jac`, `overlay.na.jac`,
  `select_list.na.jac`, `state.na.jac`, `theme.na.jac`, `width.na.jac`,
  `component.na.jac` - **unchanged**. They don't know about the transport.
- The agent `ui_*` API and `ai_ui/server.jac` - untouched. The web UI and the
  in-process TUI are now just two consumers of the same in-process agent bus.
- `_list_project_files`, `_MODEL_PRESETS` plumbing, `JAC_AI_UI_*` env contract,
  loguru/litellm capture gating (`JAC_AI_UI_ACTIVE=1`).
- Linux/WSL-only platform story (`PORTING.md`).

---

## 11. Build, distribution, and first-run

### 11.1. Compiler prerequisite (DONE - ships as its own commit)

`ctypes.CDLL` of a `nacompile --shared` `.so` originally failed under a hardened
kernel with `OSError: cannot enable executable stack as shared object requires`.
Cause: nacompile's own ELF linker emitted **no `PT_GNU_STACK` program header**,
so Linux defaulted the `.so` to an executable stack and the loader refused it.
**Fixed** in `jac/jaclang/compiler/passes/native/impl/elf_linker.impl.jac`: add
`PT_GNU_STACK = 0x6474e551`, bump the shared-lib `num_phdrs` 4→5, and emit a
PT_GNU_STACK phdr (RW, fields 0) after PT_DYNAMIC. Executable path untouched.
This is a **compiler change, independent of the TUI**, and lands as its own
commit ahead of the TUI work. After the fix, the `.so` loads cleanly under
CPython 3.14 and `:pub` exports run correctly (spike-validated 2026-06-18). Note
the toolchain's earlier-feared init-order / `RTLD_NEXT` hang did **not** occur.

**Second `--shared` compiler fix (DONE 2026-06-18, found in Phase 1).** The spike
only built **single-module** `.so`s, so it missed this: in a real multi-module
`.so` (host.na.jac pulls in ~15 modules), every module emits its own copy of the
RC primitives, and LLVM internalises + collision-renames the duplicates
(`@__rc_retain` → `@__rc_retain.298`). The injected `jac_retain`/`jac_release`
wrappers (`nacompile.impl.jac` `_inject_shared_init`) called the **bare**
`@__rc_retain`, which after linking no longer exists → `LLVM IR verification
failed: use of undefined value '@__rc_retain'`. Fixed by matching the actual
`define`d symbol name (`_first_defined_rc_symbol`, regex over the linked IR) and
emitting the wrapper against that. Backward-compatible: the single-module fixture
(`tests/compiler/passes/native/test_shared_lib.jac`, 3 tests) still passes
because the regex also matches the un-renamed bare name. Another **compiler
change, independent of the TUI**.

**Native resolver is import-order sensitive (Phase-1 footgun, no compiler fix).**
The `.na.jac` cross-module type resolver walks types in the DFS order the ENTRY
module imports them; a leaf type first *seen* too deep resolves to `<Unknown>`
(`E5090 list[<Unknown>]` / `E2018`). Factoring `_run` behind `tui_core` shrank
`tui.na.jac`'s direct import set and pushed `select_list.SelectItem` (reached only
via `input → overlay`) too deep → build failed. Fix: keep the entry module
(`tui.na.jac`) **and** `host.na.jac` importing the same flat module set the
pre-refactor entry imported (libc_tty, terminal, state, ipc, screen, diff, input)
to PRIME the resolver into the proven-good order. Those imports are otherwise
unused but load-bearing - see the comment block in both files.

### 11.2. Build steps

- `build.sh` gains a `--shared` step → `bin/libtui.so` (host platform) via
  `jac nacompile tui.na.jac --shared`. The `:pub` surface is the §5 API.
- `_ensure_tui_lib(pkg_root)` (sv side) replaces `_ensure_tui_binary`:
  - If `bin/libtui.so` exists, `ctypes.CDLL` it.
  - Else, if `tui.na.jac` sources are present (dev tree), run `build.sh --shared`
    once (same "first run compiles" UX as today, gated by mtime as today).
  - Else, error with the same hint style as today.
- `JAC_AI_TUI_REBUILD=1` still forces a recompile (now of the `.so`).
- Installed packages ship `bin/libtui.so` next to where `bin/jac-na-tui` ships
  today; no LLVM at runtime for end users.

---

## 12. Backward compatibility & the fallback renderer

The "swappable renderer / frozen protocol" design goal (ARCHITECTURE.md §1,
PLAN.md principle 3) is preserved, not abandoned:

- `jac ai --tui` → **in-process** by default.
- `JAC_AI_TUI_BACKEND=subprocess` (or `--tui-backend subprocess`) → the existing
  `run_tui_session` spawns `bin/jac-na-tui` over pipes, exactly as today. This
  is the escape hatch if the in-process path regresses on a given platform, and
  it is the contract any **third-party renderer** would implement.
- Both backends share `_dispatch_cmd`, `_frame_blob`, `_list_project_files`, and
  the `ui_*` agent API - so the fallback is cheap to maintain.

The subprocess binary (`tui.na.jac`'s `with entry`) stays buildable and tested;
it is not deleted.

### Costs the subprocess model absorbed for free - and how in-process pays them

These are *not* listed in the original "why subprocess" table (which only cited
the bogus event-loop conflict, §1), but they are the substantive reasons the
process boundary had value. In-process must pay each one explicitly.

1. **Crash isolation.** A segfault in the native renderer used to kill only the
   sidecar; the agent process, conversation, and in-flight turn survived (and
   could re-spawn the renderer). In-process, **a fault in `libtui.so` kills the
   entire `jac ai` process.** The native layer is raw libc FFI with manual
   `calloc`+`memset` for `pollfd`/`termios` (it cannot use `chr()`+concat
   because that drops NUL bytes) and has a *documented history* of
   memory-corruption-class bugs. Co-locating exactly that code with agent state
   is the main robustness regression. Decision: either (a) keep the subprocess
   backend as the **default** until the native FFI is hardened and only opt into
   in-process, or (b) accept the coupling and treat any renderer fault as a
   session-fatal bug. The fallback flag (§15-B) makes (a) cheap.

2. **Stray stdout/stderr corrupting the alt-screen.** The sidecar remapped fds
   (`dup2(1,3)`, `dup2(2,1)`) so the agent's stdout never reached the renderer's
   tty. In-process there is **one** set of fds, and fd 1/2 *are* the terminal
   the TUI put into raw + alt-screen. Any uncaptured write - an unhandled
   exception traceback, a stray `print`, a litellm/urllib3 warning not on the
   `JAC_AI_UI_ACTIVE` capture list - scribbles directly onto the TUI. The
   `JAC_AI_UI_ACTIVE` capture is a *denylist* of known-noisy sources and is not
   sufficient. **Required:** `run_tui_in_process` must redirect the process's
   real stdout/stderr file descriptors (not just `sys.stdout`) away from the
   controlling tty for the TUI's lifetime - e.g. to the bus, a log file, or
   `/dev/null` - and restore them on shutdown. (§16 previously dismissed this as
   "fine"; it is not, because in-process fd 2 is the alt-screen tty, not a
   separate parent stderr.)

3. **Signals / job control.** The sidecar ran under `start_new_session=True`
   (its own session). In-process, the TUI shares the process and puts the
   terminal in raw mode, which clears `ISIG` - so **Ctrl-C does not raise
   SIGINT**; it arrives as a keystroke and must be handled as today via
   `STOP`/`QUIT` commands. The `except KeyboardInterrupt` arm in §8 is therefore
   mostly dead code under raw mode; keep it only as a belt-and-suspenders for the
   window before `tty_open` sets raw mode. SIGWINCH now arrives at the shared
   process but is handled by polling `TIOCGWINSZ` each paint, unchanged.

---

## 13. Phased rollout

Each phase ends in a working, testable state.

**Phase 0 - Refactor for shared entry (no behavior change).**
Split `tui.na.jac`'s `_run` into reusable `tui_setup` / `tui_loop_once` /
`tui_teardown` helpers. Add `ipc_parse_frame(state, blob)` alongside
`ipc_read_frame_v2`. Add the callback-send path in `ipc_send_cmd` (no-fd form).
Subprocess binary still builds and runs identically. *Gate: `build.sh` + manual
`jac ai --tui` smoke unchanged.*

**Phase 1 - `host.na.jac` + `libtui.so` build. - DONE 2026-06-18.**
Author the eight `:pub` exports over the Phase-0 helpers. `build.sh --shared`
produces `bin/libtui.so` (the `nacompile --shared` path emits a C-ABI `.so` with
`:pub` exports run via `__jac_shared_init`/`DT_INIT_ARRAY`). **The §16 ctypes-
load spike is already done** (2026-06-18): the only blocker was the missing
`PT_GNU_STACK` header, now fixed in the compiler (§11.1); there was no init-order
hang. With that fix in place, `libtui.so` loads under CPython and exports run.
Then write a headless harness
(`test_host.na.jac` or a Python ctypes script) that feeds a canned frame blob
and asserts `TuiState.events` populates - no TTY needed. *Gate: `libtui.so`
loads under CPython without an init-order hang, parses a blob, and `tui_render`
produces the expected screen lines into a memory buffer (refactor
`diff_engine.paint` to accept an fd OR a buffer for testability).*
> **Delivered:** `host.na.jac` exports nine `:pub` symbols (the eight in §5 plus a
> headless `tui_render_buf() -> str` for the gate). `diff.na.jac` `paint` now
> routes through `_emit(fd, …)`: `fd < 0` appends to an obj-glob `PaintBuf`
> (Decision §15-C). `build.sh` builds `bin/libtui.so` via
> `nacompile host.na.jac --shared -o bin/libtui.so` and runs `test_host.py`, a
> ctypes harness that `CDLL`s the `.so`, feeds a canned `full` frame, and asserts
> the event text appears in `tui_render_buf()` + the cmd queue drains empty - all
> with no TTY. Gate green: `build.sh` builds both the executable and the `.so` and
> passes pickers + host gate. Required two compiler fixes (§11.1) and the
> import-order priming (§11.1). The `na → sv` pull queue (`tui_next_command`) and
> the lock-free `tui_wait_key` / locked `tui_handle_key` split are in place for
> Phase 2's threads.

**Phase 2 - `tui_host.impl.jac` + `run_tui_in_process.impl.jac`. - DONE 2026-06-18.**
ctypes binding, callbacks, two threads, lifecycle. Wire `plugin.impl.jac` to
select it by default. Keep `run_tui_session` as the `subprocess` fallback.
*Gate: `jac ai --tui` runs fully in-process on a real terminal; keyboard,
streaming deltas, model picker, APPLY all work; Ctrl-C / QUIT clean up the tty.*
> **Delivered (sv side, `jac_super/ai_agent/`):**
>
> - `tui_shared.jac` - one copy of the wire grammar + plumbing both backends
>   import: `_frame_blob` (the old `_write_frame` body), `_ev_line`/`_esc_text`,
>   `_dispatch_cmd`, `_list_project_files`, `_sidecar_tty_device`, `_debug_log`.
>   `_dispatch_cmd(line, stop_evt, proc)` - `proc` is optional (`None` in-process;
>   the subprocess path still `terminate()`s on QUIT).
> - `tui_host.jac` - `TuiHost` ctypes binding (`CDLL` + restype/argtypes for the
>   eight `:pub` exports) + `_ensure_tui_lib`/`_tui_lib_path`. **Footgun:** Jac
>   reserves `def init` as the obj constructor, so the wrapper for `tui_init` is
>   named `start`, not `init`. No `CFUNCTYPE`/keep-alives - na→sv is the pull queue.
> - `run_tui_in_process.jac`/`.impl.jac` - feeder + ticker threads, render lock,
>   lifecycle, `JAC_AI_UI_*` env, and the §12.2 real-fd stdout/stderr→/dev/null
>   redirect for the TUI's lifetime (restored on shutdown). Commands drained under
>   the lock, dispatched after release (§9 lock-ordering).
> - `run_tui_session.impl.jac` - refactored to import the shared helpers (deleted
>   its local copies; `_write_frame` now wraps `_frame_blob`). Behavior unchanged.
> - `plugin.impl.jac` - `JAC_AI_TUI_BACKEND` selects backend. Per §15-D the
>   **default stays `subprocess`**; `JAC_AI_TUI_BACKEND=inprocess` opts in. Flip
>   the default once it soaks.
> - `tests/test_ai_tui_bridge.jac` updated for the new `_dispatch_cmd` arg order;
>   all 8 tests green (under a PTY).
>
> **Verified headlessly (maximal short of the interactive gate):** all five sv
> modules compile + load via the runtime; `_frame_blob` byte-grammar (full+delta);
> `TuiHost` binding against the real `libtui.so` (apply_frame/next_command/
> quit_requested/render); the driver's no-tty early-exit; and - against a real
> **PTY** - the full on-tty lifecycle (`start` opens tty/raw/alt-screen → render
> paints 3934 B of ANSI + both event texts to the tty → `wait_key` detects input
> → `handle_key` consumes it → `shutdown` clean) plus the na→sv pull queue (typing
> `hi`+Enter yields `SEND:hi`). **Still requires a human on a real terminal:** the
> full agent integration - `ui_stream` feeding live byLLM deltas, the model picker
> driving `APPLY`, and Ctrl-C/QUIT teardown - which needs a live TTY + API key.

**Phase 3 - Hardening & docs. - DONE 2026-06-18.**
Update `PROTOCOL.md` (in-process section), `ARCHITECTURE.md`,
`PORTING.md`. Add a `jac-super/tests/test_ai_tui_host.jac` that exercises
`TuiHost` against a mock tty (or the existing `proto/no_c_*.na.jac` smoke
pattern). Verify the `subprocess` fallback still passes
`test_ai_tui_bridge.jac`. *Gate: CI green; both backends pass.*
> **Delivered:**
>
> - **Docs.** `PROTOCOL.md` now splits Transport into *subprocess* + *in-process*
>   (same frame/command grammar; in-process passes the blob to `tui_apply_frame`
>   and pulls commands from `tui_next_command`), and the Startup / `QUIT` /
>   invariants sections note the in-process variant. `ARCHITECTURE.md` gains an
>   "In-process model" section (one-process diagram, the `TuiHost`/driver/shared
>   file map, the two-threads-one-lock rule, and the three costs in-process pays:
>   crash isolation, fd hygiene, signals) and the "Why subprocess" table now
>   records that in-process exists behind the flag (subprocess stays default per
>   §15-D). `BACKENDS.md` documents `JAC_AI_TUI_BACKEND` selection + the in-process
>   `libtui.so` backend. `PORTING.md` notes the in-process transport deletes the
>   spawn-side OS-fork surface (one surface to port, not two) and flips the
>   distribution shape to a per-OS shared library.
> - **Test.** `jac-super/tests/test_ai_tui_host.jac` (2 tests): (1) headless -
>   binds `libtui.so` via the real `TuiHost`, round-trips a `_frame_blob`-encoded
>   frame through the native parser, asserts the event text renders + the pull
>   queue starts drained + quit unset (the sv-side twin of `test_host.py`); (2)
>   real PTY - `openpty`, `start` on it, type `hi`+Enter into the controller, run
>   the ticker's wait_key→handle_key→next_command→render loop, assert it yields
>   `SEND:hi`. Both guard-skip if `libtui.so`/openpty are unavailable.
> - **Idempotency bug found + fixed (hardening).** The PTY test exposed that
>   `tui_init` reset events but **not** `status`/`active`/`model_name`/editor/
>   overlay, so a prior frame's `STATUS:running` survived a re-init and
>   `_handle_submit` (input.na.jac) silently dropped the next `SEND` - contra
>   `tui_init`'s "safe to call twice" contract. Fixed in `host.na.jac` `tui_init`
>   (now also clears the header/interactive state); `libtui.so` rebuilt.
> - **Verified:** native host gate (`test_host.py`) green; `test_ai_tui_host.jac`
>   2/2 (headless *and* under a PTY); `test_ai_tui_bridge.jac` 8/8 (subprocess
>   fallback unaffected - its `tui_setup` runs once per fresh process, no re-init
>   leak possible). Both backends pass.

---

## 14. Testing strategy

| Layer | How |
|-------|-----|
| Frame parse (no TTY) | `test_host` feeds canned `KEY:VALUE\n…\n---` blobs to `tui_apply_frame`, asserts `TuiState` fields + `screen_render` output. Reuses today's `ipc_parse_frame` semantics, so it doubles as a protocol-conformance test. |
| Command pull (no TTY) | Drive `tui_wait_key` + `tui_handle_key` against a fake key sequence injected into a mock tty; assert `tui_next_command()` drains the right `SEND:`/`STOP`/`APPLY:` lines in FIFO order and returns `""` when empty. |
| Render determinism | `diff_engine.paint` refactored to paint to a buffer in tests; snapshot the first-paint of a known event set. |
| Integration (real TTY) | Manual + the existing `proto/no_c_*.na.jac` smoke pattern under a PTY. |
| Fallback parity | `test_ai_tui_bridge.jac` continues to cover the subprocess path; a shared `_dispatch_cmd`/`_frame_blob` unit test proves both backends agree on grammar. |
| Agent-loop coexistence | A test that runs `ui_stream()` + the ticker while a fake byLLM turn emits events, asserting no GIL deadlock and frames are applied in order. |
| State-race / lock | Stress test: feeder applying frames while the ticker dispatches keys, run under TSan-equivalent scrutiny or a high-iteration loop asserting `TuiState` invariants (no torn reads in `screen_render`). Proves the lock covers `apply_frame` + `handle_key` + `render` and that only `wait_key` is lock-free. |
| Lock-ordering | Static/asserted check that command dispatch happens outside the render lock, so render-lock and `bus._lock` are never nested (§8/§9). |
| Stray-output containment | Force a `print`/traceback to fd 1/2 during a TUI session; assert it does **not** appear on the alt-screen (i.e. the §12.2 redirect is active). |
| Crash blast-radius | Inject a fault in `libtui.so` (or simulate) and document/verify the failure mode: subprocess backend survives; in-process backend is session-fatal (informs Decision §15-D). |

Native-side tests live in `ai_tui_na/` (built by `build.sh`, as today); sv-side
tests in `jac-super/tests/`.

---

## 15. Decisions needed before implementation

**A. Bridge mechanism. - RESOLVED: AOT `.so` + ctypes.** Spike-validated
(2026-06-18): the `.so` loads under CPython (after the §11.1 compiler fix) and
na → sv is a pull queue, not callbacks (§4). The JIT mixed-file path remains a
documented alternative but is not needed.

**B. Fallback policy.** Keep the subprocess `jac-na-tui` as a supported
fallback behind `JAC_AI_TUI_BACKEND=subprocess` (recommended; §12), or delete it
and go in-process only.

**C. Render target refactor.** Phase 1 needs `diff.na.jac`'s `paint(lines,
width, fd)` (actual signature, `diff.na.jac:68` - writes to `fd` via `tty_write`)
to optionally paint to an in-memory buffer for headless tests. Confirm we're OK
touching the signature (it's internal; the change is additive - e.g. `fd < 0`
means "append to a glob buffer").

**D. Default backend given the crash-isolation cost (§12.1).** The plan defaults
to in-process. Given that a native fault now kills the agent and the native FFI
has a memory-bug history, decide whether the **default** should stay subprocess
until the renderer has soaked in-process behind the flag, flipping the default
only once it's proven stable. Recommended: ship in-process behind
`JAC_AI_TUI_BACKEND=inprocess` first, keep subprocess default for one release,
then flip.

---

## 16. Risks & open questions

- **ctypes callback lifetime - N/A (eliminated).** The pull-queue design has no
  `CFUNCTYPE` callbacks crossing into native, so there is no keep-alive footgun.
  (This risk applied only to the abandoned callback-pointer design.)
- **NA scalar-glob writes don't persist (spike-confirmed footgun).** A bare
  `glob g_x: int` write does not survive across `:pub` calls (reads return the
  initializer); object/list-field glob mutation does persist. All in-process
  mutable state - the `CmdQueue`, cursors, dirty flags - must live in `obj` glob
  fields. The existing TUI already follows this; new host code must not regress
  it. See §9.
- **`str` across c_char_p:** the frame blob can be large (a `full` snapshot with
  many `EV:` lines). `c_char_p` copies the bytes both ways; for our frame sizes
  this is fine, but if snapshots grow we'd consider the zero-copy
  `NativeStructView` path (interop doc §"Crossing whole Jac values"). Out of
  scope for v1.
- **One TTY, two writers (corrected - this is a real hazard, see §12.2).** There
  is no longer a parent process whose stdout is separate from the renderer's tty:
  in-process, fd 1/2 *are* the alt-screen tty. `JAC_AI_UI_ACTIVE=1` only captures
  *known* sources (loguru/litellm); an unhandled traceback or stray `print` goes
  straight onto the TUI. Mitigation is mandatory, not optional: redirect the real
  stdout/stderr fds for the TUI's lifetime (§12.2). `_debug_log` writing to fd 2
  is **not** "fine" in-process - fd 2 is the controlling tty now.
- **Lock ordering deadlock - eliminated by the pull queue.** `bus._lock`
  (`ai_agent.impl.jac:2287`) is only taken by `_dispatch_cmd` → `ui_send`, which
  the ticker now runs **after releasing the render lock** (§8). The render lock
  and `bus._lock` are never nested in either direction, so there is no ordering
  invariant left to violate. (Worth a one-line review assertion that nothing
  reintroduces dispatch-under-lock.)
- **`ui_stream()` blocking shutdown:** the feeder thread blocks on the
  generator's `q.get(timeout=3.0)`. On quit it may linger up to 3 s before
  noticing `stop_evt`. Acceptable (daemon thread); if not, add a
  `bus.unsubscribe`-on-shutdown hook. Today's subprocess path has the same
  property.
- **Cross-platform: distribution shape flips from executable to shared
  library (new risk).** Today each platform ships a self-contained executable
  (`bin/jac-na-tui` / `…-darwin` / `.exe`) that `Popen` launches - a
  well-trodden packaging path. In-process ships a **dlopen'd shared library**
  per platform (`bin/libtui.so` / `libtui.dylib` / `tui.dll`), which has three
  distribution hazards the subprocess model did not:

  1. **macOS code-signing of a `.dylib` inside a pip wheel.** A `.dylib` on
     arm64 needs ad-hoc signing at minimum to load; if the wheel is ever
     notarized, the dylib is in scope of the notarization ticket. Executables
     in wheels are the common case; `.dylib` signing in pip wheels is less
     exercised and has bitten projects before. Plan: ad-hoc sign at build time
     (`codesign --sign -`), verify load on an arm64 Mac in CI, and decide
     up front whether the wheel is notarized (the executable had the same
     requirement, so this isn't strictly *new*, but `.dylib` is the less-
     trodden variant).
  2. **Windows DLL search path.** `ctypes.CDLL("tui.dll")` only resolves it if
     it's next to the loader or on `PATH`; a bare name silently fails with a
     cryptic `FileNotFoundError`. `_ensure_tui_lib` must compute an **absolute
     path** before the `CDLL` call on every platform (harmless on Linux/macOS,
     required on Windows). ~5 lines, but a new footgun vs `Popen([binary_path])`.
  3. **Per-OS artifact naming / selection.** `_resolve_tui_command()` today
     picks the executable from `sys.platform`. The same selector survives, but
     it now picks `libtui.so` / `libtui.dylib` / `tui.dll`. The Linux-hardcoded
     `import from "/usr/lib/libc.so.6"` in `libc_tty.na.jac` was already
     platform-specific (macOS would be `libSystem.dylib`, Windows a Console-API
     module with no libc at all), so this doesn't worsen the per-platform
     split - but it is the same fork-now-multiplied-across-a-shared-lib
     concern to keep in mind.

- **Cross-platform: porting effort changes shape (net positive, but not free).**
  Per `PORTING.md`, the subprocess design had **two** OS-forking surfaces: the
  TTY backend (`termios` vs Console API, struct layouts, key translation) and
  the spawn/session plumbing (`start_new_session`/`setsid`, `JAC_AI_TUI_TTY`,
  the `dup2` stdio remap, the fd-3 IPC workaround, ConPTY/handle-passing on
  Windows). The in-process plan **deletes the second surface entirely** -
  `PORTING.md`'s "Control plane (minor)" (macOS) and "Stdio remap on Windows" /
  ConPTY v1–v2 (Windows) sections simply stop applying. Concretely: the
  Windows port goes from "TTY backend **plus** a ConPTY/handle spawn layer" to
  "TTY backend only," and the macOS port drops its spawn-side delta. What does
  **not** get easier: the genuinely expensive TTY-backend work (Darwin
  `termios` re-derivation, Windows `console.win32.na.jac`, key-sequence
  translation, `width.na.jac` CJK assumptions) - the plan never forks below the
  transport seam by design. So `PORTING.md`'s "~1–2 weeks macOS, ~3–6 weeks
  Windows" estimates for the TTY backend stand; what changes is those weeks are
  spent on *only* the TTY backend, not TTY-backend-plus-spawn-plumbing. If
  cross-platform is a near-term goal, **sequencing the in-process swap before
  the macOS/Windows ports is a reasonable move** - you'd port one surface
  instead of two. The ctypes GIL/callback semantics are CPython-ABI guarantees,
  not OS-specific, so the threading model in §9 transfers unchanged.
- **`jac nacompile --shared` + dlopen-under-CPython - RESOLVED (spike done
  2026-06-18).** The flag emits a C-ABI `.so` with `:pub` exports run via
  `__jac_shared_init` / `DT_INIT_ARRAY` (`nacompile.jac:42`,
  `nacompile.impl.jac:96,235`). The feared init-order / `RTLD_NEXT` hang (the CEF
  prior art) did **not** materialize. The actual blocker was unrelated: the
  linker emitted no `PT_GNU_STACK` header, so the kernel refused the `dlopen`
  with `cannot enable executable stack`. Fixed in the compiler (§11.1). After the
  fix, `ctypes.CDLL('libtui.so')` loads cleanly under CPython 3.14, scalar args /
  `str` (`c_char_p`) cross both directions, multibyte UTF-8 survives, and an
  object-glob command queue persists across calls. The JIT mixed-file path (§4)
  and the subprocess default (§12.1) remain as fallbacks but are not needed for
  feasibility.
