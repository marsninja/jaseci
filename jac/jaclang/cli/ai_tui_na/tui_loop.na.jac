import from .ipc { ipc_parse_frame }
import from .input { handle_key }
import from .keys { parse_key }
import from .tui_core { tui_render_once, _sync_size }
import from .runtime { TuiRuntime }

def tui_process_keys(rt: TuiRuntime) {
    state = rt.state;
    if rt.transport.key_ready() <= 0 {
        return;
    }
    k = rt.transport.read_key();
    if len(k) == 0 {
        return;
    }
    should_quit = handle_key(parse_key(k), rt);
    if should_quit {
        state.quit_flag = True;
    }
    rt.transport.flush_outbound_cmds(rt.cmd_queue);
}

def tui_drain_blobs(rt: TuiRuntime) -> bool {
    state = rt.state;
    frames_drained: int = 0;
    while frames_drained < 64 {
        blob: str = rt.transport.recv_blob();
        if rt.transport.stdin_eof() {
            return False;
        }
        if len(blob) == 0 {
            break;
        }
        if not ipc_parse_frame(state, blob) {
            return False;
        }
        _sync_size(state);
        frames_drained = frames_drained + 1;
    }
    return True;
}

def tui_loop_once(rt: TuiRuntime) -> bool {
    rt.transport.poll(50);
    tui_process_keys(rt);
    if not tui_drain_blobs(rt) {
        rt.state.quit_flag = True;
        return False;
    }
    tui_render_once(rt);
    return not rt.state.quit_flag;
}
