import from .libc_tty { tty_write }
import from .terminal { term_sync_start, term_sync_end }

glob _BG: str = "\033[48;2;18;18;28m",
     _RESET: str = "\033[0m";

obj PaintBuf {
    has text: str = "";

    def append(s: str) {
        self.text = self.text + s;
    }

    def take -> str {
        t = self.text;
        self.text = "";
        return t;
    }
}

def diff_take_buf(paint_buf: PaintBuf) -> str {
    return paint_buf.take();
}

def _emit(fd: int, text: str, paint_buf: PaintBuf) {
    if fd < 0 {
        paint_buf.append(text);
        return;
    }
    tty_write(fd, text);
}

def _abs_move(row: int) -> str {
    r: int = row + 1;
    return f"\033[{r};1H";
}

def _full_paint(lines: list[str], fd: int, paint_buf: PaintBuf) {
    if fd >= 0 {
        term_sync_start(fd);
    }

    _emit(fd, _BG + "\033[2J\033[H", paint_buf);
    i: int = 0;
    n = len(lines);
    while i < n {
        if i > 0 {
            _emit(fd, "\r\n", paint_buf);
        }
        _emit(fd, lines[i], paint_buf);
        i = i + 1;
    }
    _emit(fd, _RESET, paint_buf);
    if fd >= 0 {
        term_sync_end(fd);
    }
}

def _diff_paint(lines: list[str], first: int, last: int, fd: int, paint_buf: PaintBuf) {
    if fd >= 0 {
        term_sync_start(fd);
    }

    _emit(fd, _BG, paint_buf);
    i: int = first;
    nl = len(lines);
    while i <= last {
        _emit(fd, _abs_move(i) + "\033[2K", paint_buf);
        if i < nl {
            _emit(fd, lines[i], paint_buf);
        }
        i = i + 1;
    }
    _emit(fd, _RESET, paint_buf);
    if fd >= 0 {
        term_sync_end(fd);
    }
}

obj DiffEngine {
    has prev_lines: list[str] = [],
        prev_width: int = 0;

    def invalidate {
        self.prev_lines = [];
    }

    def paint(lines: list[str], width: int, fd: int, paint_buf: PaintBuf) {
        if width != self.prev_width or len(self.prev_lines) == 0 {
            _full_paint(lines, fd, paint_buf);
            self.prev_lines = lines;
            self.prev_width = width;
            return;
        }

        first_changed: int = -1;
        last_changed: int = -1;
        nl = len(lines);
        pl = len(self.prev_lines);
        max_l: int = nl;
        if pl > max_l {
            max_l = pl;
        }

        i: int = 0;
        while i < max_l {
            old_line: str = "";
            new_line: str = "";
            if i < pl {
                old_line = self.prev_lines[i];
            }
            if i < nl {
                new_line = lines[i];
            }
            if old_line != new_line {
                if first_changed < 0 {
                    first_changed = i;
                }
                last_changed = i;
            }
            i = i + 1;
        }

        if first_changed >= 0 {
            _diff_paint(lines, first_changed, last_changed, fd, paint_buf);
        }

        self.prev_lines = lines;
    }
}
