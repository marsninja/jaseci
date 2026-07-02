import os;
import sys;
import from jaclang.cli.console { console }

impl truncate(text: str, limit: int = 12000) -> str {
    if len(text) > limit {
        extra = len(text) - limit;
        return text[:limit] + f"\n... [truncated, {extra} more chars]";
    }
    return text;
}


impl confirm(action: str) -> bool {
    if agent.cfg.yolo_mode {
        return True;
    }
    console.print(f"  needs approval: {action}", style="yellow");
    try {
        answer = input("  Allow this action? [y/N] ").strip().lower();
    } except EOFError {
        return False;
    }
    return answer in ("y", "yes");
}

impl _count_diags(diags: list) -> DiagnosticCounts {
    n_err = len(
        [
            d
            for d in diags
            if d.severity == "error"
        ]
    );
    return DiagnosticCounts(errors=n_err, warnings=len(diags) - n_err);
}

impl _term_output_enabled -> bool {
    if os.environ.get("JAC_AI_UI_ACTIVE", "").strip() == "1" {
        return False;
    }
    return sys.stdout.isatty() and os.environ.get("TERM", "") not in {"", "dumb"};
}

impl _term_print(*args: any, **kwargs: any) -> None {
    if not _term_output_enabled() {
        return;
    }
    console.print(*args, **kwargs);
}

impl _tool_result_is_error(result: str, tool_name: str = "") -> bool {
    text = result.strip();
    if not text {
        return False;
    }
    if text.startswith("Tool error:") {
        return True;
    }
    timeout_prefix = f"Tool '{tool_name}' timed out after " if tool_name else "Tool '";
    if text.startswith(timeout_prefix) and " timed out after " in text {
        return True;
    }
    return False;
}
