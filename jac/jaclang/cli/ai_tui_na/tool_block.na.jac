import from .terminal { ansi_sgr }
import from .width { visible_width, ansi_trunc, ansi_pad }
import from .state { DisplayRow, EventKind }
import from .theme {
    TH_BG_R,
    TH_BG_G,
    TH_BG_B,
    TH_CALL_R,
    TH_CALL_G,
    TH_CALL_B,
    TH_REASON_R,
    TH_REASON_G,
    TH_REASON_B,
    TH_ERROR_R,
    TH_ERROR_G,
    TH_ERROR_B,
    TH_STATUS_OK_R,
    TH_STATUS_OK_G,
    TH_STATUS_OK_B,
    TH_BOLD,
    TH_DIM
}

def tool_call_rows(tool_name: str, text: str, width: int, out: list[DisplayRow]) {
    name = tool_name;
    if len(name) == 0 {
        name = "tool";
    }

    name_sgr = ansi_sgr(
        TH_CALL_R, TH_CALL_G, TH_CALL_B, TH_BG_R, TH_BG_G, TH_BG_B, TH_BOLD
    );
    arg_sgr = ansi_sgr(
        TH_REASON_R, TH_REASON_G, TH_REASON_B, TH_BG_R, TH_BG_G, TH_BG_B, TH_DIM
    );

    name_vis = visible_width(name);
    header_vis = 2 + name_vis + 2;

    args_avail = width - header_vis;
    args_line: str = "";
    if args_avail > 2 {
        if len(text) > 0 {
            args_line = ansi_trunc(text, args_avail);
        }
    }

    row = name_sgr + "⚙ " + name + arg_sgr + "  " + args_line;
    row = ansi_pad(row, width);
    row = row + "\033[0m";
    out.append(
        DisplayRow(
            text=row, kind=EventKind.CALL, is_continuation=False, pre_styled=True
        )
    );
}

def tool_result_rows(tool_name: str, text: str, width: int, out: list[DisplayRow]) {
    is_err = len(text) == 0;

    icon_str: str = "✓ ";
    icon_r: int = TH_STATUS_OK_R;
    icon_g: int = TH_STATUS_OK_G;
    icon_b: int = TH_STATUS_OK_B;
    if is_err {
        icon_str = "✗ ";
        icon_r = TH_ERROR_R;
        icon_g = TH_ERROR_G;
        icon_b = TH_ERROR_B;
    }

    icon_sgr = ansi_sgr(icon_r, icon_g, icon_b, TH_BG_R, TH_BG_G, TH_BG_B, TH_BOLD);
    cont_sgr = ansi_sgr(
        TH_REASON_R, TH_REASON_G, TH_REASON_B, TH_BG_R, TH_BG_G, TH_BG_B, TH_DIM
    );

    body = text;
    if len(body) == 0 {
        body = "(empty)";
    }

    parts = body.split("\n");
    np = len(parts);
    i: int = 0;
    while i < np {
        line = parts[i];
        avail = width - 2;
        if avail < 1 {
            avail = 1;
        }
        content = ansi_trunc(line, avail);
        if i == 0 {
            row = icon_sgr + icon_str + cont_sgr + content;
            row = ansi_pad(row, width);
            row = row + "\033[0m";
            out.append(
                DisplayRow(
                    text=row,
                    kind=EventKind.TOOL_RESULT,
                    is_continuation=False,
                    pre_styled=True
                )
            );
        } else {
            row = cont_sgr + "  " + content;
            row = ansi_pad(row, width);
            row = row + "\033[0m";
            out.append(
                DisplayRow(
                    text=row,
                    kind=EventKind.TOOL_RESULT,
                    is_continuation=True,
                    pre_styled=True
                )
            );
        }
        i = i + 1;
    }
}
