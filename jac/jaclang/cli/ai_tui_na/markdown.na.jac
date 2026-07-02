import from .terminal { ansi_sgr, term_spaces, term_dashes }
import from .width { visible_width, ansi_pad }
import from .terminal_image { term_hyperlink }
import from .theme {
    TH_BG_R,
    TH_BG_G,
    TH_BG_B,
    TH_MD_H1_R,
    TH_MD_H1_G,
    TH_MD_H1_B,
    TH_MD_H2_R,
    TH_MD_H2_G,
    TH_MD_H2_B,
    TH_MD_H3_R,
    TH_MD_H3_G,
    TH_MD_H3_B,
    TH_MD_CODE_R,
    TH_MD_CODE_G,
    TH_MD_CODE_B,
    TH_MD_CODE_BG_R,
    TH_MD_CODE_BG_G,
    TH_MD_CODE_BG_B,
    TH_MD_FENCE_R,
    TH_MD_FENCE_G,
    TH_MD_FENCE_B,
    TH_MD_BQ_R,
    TH_MD_BQ_G,
    TH_MD_BQ_B,
    TH_MD_BQ_BAR_R,
    TH_MD_BQ_BAR_G,
    TH_MD_BQ_BAR_B,
    TH_MD_HR_R,
    TH_MD_HR_G,
    TH_MD_HR_B,
    TH_NONE,
    TH_BOLD,
    TH_DIM,
    TH_ITALIC
}

def _md_is_blank(s: str) -> bool {
    i: int = 0;
    n = len(s);
    while i < n {
        c = s[i];
        if c != " " and c != "\t" and c != "\r" {
            return False;
        }
        i = i + 1;
    }
    return True;
}

def _md_is_fence(s: str) -> bool {
    n = len(s);
    if n < 3 {
        return False;
    }
    return s[0] == "`" and s[1] == "`" and s[2] == "`";
}

def _md_fence_lang(s: str) -> str {
    if len(s) <= 3 {
        return "";
    }
    lang = s[3:];
    i: int = 0;
    nl = len(lang);
    while i < nl and (lang[i] == " " or lang[i] == "\t") {
        i = i + 1;
    }
    return lang[i:];
}

def _md_heading_level(s: str) -> int {
    n = len(s);
    if n < 2 or s[0] != "#" {
        return 0;
    }
    if s[1] == " " {
        return 1;
    }
    if s[1] == "#" {
        if n < 3 {
            return 0;
        }
        if s[2] == " " {
            return 2;
        }
        if s[2] == "#" and n >= 4 and s[3] == " " {
            return 3;
        }
    }
    return 0;
}

def _md_heading_text(s: str, level: int) -> str {
    h_skip = level + 1;
    if len(s) <= h_skip {
        return "";
    }
    return s[h_skip:];
}

def _md_is_hr(s: str) -> bool {
    n = len(s);
    if n < 3 {
        return False;
    }
    c = s[0];
    if c != "-" and c != "_" and c != "*" {
        return False;
    }
    count: int = 0;
    i: int = 0;
    while i < n {
        ch = s[i];
        if ch == c {
            count = count + 1;
        } else {
            if ch != " " {
                return False;
            }
        }
        i = i + 1;
    }
    return count >= 3;
}

def _md_is_ul(s: str) -> bool {
    n = len(s);
    if n < 2 {
        return False;
    }
    c = s[0];
    return (c == "-" or c == "*" or c == "+") and s[1] == " ";
}

def _md_is_ol(s: str) -> bool {
    n = len(s);
    if n < 3 {
        return False;
    }
    i: int = 0;
    while i < n and s[i] >= "0" and s[i] <= "9" {
        i = i + 1;
    }
    if i == 0 or i + 1 >= n {
        return False;
    }
    return s[i] == "." and s[i + 1] == " ";
}

def _md_ol_marker_end(s: str) -> int {
    n = len(s);
    i: int = 0;
    while i < n and s[i] >= "0" and s[i] <= "9" {
        i = i + 1;
    }
    return i + 2;
}

def _md_is_bq(s: str) -> bool {
    return len(s) >= 1 and s[0] == ">";
}

def _md_bq_text(s: str) -> str {
    if len(s) <= 1 {
        return "";
    }
    if s[1] == " " {
        return s[2:];
    }
    return s[1:];
}

def _md_find_close(s: str, start: int, delim: str, dlen: int) -> int {
    n = len(s);
    i: int = start;
    while i + dlen <= n {
        if s[i:i + dlen] == delim {
            return i;
        }
        i = i + 1;
    }
    return -1;
}

def _md_apply_inline(s: str, base_sgr: str) -> str {
    result: str = "";
    i: int = 0;
    n = len(s);
    while i < n {
        c = s[i];

        if c == "`" {
            j = _md_find_close(s, i + 1, "`", 1);
            if j >= 0 {
                result = result + "\033[33m" + s[i + 1:j] + "\033[0m" + base_sgr;
                i = j + 1;
                continue;
            }
        }

        if c == "*" and i + 1 < n and s[i + 1] == "*" {
            j = _md_find_close(s, i + 2, "**", 2);
            if j >= 0 {
                result = result + "\033[1m" + s[i + 2:j] + "\033[0m" + base_sgr;
                i = j + 2;
                continue;
            }
        }

        if c == "*" and (i + 1 >= n or s[i + 1] != "*") {
            j = _md_find_close(s, i + 1, "*", 1);
            if j > i + 1 {
                result = result + "\033[3m" + s[i + 1:j] + "\033[0m" + base_sgr;
                i = j + 1;
                continue;
            }
        }

        if c == "~" and i + 1 < n and s[i + 1] == "~" {
            j = _md_find_close(s, i + 2, "~~", 2);
            if j >= 0 {
                result = result + "\033[9m" + s[i + 2:j] + "\033[0m" + base_sgr;
                i = j + 2;
                continue;
            }
        }

        if c == "[" {
            j = _md_find_close(s, i + 1, "]", 1);
            if j > i {
                if j + 1 < n {
                    if s[j + 1] == "(" {
                        k = _md_find_close(s, j + 2, ")", 1);
                        if k > j + 1 {
                            link_text = s[i + 1:j];
                            link_url = s[j + 2:k];
                            result = result + term_hyperlink(link_text, link_url);
                            i = k + 1;
                            continue;
                        }
                    }
                }
            }
        }

        result = result + s[i];
        i = i + 1;
    }
    return result;
}

def _md_wrap(styled: str, width: int, base_sgr: str) -> list[str] {
    result: list[str] = [];
    words = styled.split(" ");
    current: str = "";
    current_w: int = 0;
    i: int = 0;
    nw = len(words);

    while i < nw {
        word = words[i];
        ww = visible_width(word);

        if current_w == 0 {
            current = word;
            current_w = ww;
        } else {
            if current_w + 1 + ww <= width {
                current = current + " " + word;
                current_w = current_w + 1 + ww;
            } else {
                result.append(base_sgr + ansi_pad(current, width) + "\033[0m");
                current = word;
                current_w = ww;
            }
        }
        i = i + 1;
    }

    if current_w > 0 or len(result) == 0 {
        result.append(base_sgr + ansi_pad(current, width) + "\033[0m");
    }

    return result;
}

def _md_append(src: list[str], dst: list[str]) {
    i: int = 0;
    n = len(src);
    while i < n {
        dst.append(src[i]);
        i = i + 1;
    }
}

def md_render(text: str, width: int, r: int, g: int, b: int, attrs: int) -> list[str] {
    base_sgr = ansi_sgr(r, g, b, TH_BG_R, TH_BG_G, TH_BG_B, attrs);
    result: list[str] = [];

    h1_sgr = ansi_sgr(
        TH_MD_H1_R, TH_MD_H1_G, TH_MD_H1_B, TH_BG_R, TH_BG_G, TH_BG_B, TH_BOLD
    );
    h2_sgr = ansi_sgr(
        TH_MD_H2_R, TH_MD_H2_G, TH_MD_H2_B, TH_BG_R, TH_BG_G, TH_BG_B, TH_BOLD
    );
    h3_sgr = ansi_sgr(
        TH_MD_H3_R, TH_MD_H3_G, TH_MD_H3_B, TH_BG_R, TH_BG_G, TH_BG_B, TH_BOLD
    );
    code_line_sgr = ansi_sgr(
        TH_MD_CODE_R,
        TH_MD_CODE_G,
        TH_MD_CODE_B,
        TH_MD_CODE_BG_R,
        TH_MD_CODE_BG_G,
        TH_MD_CODE_BG_B,
        TH_NONE
    );
    code_fence_sgr = ansi_sgr(
        TH_MD_FENCE_R, TH_MD_FENCE_G, TH_MD_FENCE_B, TH_BG_R, TH_BG_G, TH_BG_B, TH_DIM
    );
    bq_text_sgr = ansi_sgr(
        TH_MD_BQ_R, TH_MD_BQ_G, TH_MD_BQ_B, TH_BG_R, TH_BG_G, TH_BG_B, TH_ITALIC
    );
    bq_bar_sgr = ansi_sgr(
        TH_MD_BQ_BAR_R,
        TH_MD_BQ_BAR_G,
        TH_MD_BQ_BAR_B,
        TH_BG_R,
        TH_BG_G,
        TH_BG_B,
        TH_NONE
    );
    hr_sgr = ansi_sgr(
        TH_MD_HR_R, TH_MD_HR_G, TH_MD_HR_B, TH_BG_R, TH_BG_G, TH_BG_B, TH_DIM
    );

    lines = text.split("\n");
    in_fence: bool = False;
    i: int = 0;
    nlines = len(lines);

    while i < nlines {
        line = lines[i];

        ll = len(line);
        if ll > 0 and line[ll - 1] == "\r" {
            line = line[:ll - 1];
        }

        if in_fence {
            if _md_is_fence(line) {
                close_row = code_fence_sgr + "```";
                result.append(ansi_pad(close_row, width) + "\033[0m");
                in_fence = False;
            } else {
                code_row = code_line_sgr + "  " + line;
                result.append(ansi_pad(code_row, width) + "\033[0m");
            }
            i = i + 1;
            continue;
        }

        if _md_is_blank(line) {
            result.append(base_sgr + ansi_pad("", width) + "\033[0m");
            i = i + 1;
            continue;
        }

        if _md_is_fence(line) {
            lang = _md_fence_lang(line);
            fence_label: str = "```";
            if len(lang) > 0 {
                fence_label = "```" + lang;
            }
            open_row = code_fence_sgr + fence_label;
            result.append(ansi_pad(open_row, width) + "\033[0m");
            in_fence = True;
            i = i + 1;
            continue;
        }

        lvl = _md_heading_level(line);
        if lvl > 0 {
            h_text = _md_heading_text(line, lvl);
            h_sgr = h1_sgr;
            if lvl == 2 {
                h_sgr = h2_sgr;
            }
            if lvl == 3 {
                h_sgr = h3_sgr;
            }
            styled = _md_apply_inline(h_text, h_sgr);
            wrapped = _md_wrap(styled, width, h_sgr);
            _md_append(wrapped, result);
            i = i + 1;
            continue;
        }

        if _md_is_hr(line) {
            hr_w = width;
            if hr_w > 80 {
                hr_w = 80;
            }
            hr_content = hr_sgr + term_dashes(hr_w);
            result.append(ansi_pad(hr_content, width) + "\033[0m");
            i = i + 1;
            continue;
        }

        if _md_is_ul(line) {
            item_text = line[2:];
            styled = _md_apply_inline(item_text, base_sgr);
            avail = width - 2;
            if avail < 1 {
                avail = 1;
            }
            wrapped = _md_wrap(styled, avail, base_sgr);
            nw = len(wrapped);
            j: int = 0;
            while j < nw {
                if j == 0 {
                    row = base_sgr + "• " + wrapped[j];
                } else {
                    row = base_sgr + "  " + wrapped[j];
                }
                result.append(row);
                j = j + 1;
            }
            i = i + 1;
            continue;
        }

        if _md_is_ol(line) {
            mend = _md_ol_marker_end(line);
            marker = line[:mend];
            item_text = line[mend:];
            styled = _md_apply_inline(item_text, base_sgr);
            marker_w = len(marker);
            avail = width - marker_w;
            if avail < 1 {
                avail = 1;
            }
            cont_pad = term_spaces(marker_w);
            wrapped = _md_wrap(styled, avail, base_sgr);
            nw = len(wrapped);
            j: int = 0;
            while j < nw {
                if j == 0 {
                    row = base_sgr + marker + wrapped[j];
                } else {
                    row = base_sgr + cont_pad + wrapped[j];
                }
                result.append(row);
                j = j + 1;
            }
            i = i + 1;
            continue;
        }

        if _md_is_bq(line) {
            bq_text = _md_bq_text(line);
            styled = _md_apply_inline(bq_text, bq_text_sgr);
            avail = width - 2;
            if avail < 1 {
                avail = 1;
            }
            wrapped = _md_wrap(styled, avail, bq_text_sgr);
            nw = len(wrapped);
            j: int = 0;
            while j < nw {
                row = bq_bar_sgr + "│ " + wrapped[j];
                result.append(row);
                j = j + 1;
            }
            i = i + 1;
            continue;
        }

        styled = _md_apply_inline(line, base_sgr);
        wrapped = _md_wrap(styled, width, base_sgr);
        _md_append(wrapped, result);

        i = i + 1;
    }

    return result;
}
