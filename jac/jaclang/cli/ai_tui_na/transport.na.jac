import from .libc_tty { tty_write }

obj Transport {
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
