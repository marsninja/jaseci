import from .libc_tty {
    tty_open,
    tty_open_dev,
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
    tty_write
}
import from .terminal {
    term_enter_alt_screen,
    term_leave_alt_screen,
    term_hide_cursor,
    term_show_cursor,
    term_enable_mouse,
    term_disable_mouse
}
import from .state { TuiState, TuiStatus, OverlayKind }

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
import from .keys { parse_key }
import from .terminal_image { term_hyperlink, image_rows }
import from .tui_core {
    tui_populate_state,
    tui_enter_screen,
    tui_leave_screen,
    tui_render_once,
    _sync_size
}
import from .runtime { TuiRuntime }

glob rt: TuiRuntime = TuiRuntime();

def:pub tui_init(project: str, files_env: str, presets_env: str, tty_dev: str) -> int {
    ipc_clear_cmd_queue(rt.cmd_queue);
    rt.state.reset_events();
    rt.state.files = [];
    rt.state.model_presets = [];
    rt.state.quit_flag = False;

    rt.state.ipc_fd = -1;

    rt.state.status = TuiStatus.IDLE;
    rt.state.active = "";
    rt.state.model_name = "";
    rt.state.needs_key = False;
    rt.state.key_env = "";
    rt.state.editor.clear();
    rt.state.overlay_active = False;
    rt.state.overlay_kind = OverlayKind.PALETTE;
    rt.state.overlay_filter = "";
    rt.diff.invalidate();

    fd: int = tty_open_dev(tty_dev);
    if fd < 0 {
        return 1;
    }
    rt.state.render_fd = fd;
    tui_populate_state(rt.state, project, files_env, presets_env);
    tui_enter_screen(rt.state);
    return 0;
}

def:pub tui_apply_frame(blob: str) -> int {
    ok = ipc_parse_frame(rt.state, blob);
    if ok {
        return 0;
    }
    return 1;
}

def:pub tui_wait_key(timeout_ms: int) -> int {
    tty_poll(timeout_ms);
    return tty_key_ready();
}

def:pub tui_handle_key -> int {
    raw = tty_read_key();
    if len(raw) == 0 {
        return 0;
    }
    quit = handle_key(parse_key(raw), rt);
    if quit {
        rt.state.quit_flag = True;
        return 1;
    }
    return 0;
}

def:pub tui_next_command -> str {
    return ipc_next_command(rt.cmd_queue);
}

def:pub tui_quit_requested -> int {
    if rt.state.quit_flag {
        return 1;
    }
    return 0;
}

def:pub tui_render -> int {
    if rt.state.render_fd < 0 {
        return 0;
    }

    _sync_size(rt.state);
    if tui_render_once(rt) {
        return 1;
    }
    return 0;
}

def:pub tui_render_buf -> str {
    rt.diff.invalidate();
    rt.state.dirty = True;
    saved_fd = rt.state.render_fd;
    rt.state.render_fd = -1;
    tui_render_once(rt);
    rt.state.render_fd = saved_fd;
    return diff_take_buf(rt.paint_buf);
}

def:pub tui_shutdown -> int {
    if rt.state.render_fd >= 0 {
        tui_leave_screen(rt.state);
    }
    tty_close();
    return 0;
}
