"""Spawn a TUI renderer sidecar as a subprocess for `jac ai --tui`.

This module is the seam between the Jac/Python agent control plane and the
native (`na`) renderer sidecar.  The control plane streams UI frames to the
sidecar's stdin and reads single-line commands back from its stdout.

The wire protocol is documented authoritatively in ai_tui/PROTOCOL.md (frames +
commands) and ai_tui/BACKENDS.md (spawn details).

IPC overview:
  Python feeds ui_stream() frames to the sidecar's stdin as key:value lines
  terminated by "---".  The sidecar sends single-line commands to Python via
  its stdout (SEND:, STOP, RESET, QUIT, APPLY:).

Frame format (Python -> sidecar):
  TYPE:full|delta|hb
  STATUS:<str>
  ACTIVE:<str>
  MODEL:<str>
  NEEDS_KEY:0|1
  KEY_ENV:<str>
  EV:<id>:<kind>:<node>:<text_escaped>
  ---

text_escaped: \n -> \\n, \\ -> \\\\
"""

import from jaclang.cli.agent_api { AgentRequest }
import from jac_super.ai_agent.tui_shared {
    _debug_log,
    _dispatch_cmd,
    _frame_blob,
    _list_project_files,
    _sidecar_tty_device
}

impl run_tui_session(req: AgentRequest) -> int {
    import os;
    import threading;
    import from pathlib { Path }
    import from jaclang.cli.ai_agent {
        _MODEL_PRESETS,
        ui_configure,
        ui_stop,
        ui_stream
    }
    import from jaclang.cli.console { console }

    # run_tui_session.jac lives in jac_super/ai_agent/; sidecars in jac_super/ai_tui_*/
    pkg_root = Path(__file__).resolve().parent.parent;

    typed_req: AgentRequest = req;
    r: any = typed_req;
    initial = str(r?.prompt or "").strip();

    ensured = _ensure_tui_binary(pkg_root);
    if not ensured.get("ok") {
        console.error(str(ensured.get("error", "failed to build TUI backend")));
        hint = str(ensured.get("hint", ""));
        if hint {
            console.error(hint);
        }
        return 1;
    }
    resolved = _resolve_tui_command(pkg_root, initial);

    if not resolved.get("ok") {
        console.error(str(resolved.get("error", "failed to resolve TUI backend")));
        hint = str(resolved.get("hint", ""));
        if hint {
            console.error(hint);
        }
        return 1;
    }
    cmd_args = resolved.get("cmd_args");

    tty_dev = _sidecar_tty_device();
    if not tty_dev {
        console.error(
            "jac ai --tui needs an interactive terminal (stdin or stderr must be a TTY)"
        );
        return 1;
    }
    old_tty_env = os.environ.get("JAC_AI_TUI_TTY");
    os.environ["JAC_AI_TUI_TTY"] = tty_dev;

    project = os.path.normpath(str(r?.cwd or os.getcwd()));
    os.environ["JAC_AI_UI_PROJECT"] = project;
    os.environ["JAC_AI_UI_MODEL"] = str(r?.model or "");
    os.environ["JAC_AI_UI_NCTX"] = str(int(r?.n_ctx or 0));
    # File-picker source: a newline-separated project file list, capped. Computed
    # here (control plane) so the native sidecar needs no filesystem FFI; it reads
    # JAC_AI_UI_FILES via os.getenv at startup. Prefer tracked files, else walk.
    os.environ["JAC_AI_UI_FILES"] = _list_project_files(project);
    # Model-picker defaults: same one-click list as `ai_agent._MODEL_PRESETS`.
    os.environ["JAC_AI_UI_MODEL_PRESETS"] = "\n".join(_MODEL_PRESETS);
    old_active = os.environ.get("JAC_AI_UI_ACTIVE");
    os.environ["JAC_AI_UI_ACTIVE"] = "1";

    ui_configure();

    try {
        proc = _spawn_tui_backend(cmd_args);
        _debug_log(f"spawned pid={proc.pid} cmd={cmd_args}");
    } except Exception as e {
        _debug_log(f"launch failed: {e}");
        try {
            ui_stop();
        } except Exception { }
        if old_active is None {
            os.environ.pop("JAC_AI_UI_ACTIVE", None);
        } else {
            os.environ["JAC_AI_UI_ACTIVE"] = old_active;
        }
        if old_tty_env is None {
            os.environ.pop("JAC_AI_TUI_TTY", None);
        } else {
            os.environ["JAC_AI_TUI_TTY"] = old_tty_env;
        }
        console.error(f"Failed to launch jac ai TUI: {e}");
        return 1;
    }

    stop_evt = threading.Event();

    def _cmd_reader {
        try {
            for raw_line in proc.stdout {
                line = raw_line.strip();
                if not line {
                    continue;
                }
                _debug_log(f"cmd <- {line}");
                _dispatch_cmd(line, stop_evt, proc);
            }
            _debug_log("cmd reader: stdout closed");
        } except Exception as e {
            _debug_log(f"cmd reader error: {e}");
        }
    }

    def _stream_writer {
        try {
            for frame in ui_stream() {
                if proc.poll() is not None {
                    break;
                }
                if stop_evt.is_set() {
                    break;
                }
                if frame.get("heartbeat") {
                    continue;
                }
                _debug_log(
                    "frame -> " + str(frame.get("status", "")) + " active=" + str(
                        frame.get("active", "")
                    ) + " full=" + str(bool(frame.get("full"))) + " ev=" + str(
                        (frame.get("ev") or {}).get("kind", "")
                    )
                );
                _write_frame(proc.stdin, frame);
            }
            _debug_log("stream writer: ui_stream ended");
        } except Exception as e {
            _debug_log(f"stream writer error: {e}");
        }
        try {
            proc.stdin.close();
        } except Exception as e {
            _debug_log(f"stdin close error: {e}");
        }
    }

    cmd_thread = threading.Thread(target=_cmd_reader, daemon=True);
    stream_thread = threading.Thread(target=_stream_writer, daemon=True);
    cmd_thread.start();
    stream_thread.start();

    try {
        proc.wait();
    } except KeyboardInterrupt {
        proc.terminate();
        proc.wait();
    } finally {
        stop_evt.set();
        try {
            ui_stop();
        } except Exception { }
        if old_active is None {
            os.environ.pop("JAC_AI_UI_ACTIVE", None);
        } else {
            os.environ["JAC_AI_UI_ACTIVE"] = old_active;
        }
        if old_tty_env is None {
            os.environ.pop("JAC_AI_TUI_TTY", None);
        } else {
            os.environ["JAC_AI_TUI_TTY"] = old_tty_env;
        }
    }

    rc: any = proc.returncode;
    _debug_log(f"session exit rc={rc}");
    return int(rc if rc is not None else 0);
}

def _tui_binary_path(pkg_root: any) -> str {
    return str(pkg_root / "ai_tui_na" / "bin" / "jac-na-tui");
}

def _ensure_tui_binary(pkg_root: any) -> dict {
    # Compile jac-na-tui on first launch when NA sources are present (dev tree).
    # Installed packages without sources still need a prebuilt binary or manual build.
    # Set JAC_AI_TUI_REBUILD=1 to force a recompile of an existing binary (dev
    # iteration: pick up edits to *.na.jac without deleting bin/jac-na-tui by hand).
    import os;
    import subprocess;
    import from jaclang.cli.console { console }

    binary = _tui_binary_path(pkg_root);
    exists = os.path.exists(binary);
    force = os.environ.get("JAC_AI_TUI_REBUILD", "").strip().lower() in (
        "1",
        "true",
        "yes",
        "on"
    );
    if exists and not force {
        return {"ok": True, "error": "", "hint": ""};
    }
    na_dir = str(pkg_root / "ai_tui_na");
    tui_src = str(pkg_root / "ai_tui_na" / "tui.na.jac");
    build_sh = str(pkg_root / "ai_tui_na" / "build.sh");
    if not os.path.isfile(tui_src) {
        # No sources to (re)build from. Use a prebuilt binary if present
        # (installed package); only fail when there is nothing to run.
        if exists {
            return {"ok": True, "error": "", "hint": ""};
        }
        return {
            "ok": False,
            "cmd_args": [],
            "error": f"jac-na-tui not found at {binary}",
            "hint": "Build it with: jac-super/jac_super/ai_tui_na/build.sh",

        };
    }
    if not os.path.isfile(build_sh) {
        if exists {
            return {"ok": True, "error": "", "hint": ""};
        }
        return {
            "ok": False,
            "cmd_args": [],
            "error": f"jac-na-tui not found at {binary}",
            "hint": (
                "Build it with: cd jac-super/jac_super/ai_tui_na && " + "jac nacompile tui.na.jac -o bin/jac-na-tui"
            ),

        };
    }
    if force and exists {
        console.print(
            "[tui] JAC_AI_TUI_REBUILD set; recompiling jac-na-tui ...", style="dim"
        );
    } else {
        console.print(
            "[tui] jac-na-tui missing; compiling (first run) ...", style="dim"
        );
    }
    try {
        res = subprocess.run(
            ["bash", build_sh, "--quick"],
            cwd=na_dir,
            capture_output=True,
            text=True,
            timeout=300,
        );
        if res.returncode != 0 {
            detail = (res.stderr or res.stdout or "").strip();
            if detail {
                console.error(detail);
            }
            return {
                "ok": False,
                "cmd_args": [],
                "error": "jac-na-tui compile failed",
                "hint": f"Run manually: {build_sh}",

            };
        }
    } except Exception as e {
        return {
            "ok": False,
            "cmd_args": [],
            "error": f"jac-na-tui compile failed: {e}",
            "hint": f"Run manually: {build_sh}",

        };
    }
    if not os.path.exists(binary) {
        return {
            "ok": False,
            "cmd_args": [],
            "error": f"jac-na-tui not found at {binary} after compile",
            "hint": f"Run manually: {build_sh}",

        };
    }
    return {"ok": True, "cmd_args": [], "error": "", "hint": ""};
}

def _resolve_tui_command(pkg_root: any, initial: str) -> dict {
    # Map the NA sidecar to a spawn command, validating its presence.
    # Returns {ok, cmd_args, error, hint}.  `initial`, when non-empty, is passed
    # to the sidecar as its first positional arg (the seed prompt).
    import os;

    binary = _tui_binary_path(pkg_root);
    if not os.path.exists(binary) {
        return {
            "ok": False,
            "cmd_args": [],
            "error": f"jac-na-tui not found at {binary}",
            "hint": "Build it with:  jac-super/jac_super/ai_tui_na/build.sh",

        };
    }
    cmd_args = [binary];
    if initial {
        cmd_args.append(initial);
    }
    return {"ok": True, "cmd_args": cmd_args, "error": "", "hint": ""};
}

def _spawn_tui_backend(cmd_args: list) -> any {
    # Spawn a sidecar with line-buffered text pipes on stdin/stdout.
    # Own session so keyboard input is not stolen by the parent foreground group.
    # The sidecar opens JAC_AI_TUI_TTY (/dev/pts/N) directly -- not /dev/tty,
    # which fails once setsid() drops the controlling terminal.
    import subprocess;

    return subprocess.Popen(
        cmd_args,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        text=True,
        bufsize=1,
        start_new_session=True,
    );
}

def _write_frame(pipe: any, frame: dict) {
    # Same KEY:VALUE\n...\n--- text the in-process path builds (shared _frame_blob),
    # just flushed to the sidecar's stdin instead of handed to ctypes.
    try {
        pipe.write(_frame_blob(frame) + "\n");
        pipe.flush();
    } except Exception { }
}
