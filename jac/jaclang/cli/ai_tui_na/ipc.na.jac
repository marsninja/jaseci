import from .state { TuiState }

import from .libc_tty { tty_read_line, tty_write }

def _unescape(s: str) -> str {
    result: str = "";
    i: int = 0;
    slen = len(s);
    while i < slen {
        c = s[i];
        if c == "\\" and i + 1 < slen {
            nc = s[i + 1];
            if nc == "n" {
                result = result + "\n";
                i = i + 2;
                continue;
            }
            if nc == "\\" {
                result = result + "\\";
                i = i + 2;
                continue;
            }
        }
        result = result + c;
        i = i + 1;
    }
    return result;
}

def _parse_ev_val(state: TuiState, val: str) -> None {
    i1 = val.find(":");
    if i1 < 0 {
        return;
    }
    id_str = val[:i1];
    rest1 = val[i1 + 1:];

    i2 = rest1.find(":");
    if i2 < 0 {
        return;
    }
    kind = rest1[:i2];
    rest2 = rest1[i2 + 1:];

    i3 = rest2.find(":");
    if i3 < 0 {
        return;
    }
    node_name = rest2[:i3];
    text_esc = rest2[i3 + 1:];
    text = _unescape(text_esc);

    ev_id: int = 0;
    try {
        ev_id = int(id_str);
    } except Exception { }

    state.upsert_event(ev_id, kind, text, node_name);
}

def _parse_eva_val(state: TuiState, val: str) -> None {
    i1 = val.find(":");
    if i1 < 0 {
        return;
    }
    id_str = val[:i1];
    delta_esc = val[i1 + 1:];
    delta = _unescape(delta_esc);

    ev_id: int = 0;
    try {
        ev_id = int(id_str);
    } except Exception { }

    state.append_to_event(ev_id, delta);
}

def ipc_apply_line(state: TuiState, key: str, val: str) {
    if key == "EV" {
        _parse_ev_val(state, val);
        return;
    }
    if key == "EVA" {
        _parse_eva_val(state, val);
        return;
    }

    if key == "STATUS" {
        state.status = val;
    } elif key == "ACTIVE" {
        state.active = val;
    } elif key == "MODEL" {
        state.model_name = val;
    } elif key == "NEEDS_KEY" {
        state.needs_key = val == "1";
    } elif key == "KEY_ENV" {
        state.key_env = val;
    } else {
        return;
    }
    state.dirty = True;
}

def ipc_parse_frame(state: TuiState, blob: str) -> bool {
    lines: list[str] = [];
    for raw in blob.split("\n") {
        line = raw.strip();
        if line == "---" {
            continue;
        }
        if len(line) > 0 {
            lines.append(line);
        }
    }

    if len(lines) == 0 {
        return True;
    }

    frame_type: str = "";
    for line in lines {
        if line.startswith("TYPE:") {
            frame_type = line[5:];
            break;
        }
    }

    if frame_type == "hb" {
        return True;
    }

    if frame_type == "full" {
        state.reset_events();
    }

    for line in lines {
        if line.startswith("TYPE:") {
            continue;
        }
        idx = line.find(":");
        if idx < 0 {
            continue;
        }
        key = line[:idx];
        val = line[idx + 1:];
        ipc_apply_line(state, key, val);
    }

    return True;
}

def ipc_read_frame_v2(state: TuiState) -> bool {
    blob: str = "";

    while True {
        raw = tty_read_line();
        if len(raw) == 0 {
            return False;
        }
        line = raw.strip();
        if line == "---" {
            break;
        }
        if len(line) > 0 {
            if len(blob) > 0 {
                blob = blob + "\n";
            }
            blob = blob + line;
        }
    }

    return ipc_parse_frame(state, blob);
}

obj CmdQueue {
    has items: list[str] = [],
        cursor: int = 0;

    def push(cmd: str) {
        self.items.append(cmd);
    }

    def pop_next -> str {
        if self.cursor >= len(self.items) {
            self.items = [];
            self.cursor = 0;
            return "";
        }
        cmd = self.items[self.cursor];
        self.cursor = self.cursor + 1;
        return cmd;
    }

    def clear {
        self.items = [];
        self.cursor = 0;
    }
}

glob cmd_queue: CmdQueue = CmdQueue();

def ipc_send_cmd(fd: int, cmd: str) {
    if fd < 0 {
        cmd_queue.push(cmd);
        return;
    }
    tty_write(fd, cmd + "\n");
}

def ipc_next_command -> str {
    return cmd_queue.pop_next();
}

def ipc_clear_cmd_queue {
    cmd_queue.clear();
}
