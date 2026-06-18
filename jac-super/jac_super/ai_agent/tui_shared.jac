"""Shared helpers for both `jac ai --tui` backends.

The frame/command grammar (ai_tui/PROTOCOL.md) is identical across the subprocess
and in-process transports; only the carrier differs. These helpers are the one
copy of the wire grammar + command dispatcher + project-file/tty plumbing that
`run_tui_session` (subprocess) and `run_tui_in_process` (in-process) both import,
so the two backends can never drift on the protocol. See PLAN-tui-in-process
§3/§6/§12.

`_frame_blob` is the body of the old `_write_frame` (it joins the same KEY:VALUE
lines, just returns the string instead of flushing it to a pipe). `_dispatch_cmd`
is the shared command dispatcher: it takes an optional `proc` so the subprocess
backend can still `terminate()` on QUIT while the in-process backend passes
`None` (quit there flows through `stop_evt` + the native `tui_quit_requested`).
"""

def _debug_log(msg: str) -> None {
    # Append-only trace, enabled only when JAC_AI_TUI_DEBUG_LOG points at a file.
    import os;
    import time;

    path = os.environ.get("JAC_AI_TUI_DEBUG_LOG", "").strip();
    if not path {
        return;
    }
    try {
        with open(path, "a", encoding="utf-8") as f {
            stamp = time.strftime("%Y-%m-%d %H:%M:%S");
            f.write(f"[{stamp}] {msg}\n");
        }
    } except Exception { }
}


def _esc_text(text: str) -> str {
    return text.replace("\\", "\\\\").replace("\n", "\\n");
}


def _ev_line(ev: dict) -> str {
    ev_id = str(ev.get("id", 0));
    ev_kind = str(ev.get("kind", ""));
    ev_node = str(ev.get("node", ""));
    ev_text = _esc_text(str(ev.get("text", "")));
    return f"EV:{ev_id}:{ev_kind}:{ev_node}:{ev_text}";
}


def _frame_blob(frame: dict) -> str {
    # Build the exact KEY:VALUE\n...\n--- text PROTOCOL.md specifies. The
    # subprocess path writes this to the sidecar's stdin; the in-process path
    # hands it to tui_apply_frame via ctypes. Byte-for-byte identical either way.
    parts = [];
    if frame.get("full") {
        parts.append("TYPE:full");
    } else {
        parts.append("TYPE:delta");
    }
    parts.append(f"STATUS:{frame.get('status', '')}");
    parts.append(f"ACTIVE:{frame.get('active', '')}");
    parts.append(f"MODEL:{frame.get('model_name', '')}");
    parts.append(f"NEEDS_KEY:{'1' if frame.get('needs_key') else '0'}");
    parts.append(f"KEY_ENV:{frame.get('key_env', '')}");

    if frame.get("full") {
        for ev in (frame.get("events") or []) {
            parts.append(_ev_line(ev));
        }
    } elif frame.get("ev") {
        parts.append(_ev_line(frame["ev"]));
    }

    parts.append("---");
    return "\n".join(parts);
}


def _list_project_files(project: str) -> str {
    # Newline-separated relative file paths under `project` for the file picker.
    # Tracked files first (git ls-files), else a bounded filesystem walk. Capped
    # so the value stays well within env-var size limits.
    import os;
    import subprocess;

    cap = 2000;
    out_lines: list = [];
    try {
        res = subprocess.run(
            ["git", "-C", project, "ls-files"],
            capture_output=True,
            text=True,
            timeout=5
        );
        if res.returncode == 0 {
            for line in res.stdout.split("\n") {
                s = line.strip();
                if s {
                    out_lines.append(s);
                }
                if len(out_lines) >= cap {
                    break;
                }
            }
        }
    } except Exception { }

    if not out_lines {
        try {
            for entry in os.walk(project) {
                dirpath = entry[0];
                if ".git" in dirpath.split(os.sep) {
                    continue;
                }
                for fn in entry[2] {
                    rel = os.path.relpath(os.path.join(dirpath, fn), project);
                    out_lines.append(rel);
                    if len(out_lines) >= cap {
                        break;
                    }
                }
                if len(out_lines) >= cap {
                    break;
                }
            }
        } except Exception { }
    }

    return "\n".join(out_lines);
}


def _sidecar_tty_device -> str {
    # Resolve the interactive terminal the user is sitting at. Both backends use
    # it: the subprocess sidecar gets it via JAC_AI_TUI_TTY (its stdin is a pipe);
    # the in-process host opens it directly with tui_init's tty_dev arg.
    import os;
    import sys;

    for stream in (sys.stderr, sys.stdin, sys.stdout) {
        try {
            if stream.isatty() {
                return os.ttyname(stream.fileno());
            }
        } except Exception { }
    }
    return "";
}


def _dispatch_cmd(line: str, stop_evt: any, proc: any) {
    # Map one command line (SEND:/STOP/RESET/QUIT/APPLY:) onto the agent UI API.
    # Shared by both backends. `proc` is the subprocess handle for the subprocess
    # backend (terminated on QUIT) and None for the in-process backend, where quit
    # is signalled purely through stop_evt + the native tui_quit_requested poll.
    import from jaclang.cli.ai_agent { ui_send, ui_stop, ui_reset, ui_apply_settings }

    if line.startswith("SEND:") {
        prompt = line[5:];
        try {
            ok = ui_send(prompt);
            _debug_log(f"ui_send({prompt!r}) -> {ok}");
        } except Exception as e {
            _debug_log(f"ui_send({prompt!r}) error: {e}");
        }
    } elif line == "STOP" {
        try {
            ui_stop();
            _debug_log("ui_stop()");
        } except Exception as e {
            _debug_log(f"ui_stop error: {e}");
        }
    } elif line == "RESET" {
        try {
            ui_reset();
            _debug_log("ui_reset()");
        } except Exception as e {
            _debug_log(f"ui_reset error: {e}");
        }
    } elif line == "QUIT" {
        stop_evt.set();
        try {
            ui_stop();
            _debug_log("ui_stop() before quit");
        } except Exception as e {
            _debug_log(f"ui_stop before quit error: {e}");
        }
        if proc is not None {
            try {
                proc.terminate();
                _debug_log("proc.terminate()");
            } except Exception as e {
                _debug_log(f"proc.terminate error: {e}");
            }
        }
    } elif line.startswith("APPLY:") {
        args_str = line[6:];
        settings: dict = {};
        for part in args_str.split(",") {
            eq = part.find("=");
            if eq > 0 {
                k = part[:eq].strip();
                v = part[eq + 1:].strip();
                settings[k] = v;
            }
        }
        try {
            result = ui_apply_settings(
                model=settings.get("model", ""),
                n_ctx=settings.get("n_ctx", ""),
                api_key=settings.get("api_key", ""),
                base_url=settings.get("base_url", ""),
                temperature=settings.get("temperature", ""),
            );
            _debug_log(f"ui_apply_settings({settings}) -> {result}");
        } except Exception as e {
            _debug_log(f"ui_apply_settings({settings}) error: {e}");
        }
    }
}
