"""Self-hosting TUI: the na binary IS the host; Python (the agent) is embedded.

Where host.na.jac is a `--shared` libtui.so that the Python `jac` CLI dlopens
(Python is the host, the renderer is the guest), this flips the polarity: the
nacompiled `jac-ai-tui` binary is the host and links the renderer as plain Jac,
while the agent (jaclang.cli.ai_agent.ui_stream) runs inside an EMBEDDED CPython
brought up by libjacpyembed -- the SAME fused runtime the desktop host uses.

Boundary map:
  * renderer (state/screen/input/ipc/diff/tui_core) -- LINKED Jac, no ctypes,
    runs on the `with entry` main thread, GIL NOT held;
  * agent (ui_stream + _frame_blob + _dispatch_cmd) -- EMBEDDED Python reached
    only through the `jpy_` forwarders (libjacpyembed), every call GIL-guarded.

The two threads that live in Python today (the subprocess backend's `_feeder` and
`_ticker`) collapse here: the render/input loop becomes this main thread, and the
agent's blocking ui_stream() generator runs on a daemon thread inside the
embedded interpreter, feeding a queue this loop drains under the GIL.

Build:  build_embed.sh   ->  bin/jac-ai-tui  (nacompiled executable + trailer)
"""

# Renderer: the SAME flat import block host.na.jac uses (keep it verbatim)
# The native cross-module type resolver is DFS-order sensitive and resolves leaf
# types (e.g. select_list.SelectItem, reached via input -> overlay) to <Unknown>
# if first seen too deep -- E5090/E2018. This block mirrors the proven-good order
# primed by tui.na.jac / host.na.jac; the libc_tty / terminal / screen symbols
# beyond what the loop uses are otherwise unused but REQUIRED to keep the build
# green. Do not prune them. Upstream fix tracked in jaseci-labs/jaseci#6793.
import from .libc_tty {
    tty_open,
    tty_open_dev,
    tty_close,
    tty_fd,
    tty_update_size,
    tty_rows,
    tty_cols,
    tty_x_pixels,
    tty_y_pixels,
    tty_poll,
    tty_stdin_ready,
    tty_key_ready,
    tty_read_key,
    tty_write,
    tty_init_stdio_remap,
    tty_restore_stdio,
    tty_ipc_fd
}
import from .terminal {
    term_enter_alt_screen,
    term_leave_alt_screen,
    term_hide_cursor,
    term_show_cursor,
    term_enable_mouse,
    term_disable_mouse
}
import from .state { TuiState }
import from .select_list { SelectList, SelectItem }
import from .ipc {
    ipc_read_frame_v2,
    ipc_send_cmd,
    ipc_parse_frame,
    ipc_next_command,
    ipc_clear_cmd_queue
}
import from .screen { screen_render }
import from .diff { DiffEngine, diff_take_buf }
import from .input { handle_key }
import from .terminal_image { term_hyperlink, image_rows }
import from .tui_core {
    tui_populate_state,
    tui_enter_screen,
    tui_leave_screen,
    tui_render_once,
    _sync_size
}

import os;

# Agent: the fused-runtime shim, IDENTICAL to _jacpyembed_import_block in
# _host_bootstrap.jac. The binary DT_NEEDEDs libjacpyembed (logical name,
# $ORIGIN-resolved); jac_engine_boot() materializes the trailer payload, dlopens
# THIS binary's bundled CPython and Py_Initialize()s it; the rest are jpy_-prefixed
# forwarders onto that interpreter (the prefix keeps the shim's exports from
# interposing libpython's own symbols under Linux's flat namespace).
import from jacpyembed {
    def jac_engine_boot -> i32;  def jpy_Py_Finalize -> None;  def jpy_PyRun_SimpleString(
        cmd: str
    ) -> i32;  def jpy_PyImport_AddModule(name: str) -> int;  def jpy_PyModule_GetDict(
        module: int
    ) -> int;  def jpy_PyRun_String(s: str, start: i32, g: int, l: int) -> int;  def jpy_PyEval_SaveThread -> int;  def jpy_PyEval_RestoreThread(
        s: int
    ) -> None;  def jpy_PyGILState_Ensure -> int;  def jpy_PyGILState_Release(
        state: int
    ) -> None;  def jpy_PyObject_CallOneArg(fn: int, arg: int) -> int;  def jpy_PyUnicode_FromString(
        s: str
    ) -> int;  def jpy_PyUnicode_AsUTF8(pyobj: int) -> str;  def jpy_Py_DecRef(
        pyobj: int
    ) -> None;
}

# Py_eval_input -- the same constant DISPATCH_PY uses for jpy_PyRun_String.
glob PY_EVAL: i32 = 258;

# Renderer state stays in module globs -- it never crosses the FFI boundary as a
# Jac object, so no jac_retain/jac_release dance. Pure construction is safe in
# glob init (no libc / no tty until the :pub-less `with entry` runs).
glob host_state: TuiState = TuiState(),
     host_diff: DiffEngine = DiffEngine();

# Env contract shared with the subprocess entry (tui.na.jac) and _configure_ui_env
# (tui_shared.jac): the control plane already exported these before launch.
glob proj = os.getenv("JAC_AI_UI_PROJECT");
glob files_env = os.getenv("JAC_AI_UI_FILES");
glob presets_env = os.getenv("JAC_AI_UI_MODEL_PRESETS");


# Runtime sys.path hook -- the TUI analogue of desktop's _scale_runtime_hook_py
# (_host_bootstrap.jac). The fused payload this binary carries is jaclang-only
# (the SAME one the desktop host boots): byllm + its LLM stack (litellm/openai/...)
# are deliberately NOT bundled. Rather than baking ~114MB into every binary, the
# embedded interpreter picks the agent backend up at RUNTIME from two portable env
# seams -- nothing about the build machine is baked in:
#   JAC_AI_TUI_BYLLM_SRC  -- editable jac-byllm checkout, sys.path.insert(0) (wins
#                            over any pip copy);
#   JAC_AI_TUI_DEPS       -- os.pathsep-separated dep dirs (litellm, openai, ...),
#                            appended.
# Absent both, the block is inert and the guarded import below surfaces a clean,
# directed error rather than a NameError cascade or a hang. This mirrors desktop's
# clean break from build-time dep-path baking exactly; bundling byllm into the
# fused runtime is the shared follow-up both targets defer.
def _byllm_runtime_hook_py -> str {
    return (
        "_byllm = os.environ.get('JAC_AI_TUI_BYLLM_SRC')\n" + "if _byllm and _byllm not in sys.path:\n" + "    sys.path.insert(0, _byllm)\n" + "_deps = os.environ.get('JAC_AI_TUI_DEPS', '')\n" + "if _deps:\n" + "    for _d in _deps.split(os.pathsep):\n" + "        if _d and _d not in sys.path:\n" + "            sys.path.append(_d)\n"
    );
}


# The embedded-Python bootstrap, the TUI analogue of DISPATCH_PY
# Real surface: wraps the agent's blocking ui_stream() generator (its own daemon
# thread) into a synchronous pull/push, reusing _frame_blob / _dispatch_cmd from
# tui_shared.jac VERBATIM so the wire grammar stays single-sourced with the
# subprocess backend. Each python source line ends with "\n" (statement
# separator); blob-internal line breaks are written "\\n" so the python string
# literal carries them as escapes the na ipc parser splits on.
def _agent_py_real -> str {
    return (
        "import os, sys, threading, queue\n" + _byllm_runtime_hook_py() + "try:\n" + "    from jaclang.cli.ai_agent import ui_configure, ui_stream, ui_stop\n" + "    from jaclang.cli.ai_tui.tui_shared import _frame_blob, _dispatch_cmd\n" + "except Exception as _e:\n" + "    sys.stderr.write('jac-ai-tui: embedded agent backend unavailable: ' + repr(_e) + '\\n')\n" + "    sys.stderr.write('  point the embedded interpreter at byllm: set JAC_AI_TUI_BYLLM_SRC=<jac-byllm checkout> and JAC_AI_TUI_DEPS=<dep dirs (litellm, openai, ...)>.\\n')\n" + "    raise\n" + "_q = queue.Queue()\n" + "_stop = threading.Event()\n" + "def _agent_setup():\n" + "    ui_configure()\n" + "    def _feed():\n" + "        try:\n" + "            for frame in ui_stream():\n" + "                if _stop.is_set():\n" + "                    break\n" + "                if frame.get('heartbeat'):\n" + "                    continue\n" + "                _q.put(_frame_blob(frame))\n" + "        except Exception:\n" + "            pass\n" + "    threading.Thread(target=_feed, daemon=True).start()\n" + "def _agent_poll():\n" + "    try:\n" + "        return _q.get_nowait()\n" + "    except queue.Empty:\n" + "        return ''\n" + "def _agent_send(line):\n" + "    _dispatch_cmd(line, _stop, None)\n" + "def _agent_stop():\n" + "    _stop.set()\n" + "    try:\n" + "        ui_stop()\n" + "    except Exception:\n" + "        pass\n"
    );
}


# Stub surface: NO agent, NO ui_stream -- a canned feeder that proves the
# boot/GIL/loop shape (engine boots, GIL drops, the daemon thread produces frames,
# the na loop drains+parses+renders them) before the real ui_stream is wired.
# Selected unless JAC_AI_TUI_EMBED_REAL is set in the environment.
def _agent_py_stub -> str {
    return (
        "import threading, time, queue\n" + "_q = queue.Queue()\n" + "_stop = threading.Event()\n" + "def _agent_setup():\n" + "    def _feed():\n" + "        _q.put('TYPE:full\\nSTATUS:idle\\nACTIVE:\\nMODEL:stub\\nNEEDS_KEY:0\\nKEY_ENV:\\nEV:1:system:stub:embed host booted (stub agent)\\n---')\n" + "        n = 0\n" + "        while not _stop.is_set():\n" + "            n += 1\n" + "            _q.put('TYPE:delta\\nEV:1:system:stub:tick ' + str(n) + '\\n---')\n" + "            time.sleep(1.0)\n" + "    threading.Thread(target=_feed, daemon=True).start()\n" + "def _agent_poll():\n" + "    try:\n" + "        return _q.get_nowait()\n" + "    except queue.Empty:\n" + "        return ''\n" + "def _agent_send(line):\n" + "    _q.put('TYPE:delta\\nEV:2:user:stub:sent ' + line + '\\n---')\n" + "def _agent_stop():\n" + "    _stop.set()\n"
    );
}


# Drain one queued frame from the embedded interpreter. GIL-guarded: Ensure ->
# eval `_agent_poll()` (returns a python str, "" when nothing ready) -> copy out
# -> Release. Returns "" when the queue is empty so the caller's while-loop stops.
def _agent_poll(d: int) -> str {
    gstate = jpy_PyGILState_Ensure();
    pyobj: int = jpy_PyRun_String("_agent_poll()", PY_EVAL, d, d);
    out: str = "";
    if pyobj != 0 {
        out = jpy_PyUnicode_AsUTF8(pyobj);
        jpy_Py_DecRef(pyobj);
    }
    jpy_PyGILState_Release(gstate);
    return out;
}


# Push one command line into the embedded interpreter. The (untrusted) command is
# passed as a real python str ARG to the looked-up `_agent_send` callable -- never
# spliced into PyRun_SimpleString, which would be an eval-injection surface. Every
# new reference (the callable, the arg, the result) is DecRef'd; Py_DecRef is not
# NULL-safe through the forwarder, so each is guarded.
def _agent_send(d: int, line: str) {
    gstate = jpy_PyGILState_Ensure();
    fn: int = jpy_PyRun_String("_agent_send", PY_EVAL, d, d);
    if fn != 0 {
        arg: int = jpy_PyUnicode_FromString(line);
        if arg != 0 {
            res: int = jpy_PyObject_CallOneArg(fn, arg);
            if res != 0 {
                jpy_Py_DecRef(res);
            }
            jpy_Py_DecRef(arg);
        }
        jpy_Py_DecRef(fn);
    }
    jpy_PyGILState_Release(gstate);
}


# The unified host loop -- kept inside a function (invoked from `with entry`),
# never in glob init, so the libc/tty calls run only after the imported modules'
# globs are constructed (same contract as tui.na.jac's _run).
def _run_embed -> None {
    proj_s: str = "";
    if proj is not None {
        proj_s = proj;
    }
    files_s: str = "";
    if files_env is not None {
        files_s = files_env;
    }
    presets_s: str = "";
    if presets_env is not None {
        presets_s = presets_env;
    }

    # 1. Bring up the fused CPython (materialize trailer -> dlopen bundled libpython
    #    -> Py_Initialize). Non-zero is a packaging failure; bail before touching
    #    the terminal so a boot error never corrupts the screen.
    engine_rc: i32 = jac_engine_boot();
    if engine_rc != 0 {
        return;
    }

    # 2. Define the agent bridge (real unless JAC_AI_TUI_EMBED_REAL is unset) and
    #    start its background feeder thread. Still under the GIL the boot left held.
    agent_src: str = _agent_py_real();
    use_real = os.getenv("JAC_AI_TUI_EMBED_REAL");
    if use_real is None {
        agent_src = _agent_py_stub();
    }
    # The agent bootstrap can fail (real path: byllm/LLM stack not reachable via
    # JAC_AI_TUI_BYLLM_SRC / JAC_AI_TUI_DEPS). PyRun_SimpleString returns -1 and
    # prints the traceback (plus our directed hint) to stderr; bail BEFORE tty_open
    # so a packaging/dep error never corrupts the screen -- the clean-error contract
    # desktop's _scale hook keeps, the inverse of the old NameError cascade.
    def_rc: i32 = jpy_PyRun_SimpleString(agent_src);
    main_mod: int = jpy_PyImport_AddModule("__main__");
    d: int = jpy_PyModule_GetDict(main_mod);
    setup_rc: i32 = 0;
    if def_rc == 0 {
        setup_rc = jpy_PyRun_SimpleString("_agent_setup()");
    }
    if def_rc != 0 or setup_rc != 0 {
        jpy_Py_Finalize();
        return;
    }

    # 3. Renderer init -- plain Jac, no ctypes, no .so. ipc_fd = -1 routes
    #    handle_key's commands into the in-process pull queue (ipc.na.jac) instead
    #    of a pipe; there is no IPC pipe in this single binary.
    ipc_clear_cmd_queue();
    host_state.ipc_fd = -1;
    fd: int = tty_open();
    if fd < 0 {
        jpy_PyRun_SimpleString("_agent_stop()");
        return;
    }
    tui_populate_state(host_state, proj_s, files_s, presets_s);
    tui_enter_screen(host_state, fd);

    # 4. Drop the GIL so the feeder thread can run. The render/input/tty calls below
    #    are pure Jac/libc and need no GIL; only _agent_poll / _agent_send reacquire
    #    it (Ensure/Release). Mirrors the desktop host's PyEval_SaveThread exactly --
    #    skip this and the feeder never gets the GIL and no frame ever arrives.
    ts: int = jpy_PyEval_SaveThread();

    # 5. The unified select loop: keyboard, agent frames, render.
    while not host_state.quit_flag {
        # (a) input -- pure Jac, GIL not held.
        tty_poll(50);
        if tty_key_ready() > 0 {
            k = tty_read_key();
            if len(k) > 0 {
                quit = handle_key(k, host_state, host_state.ipc_fd);
                if quit {
                    host_state.quit_flag = True;
                }
                # Drain the native command pull queue and forward each line to the
                # embedded agent (SEND:/STOP/RESET/QUIT/APPLY: -- the same grammar
                # the pipe carries).
                cmd: str = ipc_next_command();
                while len(cmd) > 0 {
                    _agent_send(d, cmd);
                    cmd = ipc_next_command();
                }
            }
        }

        # (b) agent frames -- GIL-guarded poll, drain all ready blobs before one
        #     render (keeps up with fast token streams; same rationale as
        #     tui_loop_once draining all pending IPC frames per tick).
        blob: str = _agent_poll(d);
        while len(blob) > 0 {
            ipc_parse_frame(host_state, blob);
            blob = _agent_poll(d);
        }

        # (c) render -- plain Jac. _sync_size detects a resize (no SIGWINCH handler
        #     here, same as the in-process host's tui_render).
        _sync_size(host_state);
        tui_render_once(host_state, host_diff, fd);
    }

    # Reacquire the GIL for shutdown (drain/stop the agent runs python).
    jpy_PyEval_RestoreThread(ts);
    jpy_PyRun_SimpleString("_agent_stop()");
    tui_leave_screen(host_state, fd);
    tty_close();
    jpy_Py_Finalize();
}


with entry {
    _run_embed();
}
