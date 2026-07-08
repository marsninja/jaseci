import from .libc_tty {
    tty_write,
    tty_poll,
    tty_stdin_ready,
    tty_key_ready,
    tty_read_key,
    tty_read_line
}
import from .blob_reader { read_blob }

import from jacpyembed {
    def jpy_PyEval_SaveThread -> int;  def jpy_PyEval_RestoreThread(s: int) -> None;  def jpy_PyObject_CallNoArgs(
        fn: int
    ) -> int;  def jpy_PyObject_CallOneArg(fn: int, arg: int) -> int;  def jpy_PyUnicode_FromString(
        s: str
    ) -> int;  def jpy_PyUnicode_AsUTF8(pyobj: int) -> str;  def jpy_Py_DecRef(
        pyobj: int
    ) -> None;
}

obj CmdQueue {
    has _items: list[str] = [],
        _cursor: int = 0;

    def send(fd: int, cmd: str) {
        if fd < 0 {
            self._items.append(cmd);
            return;
        }
        tty_write(fd, cmd + "\n");
    }

    def drain -> str {
        if self._cursor >= len(self._items) {
            self._items = [];
            self._cursor = 0;
            return "";
        }
        cmd = self._items[self._cursor];
        self._cursor = self._cursor + 1;
        return cmd;
    }

    def clear {
        self._items = [];
        self._cursor = 0;
    }
}

obj Transport {
    def poll(timeout_ms: int) { }
    def poll_gil(timeout_ms: int) {
        self.poll(timeout_ms);
    }

    def key_ready -> int {
        return 0;
    }

    def read_key -> str {
        return "";
    }

    def recv_blob -> str {
        return "";
    }

    def send_cmd(cmd: str) { }
    def flush_outbound_cmds(cmd_queue: CmdQueue) { }
    def stdin_eof -> bool {
        return False;
    }
}

obj TtyFdTransport(Transport) {
    has stdin_eof: bool = False;

    def poll(timeout_ms: int) {
        tty_poll(timeout_ms);
    }

    def key_ready -> int {
        return tty_key_ready();
    }

    def read_key -> str {
        return tty_read_key();
    }

    def recv_blob -> str {
        if tty_stdin_ready() <= 0 {
            return "";
        }
        raw = tty_read_line();
        if len(raw) == 0 {
            self.stdin_eof = True;
            return "";
        }

        first = raw.strip();
        result = read_blob(first);
        if result.eof {
            self.stdin_eof = True;
        }
        return result.text;
    }

    def send_cmd(cmd: str) { }
}

obj EmbedPyTransport(TtyFdTransport) {
    has py_dict: int = 0,
        py_poll_fn: int = 0,
        py_send_fn: int = 0;

    def bind_py(dict_ptr: int, poll_fn: int, send_fn: int) {
        self.py_dict = dict_ptr;
        self.py_poll_fn = poll_fn;
        self.py_send_fn = send_fn;
        self.stdin_eof = False;
    }

    def close_py {
        if self.py_poll_fn != 0 {
            jpy_Py_DecRef(self.py_poll_fn);
            self.py_poll_fn = 0;
        }
        if self.py_send_fn != 0 {
            jpy_Py_DecRef(self.py_send_fn);
            self.py_send_fn = 0;
        }
    }

    def poll_gil(timeout_ms: int) {
        ts: int = jpy_PyEval_SaveThread();
        try {
            self.poll(timeout_ms);
        } finally {
            jpy_PyEval_RestoreThread(ts);
        }
    }

    def recv_blob -> str {
        out: str = "";
        if self.py_poll_fn != 0 {
            pyobj: int = jpy_PyObject_CallNoArgs(self.py_poll_fn);
            if pyobj != 0 {
                out = jpy_PyUnicode_AsUTF8(pyobj);
                jpy_Py_DecRef(pyobj);
            }
        }
        return out;
    }

    def flush_outbound_cmds(cmd_queue: CmdQueue) {
        if self.py_send_fn == 0 {
            cmd_queue.clear();
            return;
        }
        cmd: str = cmd_queue.drain();
        while len(cmd) > 0 {
            arg: int = jpy_PyUnicode_FromString(cmd);
            if arg != 0 {
                res: int = jpy_PyObject_CallOneArg(self.py_send_fn, arg);
                if res != 0 {
                    jpy_Py_DecRef(res);
                }
                jpy_Py_DecRef(arg);
            }
            cmd = cmd_queue.drain();
        }
    }
}
