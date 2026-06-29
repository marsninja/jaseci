import os;

import from "kernel32.dll" {
    def GetStdHandle(std: i32) -> i64;  def GetConsoleMode(
        handle: i64, mode: str
    ) -> i32;  def SetConsoleMode(handle: i64, mode: i32) -> i32;  def ReadConsoleInputW(
        handle: i64, buf: str, count: i32, read: str
    ) -> i32;  def WriteFile(
        handle: i64, buf: str, n: i32, written: str, overlapped: i64
    ) -> i32;  def PeekConsoleInputW(
        handle: i64, buf: str, count: i32, read: str
    ) -> i32;  def GetConsoleScreenBufferInfo(handle: i64, info: str) -> i32;  def WaitForSingleObject(
        handle: i64, ms: i32
    ) -> i32;  def AttachConsole(pid: i32) -> i32;  def AllocConsole -> i32;  def FreeConsole -> i32;
}

import from "msvcrt.dll" {
    def calloc(n: int, sz: int) -> int;  def free(p: int) -> None;  def memset(
        s: int, c: i32, n: int
    ) -> int;  def memcpy(dst: int, src: str, n: int) -> int;
}


glob INVALID_HANDLE: int = -1;

glob ENABLE_PROCESSED_INPUT: int = 0x0001,
     ENABLE_LINE_INPUT: int = 0x0002,
     ENABLE_ECHO_INPUT: int = 0x0004;

glob ENABLE_VT_PROCESSING: int = 0x0004;

glob WAIT_OBJECT_0: int = 0,
     WAIT_TIMEOUT: int = 258;

glob KEY_EVENT_TYPE: int = 1;

glob SHIFT_PRESSED: int = 0x0010;

glob VK_BACK: int = 0x08,
     VK_TAB: int = 0x09,
     VK_PRIOR: int = 0x21,
     VK_NEXT: int = 0x22,
     VK_END: int = 0x23,
     VK_HOME: int = 0x24,
     VK_LEFT: int = 0x25,
     VK_UP: int = 0x26,
     VK_RIGHT: int = 0x27,
     VK_DOWN: int = 0x28,
     VK_INSERT: int = 0x2D,
     VK_DELETE: int = 0x2E,
     VK_F1: int = 0x70,
     VK_F2: int = 0x71,
     VK_F3: int = 0x72,
     VK_F4: int = 0x73,
     VK_F5: int = 0x74,
     VK_F6: int = 0x75,
     VK_F7: int = 0x76,
     VK_F8: int = 0x77,
     VK_F9: int = 0x78,
     VK_F10: int = 0x79,
     VK_F11: int = 0x7A,
     VK_F12: int = 0x7B;

obj TtyCtx {
    has in_handle: int = -1,
        out_handle: int = -1,
        saved_in_mode: int = 0,
        saved_out_mode: int = 0,
        rows: int = 24,
        cols: int = 80,
        stdin_ready: int = 0,
        key_ready: int = 0,
        allocated_console: int = 0;
}

glob g_tty: TtyCtx = TtyCtx();

def read_u32(buf: str, off: int) -> int {
    b0: int = ord(buf[off]);
    b1: int = ord(buf[off + 1]);
    b2: int = ord(buf[off + 2]);
    b3: int = ord(buf[off + 3]);
    return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

def u16le(buf: str, off: int) -> int {
    lo: int = ord(buf[off]);
    hi: int = ord(buf[off + 1]);
    return lo | (hi << 8);
}

def wchar_to_utf8(c: int) -> str {
    if c <= 0 {
        return "";
    }
    if c < 0x80 {
        return chr(c);
    }
    if c < 0x800 {
        return chr(0xC0 | (c >> 6)) + chr(0x80 | (c & 0x3F));
    }
    return chr(0xE0 | (c >> 12)) + chr(0x80 | ((c >> 6) & 0x3F)) + chr(
        0x80 | (c & 0x3F)
    );
}

def _read_console_mode(handle: int) -> int {
    p: int = calloc(4, 1);
    mode_buf: str = p;
    ok: int = GetConsoleMode(handle, mode_buf);
    val: int = 0;
    if ok != 0 {
        val = read_u32(mode_buf, 0);
    }
    free(p);
    return val;
}

def tty_open -> int {
    return tty_open_dev("");
}

def tty_fd -> int {
    if g_tty.in_handle < 0 {
        return -1;
    }
    return 0;
}

def tty_open_dev(dev: str) -> int {
    AttachConsole(-1);
    in_h: int = GetStdHandle(-10);
    out_h: int = GetStdHandle(-11);
    if in_h == INVALID_HANDLE or out_h == INVALID_HANDLE {
        if AllocConsole() == 0 {
            return -1;
        }
        g_tty.allocated_console = 1;
        in_h = GetStdHandle(-10);
        out_h = GetStdHandle(-11);
        if in_h == INVALID_HANDLE or out_h == INVALID_HANDLE {
            return -1;
        }
    }

    g_tty.saved_in_mode = _read_console_mode(in_h);
    g_tty.saved_out_mode = _read_console_mode(out_h);

    new_in: int = g_tty.saved_in_mode & ~(
        ENABLE_PROCESSED_INPUT | ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT
    );
    if SetConsoleMode(in_h, new_in) == 0 {
        return -1;
    }

    new_out: int = g_tty.saved_out_mode | ENABLE_VT_PROCESSING;
    if SetConsoleMode(out_h, new_out) == 0 {
        SetConsoleMode(in_h, g_tty.saved_in_mode);
        return -1;
    }

    g_tty.in_handle = in_h;
    g_tty.out_handle = out_h;
    tty_update_size();
    return 0;
}

def tty_close {
    in_h: int = g_tty.in_handle;
    out_h: int = g_tty.out_handle;
    if in_h >= 0 {
        if SetConsoleMode(in_h, g_tty.saved_in_mode) == 0 {
            fallback: int = g_tty.saved_in_mode | ENABLE_PROCESSED_INPUT | ENABLE_LINE_INPUT;
            SetConsoleMode(in_h, fallback);
        }
    }
    if out_h >= 0 {
        if SetConsoleMode(out_h, g_tty.saved_out_mode) == 0 {
            fallback: int = g_tty.saved_out_mode & ~ENABLE_VT_PROCESSING;
            SetConsoleMode(out_h, fallback);
        }
    }
    g_tty.in_handle = -1;
    g_tty.out_handle = -1;
    if g_tty.allocated_console != 0 {
        FreeConsole();
        g_tty.allocated_console = 0;
    }
}

def tty_update_size {
    out_h: int = g_tty.out_handle;
    if out_h < 0 {
        return;
    }

    p: int = calloc(22, 1);
    info: str = p;
    if GetConsoleScreenBufferInfo(out_h, info) != 0 {
        left: int = u16le(info, 10);
        top: int = u16le(info, 12);
        right: int = u16le(info, 14);
        bottom: int = u16le(info, 16);
        col: int = right - left + 1;
        row: int = bottom - top + 1;
        if col > 0 {
            if row > 0 {
                g_tty.cols = col;
                g_tty.rows = row;
            }
        }
    }
    free(p);
}

def tty_rows -> int {
    return g_tty.rows;
}

def tty_cols -> int {
    return g_tty.cols;
}

def tty_x_pixels -> int {
    return 0;
}

def tty_y_pixels -> int {
    return 0;
}

def tty_poll(timeout_ms: int) {
    g_tty.stdin_ready = 0;
    g_tty.key_ready = 0;
    in_h: int = g_tty.in_handle;
    if in_h < 0 {
        return;
    }

    r: int = WaitForSingleObject(in_h, timeout_ms);
    if r == WAIT_OBJECT_0 {
        g_tty.key_ready = 1;
    }
}

def tty_stdin_ready -> int {
    return g_tty.stdin_ready;
}

def tty_key_ready -> int {
    return g_tty.key_ready;
}

def tty_write(fd: int, text: str) {
    out_h: int = g_tty.out_handle;
    if out_h < 0 {
        std_id: int = -11;
        if fd == 2 {
            std_id = -12;
        }
        out_h = GetStdHandle(std_id);
        if out_h <= 0 {
            return;
        }
    }
    n: int = len(text);
    if n <= 0 {
        return;
    }

    p: int = calloc(4, 1);
    written: str = p;
    WriteFile(out_h, text, n, written, 0);
    free(p);
}

def tty_read_key -> str {
    in_h: int = g_tty.in_handle;
    if in_h < 0 {
        return "";
    }

    rec_p: int = calloc(1, 20);
    cnt_p: int = calloc(1, 4);
    rec: str = rec_p;
    cnt: str = cnt_p;
    ok: int = ReadConsoleInputW(in_h, rec, 1, cnt);
    free(cnt_p);
    if ok == 0 {
        free(rec_p);
        return "";
    }

    evt: int = u16le(rec, 0);
    if evt != KEY_EVENT_TYPE {
        free(rec_p);
        return "";
    }
    key_down: int = read_u32(rec, 4);
    if key_down == 0 {
        free(rec_p);
        return "";
    }
    vk: int = u16le(rec, 10);
    uc: int = u16le(rec, 14);
    ctrl_state: int = read_u32(rec, 16);
    free(rec_p);

    shift: int = 0;
    if ctrl_state & SHIFT_PRESSED != 0 {
        shift = 1;
    }

    if vk == VK_BACK {
        return "\x7f";
    }
    if vk == VK_TAB {
        if shift != 0 {
            return "\x1b[Z";
        }
        return "\t";
    }
    if vk == VK_UP {
        return "\x1b[A";
    }
    if vk == VK_DOWN {
        return "\x1b[B";
    }
    if vk == VK_RIGHT {
        return "\x1b[C";
    }
    if vk == VK_LEFT {
        return "\x1b[D";
    }
    if vk == VK_HOME {
        return "\x1b[H";
    }
    if vk == VK_END {
        return "\x1b[F";
    }
    if vk == VK_PRIOR {
        return "\x1b[5~";
    }
    if vk == VK_NEXT {
        return "\x1b[6~";
    }
    if vk == VK_INSERT {
        return "\x1b[2~";
    }
    if vk == VK_DELETE {
        return "\x1b[3~";
    }

    if vk == VK_F1 {
        return "\x1bOP";
    }
    if vk == VK_F2 {
        return "\x1bOQ";
    }
    if vk == VK_F3 {
        return "\x1bOR";
    }
    if vk == VK_F4 {
        return "\x1bOS";
    }
    if vk == VK_F5 {
        return "\x1b[15~";
    }
    if vk == VK_F6 {
        return "\x1b[17~";
    }
    if vk == VK_F7 {
        return "\x1b[18~";
    }
    if vk == VK_F8 {
        return "\x1b[19~";
    }
    if vk == VK_F9 {
        return "\x1b[20~";
    }
    if vk == VK_F10 {
        return "\x1b[21~";
    }
    if vk == VK_F11 {
        return "\x1b[23~";
    }
    if vk == VK_F12 {
        return "\x1b[24~";
    }

    if uc > 0 {
        return wchar_to_utf8(uc);
    }

    return "";
}

def tty_read_line -> str {
    return "";
}

def tty_init_stdio_remap -> int {
    return -1;
}

def tty_restore_stdio { }

def tty_ipc_fd -> int {
    return -1;
}
