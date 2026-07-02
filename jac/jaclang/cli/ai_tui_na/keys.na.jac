enum KeyKind {
    CHAR = 1,
    CTRL = 2,
    ENTER = 3,
    SHIFT_ENTER = 4,
    BACKSPACE = 5,
    DELETE = 6,
    TAB = 7,
    ESCAPE = 8,
    UP = 9,
    DOWN = 10,
    LEFT = 11,
    RIGHT = 12,
    HOME = 13,
    END = 14,
    PAGE_UP = 15,
    PAGE_DOWN = 16,
    WORD_LEFT = 17,
    WORD_RIGHT = 18,
    MOUSE_SCROLL_UP = 19,
    MOUSE_SCROLL_DOWN = 20,
    UNKNOWN = 21,
}

obj Key {
    has kind: KeyKind = KeyKind.UNKNOWN,
        code: int = 0;
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

def parse_key(raw: str) -> Key {
    if len(raw) == 0 {
        return Key();
    }

    first = raw[0];
    code = ord(first);

    if code == 9 {
        return Key(kind=KeyKind.TAB);
    }
    if code == 13 or code == 10 {
        return Key(kind=KeyKind.ENTER);
    }
    if code == 127 or code == 8 {
        return Key(kind=KeyKind.BACKSPACE);
    }

    if code == 27 {
        if len(raw) == 1 {
            return Key(kind=KeyKind.ESCAPE);
        }

        last = raw[len(raw) - 1];

        if raw.startswith("\033[<") and (last == "M" or last == "m") {
            parts = raw[3:len(raw) - 1].split(";");
            if len(parts) > 0 {
                btn = _parse_uint(parts[0]);
                if btn == 64 {
                    return Key(kind=KeyKind.MOUSE_SCROLL_UP);
                }
                if btn == 65 {
                    return Key(kind=KeyKind.MOUSE_SCROLL_DOWN);
                }
            }
            return Key();
        }

        if raw == "\033\r" or raw == "\033[13;2~" {
            return Key(kind=KeyKind.SHIFT_ENTER);
        }

        if raw == "\033OA" or raw == "\033[A" {
            return Key(kind=KeyKind.UP);
        }
        if raw == "\033OB" or raw == "\033[B" {
            return Key(kind=KeyKind.DOWN);
        }
        if raw == "\033OC" or raw == "\033[C" {
            return Key(kind=KeyKind.RIGHT);
        }
        if raw == "\033OD" or raw == "\033[D" {
            return Key(kind=KeyKind.LEFT);
        }
        if raw == "\033OH" or raw == "\033[H" {
            return Key(kind=KeyKind.HOME);
        }
        if raw == "\033OF" or raw == "\033[F" {
            return Key(kind=KeyKind.END);
        }

        if raw == "\033[3~" {
            return Key(kind=KeyKind.DELETE);
        }

        if raw == "\033[5~" or raw == "\033[1;5A" {
            return Key(kind=KeyKind.PAGE_UP);
        }
        if raw == "\033[6~" or raw == "\033[1;5B" {
            return Key(kind=KeyKind.PAGE_DOWN);
        }

        if raw == "\033[1;5D"
        or raw == "\033[5D"
        or raw == "\033b"
        or raw == "\033[1;3D" {
            return Key(kind=KeyKind.WORD_LEFT);
        }
        if raw == "\033[1;5C"
        or raw == "\033[5C"
        or raw == "\033f"
        or raw == "\033[1;3C" {
            return Key(kind=KeyKind.WORD_RIGHT);
        }

        return Key();
    }

    if code >= 1 and code <= 26 {
        return Key(kind=KeyKind.CTRL, code=code + 96);
    }

    if code >= 32 and code <= 126 {
        return Key(kind=KeyKind.CHAR, code=code);
    }

    return Key();
}
