import from .libc_tty { tty_open, tty_close }
import from .state { TuiState }
import from .select_list { SelectList, SelectItem }
import from .diff { DiffEngine }
import from .terminal_image { term_hyperlink, image_rows }
import from .transport { EmbedPyTransport }
import from .tui_loop { tui_loop_once }
import from .tui_core { tui_populate_state, tui_enter_screen, tui_leave_screen }
import from .runtime { TuiRuntime }

import os;

import from jacpyembed {
    def jac_engine_boot -> i32;  def jpy_Py_Finalize -> None;  def jpy_PyRun_SimpleString(
        cmd: str
    ) -> i32;  def jpy_PyImport_AddModule(name: str) -> int;  def jpy_PyModule_GetDict(
        module: int
    ) -> int;  def jpy_PyRun_String(s: str, start: i32, g: int, l: int) -> int;  def jpy_Py_DecRef(
        pyobj: int
    ) -> None;
}

glob PY_EVAL: i32 = 258,
     proj = os.getenv("JAC_AI_UI_PROJECT"),
     files_env = os.getenv("JAC_AI_UI_FILES"),
     presets_env = os.getenv("JAC_AI_UI_MODEL_PRESETS");

glob _BOOTSTRAP_PY: str = (
         "from jaclang.cli.ai_tui.embed_agent import "
         "setup as _agent_setup, poll as _agent_poll, "
         "send as _agent_send, stop as _agent_stop\n"
     );

glob embed_transport: EmbedPyTransport = EmbedPyTransport();


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

    def_rc: i32 = jpy_PyRun_SimpleString(_BOOTSTRAP_PY);
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

    rt = TuiRuntime();
    rt.transport = embed_transport;
    state = rt.state;
    rt.cmd_queue.clear();
    state.ipc_fd = -1;
    fd: int = tty_open();
    if fd < 0 {
        jpy_PyRun_SimpleString("_agent_stop()");
        jpy_Py_Finalize();
        return;
    }
    state.render_fd = fd;
    tui_populate_state(state, proj_s, files_s, presets_s);
    tui_enter_screen(state);

    embed_transport.py_dict = d;
    embed_transport.py_poll_fn = jpy_PyRun_String("_agent_poll", PY_EVAL, d, d);
    embed_transport.py_send_fn = jpy_PyRun_String("_agent_send", PY_EVAL, d, d);
    embed_transport.stdin_eof = False;

    try {
        while tui_loop_once(rt) { }
    } finally {
        jpy_PyRun_SimpleString("_agent_stop()");
        if embed_transport.py_poll_fn != 0 {
            jpy_Py_DecRef(embed_transport.py_poll_fn);
            embed_transport.py_poll_fn = 0;
        }
        if embed_transport.py_send_fn != 0 {
            jpy_Py_DecRef(embed_transport.py_send_fn);
            embed_transport.py_send_fn = 0;
        }
        tui_leave_screen(state);
        tty_close();
        jpy_Py_Finalize();
    }
}


with entry {
    _run_embed();
}
