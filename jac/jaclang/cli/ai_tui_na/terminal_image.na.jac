import os;
import from .libc_tty { tty_rows, tty_cols, tty_x_pixels, tty_y_pixels }

def _getenv(name: str) -> str {
    v = os.getenv(name);
    if v is None {
        return "";
    }
    return v;
}

def detect_image_protocol -> str {
    if len(_getenv("TMUX")) > 0 {
        return "";
    }
    term: str = _getenv("TERM");
    if term.startswith("tmux") or term.startswith("screen") {
        return "";
    }

    if len(_getenv("KITTY_WINDOW_ID")) > 0 {
        return "kitty";
    }
    term_prog: str = _getenv("TERM_PROGRAM");
    if term_prog == "kitty" {
        return "kitty";
    }
    if term_prog == "ghostty" {
        return "kitty";
    }
    if len(_getenv("GHOSTTY_RESOURCES_DIR")) > 0 {
        return "kitty";
    }
    if term.find("ghostty") >= 0 {
        return "kitty";
    }
    if len(_getenv("WEZTERM_PANE")) > 0 {
        return "kitty";
    }
    if term_prog == "wezterm" {
        return "kitty";
    }

    if len(_getenv("ITERM_SESSION_ID")) > 0 {
        return "iterm2";
    }
    if term_prog == "iterm.app" {
        return "iterm2";
    }

    return "";
}

def detect_hyperlinks -> bool {
    if len(_getenv("TMUX")) > 0 {
        return False;
    }
    term: str = _getenv("TERM");
    if term.startswith("screen") {
        return False;
    }

    if len(_getenv("KITTY_WINDOW_ID")) > 0 {
        return True;
    }
    term_prog: str = _getenv("TERM_PROGRAM");
    if term_prog == "kitty" {
        return True;
    }
    if term_prog == "ghostty" {
        return True;
    }
    if len(_getenv("GHOSTTY_RESOURCES_DIR")) > 0 {
        return True;
    }
    if term.find("ghostty") >= 0 {
        return True;
    }
    if len(_getenv("WEZTERM_PANE")) > 0 {
        return True;
    }
    if term_prog == "wezterm" {
        return True;
    }
    if len(_getenv("ITERM_SESSION_ID")) > 0 {
        return True;
    }
    if term_prog == "iterm.app" {
        return True;
    }
    if len(_getenv("WT_SESSION")) > 0 {
        return True;
    }
    if term_prog == "vscode" {
        return True;
    }
    if term_prog == "alacritty" {
        return True;
    }
    return False;
}

def term_hyperlink(text: str, url: str) -> str {
    if not detect_hyperlinks() {
        return text + " (" + url + ")";
    }
    return "\033]8;;" + url + "\033\\" + text + "\033]8;;\033\\";
}

def _encode_kitty(b64: str, cols: int, img_rows: int, img_id: int) -> str {
    chunk_sz: int = 4096;
    params: str = "a=T,f=100,q=2";
    if cols > 0 {
        params = params + f",c={cols}";
    }
    if img_rows > 0 {
        params = params + f",r={img_rows}";
    }
    if img_id > 0 {
        params = params + f",i={img_id}";
    }

    n = len(b64);
    if n <= chunk_sz {
        return "\033_G" + params + ";" + b64 + "\033\\";
    }

    result: str = "";
    offset: int = 0;
    first: bool = True;
    while offset < n {
        chunk = b64[offset:offset + chunk_sz];
        is_last: bool = (offset + chunk_sz) >= n;
        if first {
            result = result + "\033_G" + params + ",m=1;" + chunk + "\033\\";
            first = False;
        } else {
            if is_last {
                result = result + "\033_Gm=0;" + chunk + "\033\\";
            } else {
                result = result + "\033_Gm=1;" + chunk + "\033\\";
            }
        }
        offset = offset + chunk_sz;
    }
    return result;
}

def _encode_iterm2(b64: str, cols: int) -> str {
    params: str = "inline=1";
    if cols > 0 {
        params = params + f";width={cols}";
    }
    params = params + ";height=auto;preserveAspectRatio=1";
    return "\033]1337;File=" + params + ":" + b64 + "\007";
}

def image_fallback(mime: str, w_px: int, h_px: int) -> str {
    return f"[Image: {mime} {w_px}x{h_px}]";
}

def _cell_px_w -> int {
    xpx = tty_x_pixels();
    cols = tty_cols();
    if xpx > 0 and cols > 0 {
        return xpx // cols;
    }
    return 9;
}

def _cell_px_h -> int {
    ypx = tty_y_pixels();
    rows = tty_rows();
    if ypx > 0 and rows > 0 {
        return ypx // rows;
    }
    return 18;
}

def image_rows(b64: str, mime: str, w_px: int, h_px: int, inner_w: int) -> list[str] {
    result: list[str] = [];
    proto = detect_image_protocol();

    if proto == "" {
        result.append(image_fallback(mime, w_px, h_px));
        return result;
    }

    if w_px <= 0 {
        w_px = 1;
    }
    if h_px <= 0 {
        h_px = 1;
    }
    if inner_w <= 0 {
        inner_w = 1;
    }

    cpx_w = _cell_px_w();
    cpx_h = _cell_px_h();
    if cpx_w <= 0 {
        cpx_w = 9;
    }
    if cpx_h <= 0 {
        cpx_h = 18;
    }

    max_px_w = inner_w * cpx_w;

    scale_num: int = max_px_w * 1000;
    scale_k = scale_num // w_px;

    scaled_w_px = w_px * scale_k // 1000;
    scaled_h_px = h_px * scale_k // 1000;

    img_cols = (scaled_w_px + cpx_w - 1) // cpx_w;
    img_cell_rows = (scaled_h_px + cpx_h - 1) // cpx_h;

    if img_cols < 1 {
        img_cols = 1;
    }
    if img_cell_rows < 1 {
        img_cell_rows = 1;
    }
    if img_cols > inner_w {
        img_cols = inner_w;
    }

    if proto == "kitty" {
        result.append(_encode_kitty(b64, img_cols, img_cell_rows, 0));
    } else {
        result.append(_encode_iterm2(b64, img_cols));
    }

    i: int = 1;
    while i < img_cell_rows {
        result.append("");
        i = i + 1;
    }

    return result;
}
