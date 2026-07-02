import sys;
import os;

import from .libc_tty {
    tty_open,
    tty_close,
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
import from .ipc { ipc_read_frame_v2, ipc_send_cmd }
import from .ipc_schema { IPC_CMD_SEND }
import from .screen { screen_render }
import from .diff { DiffEngine }
import from .input { handle_key }
import from .terminal_image { term_hyperlink, image_rows }
import from .tui_core { tui_setup, tui_loop_once, tui_teardown }

glob args = sys.argv;

glob state: TuiState = TuiState(),
     diff_engine: DiffEngine = DiffEngine();

glob proj = os.getenv("JAC_AI_UI_PROJECT");

glob files_env = os.getenv("JAC_AI_UI_FILES");

glob presets_env = os.getenv("JAC_AI_UI_MODEL_PRESETS");

def _run {
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

    if tui_setup(state, proj_s, files_s, presets_s) < 0 {
        sys.exit(1);
    }

    if len(args) > 1 {
        initial = args[1].strip();
        if len(initial) > 0 {
            ipc_send_cmd(state.ipc_fd, IPC_CMD_SEND + ":" + initial);
        }
    }

    while tui_loop_once(state, diff_engine) { }

    tui_teardown(state);
}

with entry {
    _run();
}
