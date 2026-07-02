def idiv(a: int, b: int) -> int {
    if b <= 0 {
        return 0;
    }
    return a // b;
}

def _is_csi_final(c: int) -> bool {
    return c >= 64 and c <= 126;
}

def _utf8_seq_len(lead: int) -> int {
    if lead >= 240 {
        return 4;
    }
    if lead >= 224 {
        return 3;
    }
    if lead >= 192 {
        return 2;
    }
    return 1;
}

def _skip_ansi_at(s: str, i: int) -> int {
    n = len(s);
    if i + 1 >= n {
        return i + 1;
    }
    nc = ord(s[i + 1]);
    if nc == 91 {
        j = i + 2;
        while j < n and not _is_csi_final(ord(s[j])) {
            j = j + 1;
        }
        return j + 1;
    }
    if nc == 93 or nc == 95 {
        j = i + 2;
        while j < n {
            bc = ord(s[j]);
            if bc == 7 {
                return j + 1;
            }
            if bc == 27 and j + 1 < n and ord(s[j + 1]) == 92 {
                return j + 2;
            }
            j = j + 1;
        }
        return j;
    }

    return i + 2;
}

def visible_width(s: str) -> int {
    n = len(s);
    if n == 0 {
        return 0;
    }
    w: int = 0;
    i: int = 0;
    while i < n {
        c = ord(s[i]);
        if c == 27 {
            i = _skip_ansi_at(s, i);
            continue;
        }
        if c >= 32 and c <= 126 {
            w = w + 1;
            i = i + 1;
            continue;
        }
        if c >= 194 {
            seq = _utf8_seq_len(c);
            w = w + 1;
            i = i + seq;
            continue;
        }

        i = i + 1;
    }
    return w;
}

def ansi_trunc(s: str, width: int) -> str {
    if width <= 0 {
        return "";
    }
    if visible_width(s) <= width {
        return s;
    }

    target = width - 1;
    result: str = "";
    vis: int = 0;
    i: int = 0;
    n = len(s);
    while i < n and vis < target {
        c = ord(s[i]);
        if c == 27 {
            j = _skip_ansi_at(s, i);
            result = result + s[i:j];
            i = j;
            continue;
        }
        if c >= 32 and c <= 126 {
            result = result + s[i];
            vis = vis + 1;
            i = i + 1;
            continue;
        }
        if c >= 194 {
            seq = _utf8_seq_len(c);
            end_j = i + seq;
            if end_j > n {
                end_j = n;
            }
            result = result + s[i:end_j];
            vis = vis + 1;
            i = end_j;
            continue;
        }

        i = i + 1;
    }
    return result + "~";
}

def ansi_pad(s: str, width: int) -> str {
    vw = visible_width(s);
    if vw >= width {
        return s;
    }
    pad = width - vw;
    result: str = s;
    i: int = 0;
    while i < pad {
        result = result + " ";
        i = i + 1;
    }
    return result;
}
