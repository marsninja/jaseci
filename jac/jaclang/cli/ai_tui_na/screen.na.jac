import from .state { TuiState, DisplayRow, EditorState }
import from .feed { build_rows }
import from .overlay { overlay_build_modal, overlay_composite }
import from .terminal { ansi_sgr, ansi_reset, term_spaces, term_dashes }
import from .width { visible_width, ansi_trunc, ansi_pad }
import from .theme {
    TH_BG_R,
    TH_BG_G,
    TH_BG_B,
    TH_BORDER_R,
    TH_BORDER_G,
    TH_BORDER_B,
    TH_BOLD,
    TH_DIM
}

glob _SB: str = "\033[0;38;2;70;70;100;48;2;18;18;28m",
     _ST: str = "\033[0;1;38;2;204;0;204;48;2;18;18;28m",
     _SC: str = "\033[0;38;2;86;182;194;48;2;18;18;28m",
     _SM: str = "\033[0;2;38;2;120;120;120;48;2;18;18;28m",
     _SR: str = "\033[0m",
     _USER_MSG: str = "\033[0;1;38;2;255;255;255;48;2;26;26;46m",
     _REASON_MSG: str = "\033[0;2;3;38;2;160;160;160;48;2;18;18;28m";

glob _AC_SEL: str = "\033[0;1;38;2;255;255;255;48;2;36;36;60m",
     _AC_SEL_DESC: str = "\033[0;38;2;180;180;220;48;2;36;36;60m",
     _AC_NORM: str = "\033[0;38;2;140;140;140;48;2;18;18;28m",
     _AC_NORM_DESC: str = "\033[0;2;38;2;100;100;100;48;2;18;18;28m";

def _cwd_short(cwd: str) -> str {
    slen = len(cwd);
    last: int = -1;
    i: int = slen - 1;
    while i >= 0 {
        if cwd[i] == "/" {
            last = i;
            break;
        }
        i = i - 1;
    }
    if last <= 0 {
        return cwd;
    }
    prev: int = -1;
    j: int = last - 1;
    while j >= 0 {
        if cwd[j] == "/" {
            prev = j;
            break;
        }
        j = j - 1;
    }
    if prev < 0 {
        return cwd;
    }
    return "~" + cwd[prev:];
}

def _kind_sgr(kind: str) -> str {
    if kind == "user" {
        return ansi_sgr(255, 255, 255, TH_BG_R, TH_BG_G, TH_BG_B, TH_BOLD);
    }
    if kind == "answer" {
        return ansi_sgr(220, 220, 220, TH_BG_R, TH_BG_G, TH_BG_B, 0);
    }
    if kind == "reasoning" {
        return _REASON_MSG;
    }
    if kind == "system" {
        return ansi_sgr(86, 182, 194, TH_BG_R, TH_BG_G, TH_BG_B, 0);
    }
    if kind == "logo" {
        return ansi_sgr(86, 182, 194, TH_BG_R, TH_BG_G, TH_BG_B, TH_BOLD);
    }
    if kind == "error" {
        return ansi_sgr(255, 80, 80, TH_BG_R, TH_BG_G, TH_BG_B, TH_BOLD);
    }
    if kind == "phase" {
        return ansi_sgr(255, 210, 60, TH_BG_R, TH_BG_G, TH_BG_B, 0);
    }
    if kind == "call" {
        return ansi_sgr(204, 119, 255, TH_BG_R, TH_BG_G, TH_BG_B, 0);
    }
    if kind == "tool_result" {
        return ansi_sgr(140, 140, 140, TH_BG_R, TH_BG_G, TH_BG_B, TH_DIM);
    }
    return ansi_sgr(200, 200, 200, TH_BG_R, TH_BG_G, TH_BG_B, 0);
}

def _status_footer_row(state: TuiState, cols: int) -> str {
    inner_w = cols - 4;

    act_disp: str = "";
    act_len: int = 0;
    if len(state.active) > 0 {
        act_max = inner_w - 3;
        if act_max > 0 {
            act_disp = ansi_trunc(state.active, act_max);
            act_len = visible_width(act_disp);
        }
    }

    model_s: str = state.model_name;
    if visible_width(model_s) == 0 {
        model_s = "no model";
    }
    model_len = visible_width(model_s);

    left_len = act_len;

    cwd_d = _cwd_short(state.cwd);
    cwd_avail = inner_w - left_len - model_len - 3;
    if cwd_avail < 0 {
        cwd_avail = 0;
    }
    cwd_disp = ansi_trunc(cwd_d, cwd_avail);
    cwd_len = visible_width(cwd_disp);

    right_len = cwd_len + model_len;
    if cwd_len > 0 {
        right_len = right_len + 1;
    }
    total_dashes = inner_w - left_len - right_len;
    if total_dashes < 1 {
        total_dashes = 1;
    }

    row: str = _SB + "│ ";
    if act_len > 0 {
        row = row + ansi_sgr(255, 210, 60, TH_BG_R, TH_BG_G, TH_BG_B, 0) + act_disp;
    }
    row = row + _SB + term_dashes(total_dashes);
    if cwd_len > 0 {
        row = row + _SC + cwd_disp + " ";
    }
    row = row + _SM + model_s + " " + _SB + "│" + _SR;
    return row;
}

def _divider_row(left: str, right: str, cols: int) -> str {
    fill = cols - 2;
    if fill < 0 {
        fill = 0;
    }
    return _SB + left + term_dashes(fill) + right + _SR;
}

def _transcript_row(dr: DisplayRow, cols: int) -> str {
    if dr.kind == "sep" {
        return _SB + "│" + term_spaces(cols - 2) + "│" + _SR;
    }

    inner_w = cols - 4;

    if dr.pre_styled {
        return _SB + "│ " + dr.text + _SB + " │" + _SR;
    }

    if dr.kind == "user" {
        content_w = inner_w - 1;
        display = ansi_trunc(dr.text, content_w);
        padded = ansi_pad(display, content_w);
        return _SB + "│ " + _USER_MSG + padded + " " + _SB + "│" + _SR;
    }

    display = ansi_trunc(dr.text, inner_w);
    row: str = _SB + "│ " + _kind_sgr(dr.kind) + display + " " + _SB + "│" + _SR;
    return row;
}

def _empty_border_row(cols: int) -> str {
    return _SB + "│" + term_spaces(cols - 2) + "│" + _SR;
}

def _warn_row(env: str, cols: int) -> str {
    inner_w = cols - 4;
    warn_text = ansi_trunc(
        f"  Missing API key: {env}  (/settings to configure)", inner_w
    );
    return _SB + "│ " + ansi_sgr(
        255, 80, 80, TH_BG_R, TH_BG_G, TH_BG_B, 0
    ) + warn_text + " " + _SB + "│" + _SR;
}

def _ac_item_row(label: str, desc: str, selected: bool, cols: int) -> str {
    inner_w = cols - 4;
    if inner_w < 4 {
        return _empty_border_row(cols);
    }
    label_max: int = 20;
    if label_max > inner_w - 6 {
        label_max = inner_w - 6;
    }
    if label_max < 1 {
        label_max = 1;
    }
    label_trunc = ansi_trunc(label, label_max);
    label_len = visible_width(label_trunc);
    pad_after = label_max - label_len;
    if pad_after < 0 {
        pad_after = 0;
    }
    desc_avail = inner_w - 2 - label_max - 2;
    if desc_avail < 0 {
        desc_avail = 0;
    }
    desc_trunc = ansi_trunc(desc, desc_avail);
    desc_len = visible_width(desc_trunc);
    total_len = 2 + label_len + pad_after + 2 + desc_len;
    trail = inner_w - total_len;
    if trail < 0 {
        trail = 0;
    }
    item_sgr: str = _AC_NORM;
    marker: str = "  ";
    desc_sgr: str = _AC_NORM_DESC;
    if selected {
        item_sgr = _AC_SEL;
        marker = "▸ ";
        desc_sgr = _AC_SEL_DESC;
    }
    row: str = _SB + "│ " + item_sgr + marker + label_trunc;
    if pad_after > 0 {
        row = row + term_spaces(pad_after);
    }
    row = row + "  " + desc_sgr + desc_trunc;
    if trail > 0 {
        row = row + term_spaces(trail);
    }
    row = row + _SB + " │" + _SR;
    return row;
}

def _idiv_s(a: int, b: int) -> int {
    if b <= 0 {
        return 0;
    }
    result: int = 0;
    rem: int = a;
    while rem >= b {
        rem = rem - b;
        result = result + 1;
    }
    return result;
}

def _ed_vl_count(line_len: int, width: int) -> int {
    if width <= 0 or line_len == 0 {
        return 1;
    }
    return _idiv_s(line_len + width - 1, width);
}

def _ed_total_vlines(ed: EditorState, width: int) -> int {
    total: int = 0;
    i: int = 0;
    n = len(ed.lines);
    while i < n {
        total = total + _ed_vl_count(len(ed.lines[i]), width);
        i = i + 1;
    }
    return total;
}

def _editor_rows(
    ed: EditorState, cols: int, max_rows: int, is_running: bool
) -> list[str] {
    text_w = cols - 6;
    if text_w < 1 {
        text_w = 1;
    }

    if is_running {
        prompt_sgr = ansi_sgr(120, 120, 120, TH_BG_R, TH_BG_G, TH_BG_B, TH_DIM);
    } else {
        prompt_sgr = ansi_sgr(255, 255, 255, TH_BG_R, TH_BG_G, TH_BG_B, TH_BOLD);
    }
    text_sgr = ansi_sgr(220, 220, 220, TH_BG_R, TH_BG_G, TH_BG_B, 0);
    cursor_sgr: str = "\033[7m";

    vis_texts: list[str] = [];
    vis_cursor_cols: list[int] = [];

    n_lines = len(ed.lines);
    i: int = 0;

    while i < n_lines {
        line = ed.lines[i];
        llen = len(line);
        vl_count = _ed_vl_count(llen, text_w);

        j: int = 0;
        while j < vl_count {
            chunk_start = j * text_w;
            chunk_end = chunk_start + text_w;
            if chunk_end > llen {
                chunk_end = llen;
            }
            chunk = line[chunk_start:chunk_end];
            vis_texts.append(chunk);

            if i == ed.cursor_line {
                cur_vsubline = _idiv_s(ed.cursor_col, text_w);
                if cur_vsubline == j {
                    vcol = ed.cursor_col - j * text_w;
                    vis_cursor_cols.append(vcol);
                } else {
                    vis_cursor_cols.append(-1);
                }
            } else {
                vis_cursor_cols.append(-1);
            }

            j = j + 1;
        }
        i = i + 1;
    }

    scroll = ed.scroll_offset;
    total_vl = len(vis_texts);
    if scroll < 0 {
        scroll = 0;
    }
    if scroll > total_vl - 1 {
        scroll = total_vl - 1;
    }
    if scroll < 0 {
        scroll = 0;
    }

    result: list[str] = [];
    row_vi: int = scroll;
    rows_emitted: int = 0;
    is_first_row: bool = True;

    while rows_emitted < max_rows {
        if row_vi < total_vl {
            chunk = vis_texts[row_vi];
            vcol = vis_cursor_cols[row_vi];
        } else {
            chunk = "";
            vcol = -1;
        }

        if vcol >= 0 {
            before = chunk[:vcol];
            if vcol < len(chunk) {
                cur_char = chunk[vcol];
                after = chunk[vcol + 1:];
                display = before + cursor_sgr + cur_char + "\033[0m" + after;
            } else {
                display = before + cursor_sgr + " " + "\033[0m";
            }
        } else {
            display = chunk;
        }

        dw = visible_width(display);
        if dw < text_w {
            display = display + term_spaces(text_w - dw);
        }

        if is_first_row {
            prefix = prompt_sgr + "› " + text_sgr;
            is_first_row = False;
        } else {
            prefix = text_sgr + "  ";
        }

        row: str = _SB + "│ " + prefix + display + " " + _SB + "│" + _SR;
        result.append(row);
        row_vi = row_vi + 1;
        rows_emitted = rows_emitted + 1;
    }

    return result;
}

def _editor_height(ed: EditorState, cols: int, rows: int) -> int {
    text_w = cols - 6;
    if text_w < 1 {
        text_w = 1;
    }
    total_vl = _ed_total_vlines(ed, text_w);
    max_h: int = rows - 3;
    if max_h < 1 {
        max_h = 1;
    }
    if max_h > 10 {
        max_h = 10;
    }
    if total_vl < 1 {
        total_vl = 1;
    }
    if total_vl < max_h {
        return total_vl;
    }
    return max_h;
}

def screen_render(state: TuiState, cols: int, rows: int) -> list[str] {
    out: list[str] = [];

    if cols < 10 or rows < 6 {
        i: int = 0;
        while i < rows {
            out.append("");
            i = i + 1;
        }
        return out;
    }

    ed = state.editor;
    editor_h = _editor_height(ed, cols, rows);
    is_running = state.status == "running";

    ac_h: int = 0;
    if state.ac.active {
        ac_h = len(state.ac.items);
        if ac_h > 8 {
            ac_h = 8;
        }
    }

    transcript_h = rows - 1 - editor_h - ac_h - 1;
    if transcript_h < 0 {
        transcript_h = 0;
    }

    t_draw_h = transcript_h;
    show_warn: bool = False;
    if state.needs_key {
        show_warn = True;
        t_draw_h = transcript_h - 1;
        if t_draw_h < 0 {
            t_draw_h = 0;
        }
    }

    if state.layout_dirty or state.layout_cols != cols {
        build_rows(state);
    }

    drows = state.display_rows;
    total = len(drows);

    max_top = total - t_draw_h;
    if max_top < 0 {
        max_top = 0;
    }
    if state.follow_tail {
        state.viewport_top = max_top;
    }
    if state.viewport_top > max_top {
        state.viewport_top = max_top;
    }
    if state.viewport_top < 0 {
        state.viewport_top = 0;
    }

    if not state.follow_tail and state.viewport_top >= max_top {
        state.follow_tail = True;
    }

    row_idx = state.viewport_top;
    t_shown: int = 0;
    while t_shown < t_draw_h {
        if row_idx < total {
            out.append(_transcript_row(drows[row_idx], cols));
            row_idx = row_idx + 1;
        } else {
            out.append(_empty_border_row(cols));
        }
        t_shown = t_shown + 1;
    }

    if show_warn {
        env = state.key_env;
        if len(env) == 0 {
            env = "API_KEY";
        }
        out.append(_warn_row(env, cols));
    }

    if state.ac.active and ac_h > 0 {
        ac_i: int = 0;
        while ac_i < ac_h {
            item = state.ac.items[ac_i];
            is_sel: bool = False;
            if ac_i == state.ac.selected_idx {
                is_sel = True;
            }
            out.append(_ac_item_row(item.label, item.description, is_sel, cols));
            ac_i = ac_i + 1;
        }
    }

    editor_rows = _editor_rows(ed, cols, editor_h, is_running);

    out.append(_divider_row("├", "┤", cols));

    ri: int = 0;
    while ri < editor_h {
        out.append(editor_rows[ri]);
        ri = ri + 1;
    }

    out.append(_status_footer_row(state, cols));

    if state.overlay_active {
        modal = overlay_build_modal(state, cols, rows);
        out = overlay_composite(out, modal, cols, rows);
    }

    return out;
}
