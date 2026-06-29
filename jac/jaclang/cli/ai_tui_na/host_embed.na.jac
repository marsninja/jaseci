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

glob PY_EVAL: i32 = 258;

glob host_state: TuiState = TuiState(),
     host_diff: DiffEngine = DiffEngine();

glob proj = os.getenv("JAC_AI_UI_PROJECT");
glob files_env = os.getenv("JAC_AI_UI_FILES");
glob presets_env = os.getenv("JAC_AI_UI_MODEL_PRESETS");


def _byllm_runtime_hook_py -> str {
    return (
        "_byllm = os.environ.get('JAC_AI_TUI_BYLLM_SRC')\n" + "if _byllm and _byllm not in sys.path:\n" + "    sys.path.insert(0, _byllm)\n" + "_deps = os.environ.get('JAC_AI_TUI_DEPS', '')\n" + "if _deps:\n" + "    for _d in _deps.split(os.pathsep):\n" + "        if _d and _d not in sys.path:\n" + "            sys.path.append(_d)\n"
    );
}


def _agent_py_real -> str {
    return (
        "import os, sys, threading, queue\n" + _byllm_runtime_hook_py() + "try:\n" + "    from jaclang.cli.ai_agent import ui_configure, ui_stream, ui_stop\n" + "    from jaclang.cli.ai_tui.tui_shared import _frame_blob, _dispatch_cmd\n" + "except Exception as _e:\n" + "    sys.stderr.write('jac-ai-tui: embedded agent backend unavailable: ' + repr(_e) + '\\n')\n" + "    sys.stderr.write('  point the embedded interpreter at byllm: set JAC_AI_TUI_BYLLM_SRC=<jac-byllm checkout> and JAC_AI_TUI_DEPS=<dep dirs (litellm, openai, ...)>.\\n')\n" + "    raise\n" + "_q = queue.Queue()\n" + "_stop = threading.Event()\n" + "def _agent_setup():\n" + "    ui_configure()\n" + "    def _feed():\n" + "        try:\n" + "            for frame in ui_stream():\n" + "                if _stop.is_set():\n" + "                    break\n" + "                if frame.get('heartbeat'):\n" + "                    continue\n" + "                _q.put(_frame_blob(frame))\n" + "        except Exception:\n" + "            pass\n" + "    threading.Thread(target=_feed, daemon=True).start()\n" + "def _agent_poll():\n" + "    try:\n" + "        return _q.get_nowait()\n" + "    except queue.Empty:\n" + "        return ''\n" + "def _agent_send(line):\n" + "    _dispatch_cmd(line, _stop, None)\n" + "def _agent_stop():\n" + "    _stop.set()\n" + "    try:\n" + "        ui_stop()\n" + "    except Exception:\n" + "        pass\n"
    );
}


def _agent_py_stub -> str {
    return (
        "import threading, time, queue\n" + "_q = queue.Queue()\n" + "_stop = threading.Event()\n" + "def _agent_setup():\n" + "    def _feed():\n" + "        _q.put('TYPE:full\\nSTATUS:idle\\nACTIVE:\\nMODEL:stub\\nNEEDS_KEY:0\\nKEY_ENV:\\nEV:1:system:stub:embed host booted (stub agent)\\n---')\n" + "        n = 0\n" + "        while not _stop.is_set():\n" + "            n += 1\n" + "            _q.put('TYPE:delta\\nEV:1:system:stub:tick ' + str(n) + '\\n---')\n" + "            time.sleep(1.0)\n" + "    threading.Thread(target=_feed, daemon=True).start()\n" + "def _agent_poll():\n" + "    try:\n" + "        return _q.get_nowait()\n" + "    except queue.Empty:\n" + "        return ''\n" + "def _agent_send(line):\n" + "    _q.put('TYPE:delta\\nEV:2:user:stub:sent ' + line + '\\n---')\n" + "def _agent_stop():\n" + "    _stop.set()\n"
    );
}


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

    engine_rc: i32 = jac_engine_boot();
    if engine_rc != 0 {
        return;
    }

    agent_src: str = _agent_py_real();
    use_real = os.getenv("JAC_AI_TUI_EMBED_REAL");
    if use_real is None {
        agent_src = _agent_py_stub();
    }

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

    ipc_clear_cmd_queue();
    host_state.ipc_fd = -1;
    fd: int = tty_open();
    if fd < 0 {
        jpy_PyRun_SimpleString("_agent_stop()");
        return;
    }
    tui_populate_state(host_state, proj_s, files_s, presets_s);
    tui_enter_screen(host_state, fd);

    ts: int = jpy_PyEval_SaveThread();

    while not host_state.quit_flag {
        tty_poll(50);
        if tty_key_ready() > 0 {
            k = tty_read_key();
            if len(k) > 0 {
                quit = handle_key(k, host_state, host_state.ipc_fd);
                if quit {
                    host_state.quit_flag = True;
                }

                cmd: str = ipc_next_command();
                while len(cmd) > 0 {
                    _agent_send(d, cmd);
                    cmd = ipc_next_command();
                }
            }
        }

        blob: str = _agent_poll(d);
        while len(blob) > 0 {
            ipc_parse_frame(host_state, blob);
            blob = _agent_poll(d);
        }

        _sync_size(host_state);
        tui_render_once(host_state, host_diff, fd);
    }

    jpy_PyEval_RestoreThread(ts);
    jpy_PyRun_SimpleString("_agent_stop()");
    tui_leave_screen(host_state, fd);
    tty_close();
    jpy_Py_Finalize();
}


with entry {
    _run_embed();
}
