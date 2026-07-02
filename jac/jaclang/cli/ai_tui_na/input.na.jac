import from .state { TuiState }
import from .ipc { ipc_send_cmd }
import from .ipc_schema { IPC_CMD_SEND, IPC_CMD_STOP, IPC_CMD_RESET, IPC_CMD_QUIT }
import from .autocomplete { ac_update, ac_apply }
import from .overlay {
    overlay_is_active,
    overlay_handle_key,
    overlay_open_palette,
    overlay_open_model,
    overlay_open_file
}
import from .commands { slash_submit }
import from .editor {
    editor_insert,
    editor_backspace,
    editor_forward_delete,
    editor_newline,
    editor_move_left,
    editor_move_right,
    editor_move_up,
    editor_move_down,
    editor_move_line_start,
    editor_move_line_end,
    editor_delete_to_line_end,
    editor_delete_to_line_start,
    editor_delete_word_back,
    editor_word_left,
    editor_word_right,
    editor_is_on_first_vline,
    editor_is_on_last_vline,
    editor_nav_history,
    editor_update_scroll,
    editor_submit
}

def _parse_uint(s: str) -> int {
    n: int = 0;
    i: int = 0;
    m = len(s);
    while i < m {
        c = ord(s[i]);
        if c >= 48 and c <= 57 {
            n = n * 10 + (c - 48);
        }
        i = i + 1;
    }
    return n;
}

def _editor_width(state: TuiState) -> int {
    w = state.term_cols - 6;
    if w < 1 {
        return 1;
    }
    return w;
}

def _editor_max_rows(state: TuiState) -> int {
    m = state.term_rows - 6;
    if m < 1 {
        return 1;
    }
    if m > 10 {
        return 10;
    }
    return m;
}

def _handle_submit(state: TuiState, ipc_fd: int) -> bool {
    ed = state.editor;

    if len(ed.lines) > 0 {
        cur_line = ed.lines[ed.cursor_line];
        if ed.cursor_col > 0 and cur_line[ed.cursor_col - 1] == "\\" {
            editor_backspace(ed);
            editor_newline(ed);
            state.dirty = True;
            return False;
        }
    }

    text = editor_submit(ed);
    state.dirty = True;

    if len(text) == 0 {
        return False;
    }

    result = slash_submit(text, state, ipc_fd);
    if result == "quit" {
        return True;
    }
    if result == "open_model" {
        overlay_open_model(state);
        return False;
    }
    if result == "open_file" {
        overlay_open_file(state);
        return False;
    }
    if result == "handled" {
        return False;
    }

    if state.status == "running" {
        return False;
    }

    state.upsert_event(-1, "user", text, "");
    state.scroll_to_bottom();

    ipc_send_cmd(ipc_fd, IPC_CMD_SEND + ":" + text);
    return False;
}

def handle_key(key: str, state: TuiState, ipc_fd: int) -> bool {
    if len(key) == 0 {
        return False;
    }

    if overlay_is_active(state) {
        return overlay_handle_key(key, state, ipc_fd);
    }

    ed = state.editor;
    ew = _editor_width(state);
    emr = _editor_max_rows(state);

    first = key[0];
    code = ord(first);

    if state.ac.active {
        if code == 9 {
            ac_apply(state);
            editor_update_scroll(ed, ew, emr);
            state.dirty = True;
            return False;
        }

        if code == 27 and len(key) == 1 {
            state.ac.dismiss();
            state.dirty = True;
            return False;
        }

        if key == "\033[A" or key == "\033OA" {
            state.ac.nav_up();
            state.dirty = True;
            return False;
        }

        if key == "\033[B" or key == "\033OB" {
            state.ac.nav_down();
            state.dirty = True;
            return False;
        }

        if (code == 13 or code == 10) and len(key) == 1 {
            ac_kind = state.ac.kind;
            ac_apply(state);
            editor_update_scroll(ed, ew, emr);
            if ac_kind == "slash" {
                return _handle_submit(state, ipc_fd);
            }
            return False;
        }

        state.ac.dismiss();
        state.dirty = True;
    }

    if code == 3 or code == 17 {
        ipc_send_cmd(ipc_fd, IPC_CMD_QUIT);
        return True;
    }

    if code == 7 {
        ipc_send_cmd(ipc_fd, IPC_CMD_STOP);
        state.dirty = True;
        return False;
    }

    if code == 18 {
        ipc_send_cmd(ipc_fd, IPC_CMD_RESET);
        state.reset_events();
        state.dirty = True;
        return False;
    }

    if code == 15 {
        overlay_open_palette(state, "");
        return False;
    }

    if code == 9 {
        ed_text = ed.get_text();
        if ed_text.startswith("/") {
            overlay_open_palette(state, ed_text[1:]);
            return False;
        }
    }

    if code == 1 {
        editor_move_line_start(ed);
        editor_update_scroll(ed, ew, emr);
        state.dirty = True;
        return False;
    }

    if code == 5 {
        editor_move_line_end(ed);
        editor_update_scroll(ed, ew, emr);
        state.dirty = True;
        return False;
    }

    if code == 11 {
        editor_delete_to_line_end(ed);
        editor_update_scroll(ed, ew, emr);
        state.dirty = True;
        return False;
    }

    if code == 21 {
        editor_delete_to_line_start(ed);
        editor_update_scroll(ed, ew, emr);
        state.dirty = True;
        return False;
    }

    if code == 23 {
        editor_delete_word_back(ed);
        editor_update_scroll(ed, ew, emr);
        state.dirty = True;
        return False;
    }

    if key == "\033\r" or key == "\033[13;2~" {
        editor_newline(ed);
        editor_update_scroll(ed, ew, emr);
        state.dirty = True;
        return False;
    }

    if code == 13 or code == 10 {
        if len(key) == 1 {
            return _handle_submit(state, ipc_fd);
        }

        editor_newline(ed);
        editor_update_scroll(ed, ew, emr);
        state.dirty = True;
        return False;
    }

    if code == 127 or code == 8 {
        editor_backspace(ed);
        editor_update_scroll(ed, ew, emr);
        ac_update(state);
        state.dirty = True;
        return False;
    }

    if code == 27 and len(key) > 1 {
        klen = len(key);
        last = key[klen - 1];
        if key.startswith("\033[<") and (last == "M" or last == "m") {
            parts = key[3:klen - 1].split(";");
            if len(parts) > 0 {
                btn = _parse_uint(parts[0]);
                if btn == 64 {
                    state.scroll_up(3);
                } elif btn == 65 {
                    state.scroll_down(3);
                }
            }
            return False;
        }

        if key == "\033[3~" {
            editor_forward_delete(ed);
            editor_update_scroll(ed, ew, emr);
            state.dirty = True;
            return False;
        }

        if key == "\033[A" or key == "\033OA" {
            if editor_is_on_first_vline(ed, ew) {
                navigated = editor_nav_history(ed, -1);
                if not navigated {
                    editor_move_line_start(ed);
                }
            } else {
                editor_move_up(ed, ew);
            }
            editor_update_scroll(ed, ew, emr);
            state.dirty = True;
            return False;
        }

        if key == "\033[B" or key == "\033OB" {
            if editor_is_on_last_vline(ed, ew) {
                navigated = editor_nav_history(ed, 1);
                if not navigated {
                    editor_move_line_end(ed);
                }
            } else {
                editor_move_down(ed, ew);
            }
            editor_update_scroll(ed, ew, emr);
            state.dirty = True;
            return False;
        }

        if key == "\033[D" or key == "\033OD" {
            editor_move_left(ed);
            editor_update_scroll(ed, ew, emr);
            state.dirty = True;
            return False;
        }

        if key == "\033[C" or key == "\033OC" {
            editor_move_right(ed);
            editor_update_scroll(ed, ew, emr);
            state.dirty = True;
            return False;
        }

        if key == "\033[H" or key == "\033OH" {
            editor_move_line_start(ed);
            editor_update_scroll(ed, ew, emr);
            state.dirty = True;
            return False;
        }

        if key == "\033[F" or key == "\033OF" {
            editor_move_line_end(ed);
            editor_update_scroll(ed, ew, emr);
            state.dirty = True;
            return False;
        }

        if key == "\033[1;5D"
        or key == "\033[5D"
        or key == "\033b"
        or key == "\033[1;3D" {
            editor_word_left(ed);
            editor_update_scroll(ed, ew, emr);
            state.dirty = True;
            return False;
        }

        if key == "\033[1;5C"
        or key == "\033[5C"
        or key == "\033f"
        or key == "\033[1;3C" {
            editor_word_right(ed);
            editor_update_scroll(ed, ew, emr);
            state.dirty = True;
            return False;
        }

        if key == "\033[5~" or key == "\033[1;5A" {
            state.scroll_up(state.term_rows - 4);
            return False;
        }

        if key == "\033[6~" or key == "\033[1;5B" {
            state.scroll_down(state.term_rows - 4);
            return False;
        }

        return False;
    }

    if code >= 32 and code <= 126 {
        if len(ed.get_text()) < 4096 {
            editor_insert(ed, first);
            editor_update_scroll(ed, ew, emr);
            ac_update(state);
            state.dirty = True;
        }
        return False;
    }

    return False;
}
