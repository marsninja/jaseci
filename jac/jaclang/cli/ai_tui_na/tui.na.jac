import sys;
import os;

import from .ipc { ipc_send_cmd }
import from .ipc_schema { IPC_CMD_SEND }
import from .transport { TtyFdTransport }
import from .tui_loop { tui_loop_once }
import from .tui_core { tui_setup, tui_teardown }
import from .runtime { TuiRuntime }

glob args = sys.argv,
     proj = os.getenv("JAC_AI_UI_PROJECT"),
     files_env = os.getenv("JAC_AI_UI_FILES"),
     presets_env = os.getenv("JAC_AI_UI_MODEL_PRESETS");

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

    rt = TuiRuntime();
    rt.transport = TtyFdTransport();
    if tui_setup(rt.state, proj_s, files_s, presets_s) < 0 {
        sys.exit(1);
    }

    if len(args) > 1 {
        initial = args[1].strip();
        if len(initial) > 0 {
            ipc_send_cmd(rt.cmd_queue, rt.state.ipc_fd, IPC_CMD_SEND + ":" + initial);
        }
    }

    while tui_loop_once(rt) { }

    tui_teardown(rt.state);
}

with entry {
    _run();
}
