import os;
import sys;
import time;

impl TurnRenderer.print_banner{
    _term_print("");
    _term_print("  Jac AI -- interactive coding agent", style="bold");
    _term_print(
        f"  model: {agent_model.model_name}  (from {agent.cfg.model_source})",
        style="muted"
    );
    if agent.cfg.threads > 0 {
        _term_print(f"  inference threads: {agent.cfg.threads}", style="muted");
    }
    if agent.cfg.yolo_mode {
        _term_print(
            "  file writes and commands run without confirmation (use --safe to confirm each)",
            style="yellow"
        );
    }
    _term_print("  type a request, /help for commands, /exit to quit", style="muted");
    _term_print("");
}

impl TurnRenderer.print_help{
    cmds = _host_cmds();
    width = 0;
    for c in cmds {
        if len(c.help_label) > width {
            width = len(c.help_label);
        }
    }
    for c in cmds {
        _term_print(f"  {c.help_label.ljust(width)}  {c.help_desc}", style="muted");
    }
}

impl TurnRenderer.fmt_tool_call(tool: str, args: object) -> str {
    parts: list[str] = [];
    if isinstance(args, dict) {
        for (key, value) in args.items() {
            sval = str(value).replace("\n", " ");
            if len(sval) > 60 {
                sval = sval[:60] + "...";
            }
            parts.append(f"{key}={sval}");
        }
    }
    return f"{tool}(" + ", ".join(parts) + ")";
}

impl TurnRenderer._short_num(n: int) -> str {
    return f"{n / 1000:.1f}k" if n >= 1000 else str(n);
}

impl TurnRenderer._estimate_cost(prompt_tokens: int, completion_tokens: int) -> float {
    try {
        import litellm;
        costs: any = litellm.cost_per_token(
            model=agent_model.model_name,
            prompt_tokens=prompt_tokens,
            completion_tokens=completion_tokens
        );
        return float(str(costs[0])) + float(str(costs[1]));
    } except Exception {
        return 0.0;
    }
}

impl TurnRenderer._format_tokens(usage: dict[str, object]) -> str {
    prompt = int(usage.get("prompt_tokens", 0) or 0);
    completion = int(usage.get("completion_tokens", 0) or 0);
    if prompt == 0 and completion == 0 {
        return "";
    }
    text = f"{agent.view._short_num(prompt)} in / {agent.view._short_num(
        completion
    )} out";
    cost = agent.view._estimate_cost(prompt, completion);
    if cost > 0 {
        text += f" (~${cost:.4f})";
    }
    return text;
}

impl TurnRenderer._format_health -> str {
    ci = agent.ws.code_intel();
    if ci is None or not ci.is_loaded() {
        return "";
    }
    try {
        diags: list[any] = list(ci.diagnostics());
    } except Exception {
        return "";
    }
    (n_err, n_warn) = _count_diags(diags);
    if n_err == 0 and n_warn == 0 {
        return "project: clean";
    }
    return f"project: {n_err} error(s), {n_warn} warning(s)";
}

impl TurnRenderer.print_stats(
    elapsed: float,
    n_read: int,
    n_write: int,
    n_run: int,
    files: set[str],
    usage: dict[str, object]
) {
    parts: list[str] = [f"{elapsed:.1f}s"];
    n_tools = n_read + n_write + n_run;
    if n_tools > 0 {
        breakdown: list[str] = [];
        if n_read {
            breakdown.append(f"{n_read} read");
        }
        if n_write {
            breakdown.append(f"{n_write} write");
        }
        if n_run {
            breakdown.append(f"{n_run} run");
        }
        parts.append(f"{n_tools} tools (" + ", ".join(breakdown) + ")");
    }
    if files {
        suffix = "" if len(files) == 1 else "s";
        parts.append(f"{len(files)} file{suffix} changed");
    }
    tokens = agent.view._format_tokens(usage);
    if tokens {
        parts.append(tokens);
    }

    completion = int(usage.get("completion_tokens", 0) or 0);
    if completion > 0 and elapsed > 0 {
        parts.append(f"{completion / elapsed:.1f} tok/s");
    }
    health = agent.view._format_health();
    if health {
        parts.append(health);
    }
    _term_print("  " + "  ·  ".join(parts), style="muted");
}

impl TurnRenderer._strip_control(text: str) -> str {
    import re;
    t = text.replace("<|\"|>", "\"").replace("<|'|>", "'");
    t = re.sub("<\\|[a-z_]+>[a-z]*", "", t);
    t = re.sub("<[a-z_]+\\|>", "", t);
    return t;
}

impl TurnRenderer._split_reasoning(raw: str) -> tuple[str, bool] {
    mark = "<tool_call>";
    idx = raw.find(mark);
    if idx >= 0 {
        return (raw[:idx], True);
    }
    hold = 0;
    k = min(len(raw), len(mark) - 1);
    while k > 0 {
        if mark.startswith(raw[len(raw) - k:]) {
            hold = k;
            break;
        }
        k -= 1;
    }
    return (raw[:len(raw) - hold], False);
}

impl TurnRenderer._result_snippet(text: str, max_lines: int) -> list[str] {
    stripped = text.strip();
    if not stripped {
        return ["(no output)"];
    }
    lines = stripped.splitlines();
    shown: list[str] = [];
    for ln in lines[:max_lines] {
        shown.append(ln[:100] + "..." if len(ln) > 100 else ln);
    }
    rest = len(lines) - min(len(lines), max_lines);
    if rest > 0 {
        shown.append(f"(+{rest} more lines)");
    }
    return shown;
}

impl TurnRenderer._fmt_ms(ms: float) -> str {
    return f"{int(ms)}ms" if ms < 1000 else f"{ms / 1000:.1f}s";
}

impl TurnRenderer._fmt_gen(ms: float, tokens: int) -> str {
    if ms <= 0 {
        return "";
    }
    if tokens > 0 {
        tps = tokens / (ms / 1000);
        return f"   ({agent.view._fmt_ms(ms)}, {tps:.0f} tps)";
    }
    return f"   ({agent.view._fmt_ms(ms)})";
}

impl TurnRenderer._ci_event(info: any) {
    op = str(info.get("op", "?"));
    recompiled = int(info.get("recompiled", 0));
    cached = int(info.get("cached", 0));
    total = int(info.get("total", 0));
    raw_ms = info.get("ms", 0.0);
    ms = raw_ms if isinstance(raw_ms, float) else 0.0;
    fname: str = str(info.get("file", ""));
    name = os.path.basename(fname);
    if op == "load" {
        what = f"load · compiled {recompiled} files";
        if cached {
            what += f" · {cached} from cache";
        }
    } else {
        what = f"{op} {name} · recompiled {recompiled}/{total}";
    }
    _term_print(f"      ⚙ code intel · {what} · {agent.view._fmt_ms(ms)}", style="dim");
}

impl TurnRenderer._emit_call_usage(data: any, phase: str) -> None {
    if not agent.bus.active_feed {
        return;
    }
    d = data if isinstance(data, dict) else {};
    tin = int(d.get("prompt_tokens", 0) or 0);
    tout = int(d.get("completion_tokens", 0) or 0);

    if tin == 0 and tout == 0 {
        return;
    }

    agent.bus.emit_call(
        {
            "node": phase,
            "tokens_in": tin,
            "tokens_out": tout,
            "cache_read": int(d.get("cache_read_input_tokens", 0) or 0),
            "cache_create": int(d.get("cache_creation_input_tokens", 0) or 0),
            "ms": float(d.get("duration_ms", 0) or 0)
        }
    );
}

impl TurnRenderer.render_stream(event_stream: any) -> dict {
    out: any = sys.stdout;

    show_term = _term_output_enabled();
    is_tty = show_term and bool(out?.isatty) and bool(out.isatty());

    n_read = 0;
    n_write = 0;
    n_run = 0;
    files: set[str] = set();
    usage: dict[str, object] = {};
    answer = "";
    streamed = False;
    thought_raw = "";
    prose_shown = 0;
    step_t0 = 0.0;
    think_on = False;
    last_llm_ms = 0.0;
    last_llm_tokens = 0;
    pend_result: any = None;
    def clear_think {
        nonlocal think_on;
        if think_on and is_tty {
            out.write("\r" + (" " * _THINK_WIDTH) + "\r");
            out.flush();
        }
        think_on = False;
    }
    def end_line {
        nonlocal streamed;
        if streamed {
            if show_term {
                out.write("\n");
                out.flush();
            }
            streamed = False;
        }
    }
    def flush_result {
        nonlocal pend_result;
        if pend_result is None {
            return;
        }
        (tool_name, result, ms) = (
            str(pend_result.get("tool", "")),
            pend_result["result"],
            pend_result["ms"]
        );
        pend_result = None;
        if agent.bus.active_feed and _tool_result_is_error(result, tool_name) {
            return;
        }
        agent.bus.emit("tool_result", {"text": truncate(str(result), 4000)});
        lines = agent.view._result_snippet(result, 3 if agent.cfg.verbose else 1);
        tail = f"   {agent.view._fmt_ms(ms)}"
            if (agent.cfg.verbose and ms is not None)
            else "";
        _term_print(f"      ↳ {lines[0]}{tail}", style="dim");
        for ln in lines[1:] {
            _term_print(f"        {ln}", style="dim");
        }
    }
    try {
        for event in event_stream {
            if agent.bus.cancel_requested {
                break;
            }
            kind = event.event_type;
            data = event.data;
            if kind == "thought" {
                if not agent.cfg.verbose {
                    continue;
                }
                tok = str(data.get("content", ""));
                if not tok {
                    continue;
                }
                if step_t0 == 0.0 {
                    step_t0 = time.time();
                }
                thought_raw += tok;
                (prose, hit) = agent.view._split_reasoning(thought_raw);
                new_raw = prose[prose_shown:];
                prose_shown = len(prose);
                cleaned = agent.view._strip_control(new_raw);
                if cleaned {
                    clear_think();
                    if show_term {
                        out.write(cleaned);
                        out.flush();
                    }
                    streamed = True;
                    agent.bus.emit_stream("reasoning", cleaned);
                }

                if hit and not streamed and is_tty {
                    out.write(f"\r  ● thinking… {time.time() - step_t0:.1f}s");
                    out.flush();
                    think_on = True;
                }
            } elif kind == "chunk" {
                clear_think();
                flush_result();
                tok = str(data.get("content", ""));
                answer += tok;
                if show_term {
                    out.write(tok);
                    out.flush();
                }
                streamed = True;
                agent.bus.emit_stream("answer", tok);
            } elif kind == "llm_timing" {
                last_llm_ms = float(data.get("duration_ms", 0) or 0);
                last_llm_tokens = int(data.get("completion_tokens", 0) or 0);
                agent.view._emit_call_usage(data, agent.bus.active);
            } elif kind == "tool_call" {
                clear_think();
                end_line();
                flush_result();
                tool = str(data.get("tool", "?"));
                args = data.get("args", {});
                if tool in _WRITE_TOOLS {
                    n_write += 1;
                    agent.turn_wrote = True;
                    if isinstance(args, dict) {
                        path = args.get("path");
                        if path {
                            files.add(str(path));
                        }
                    }
                } elif tool in _RUN_TOOLS {
                    n_run += 1;
                } else {
                    n_read += 1;
                }
                gen = agent.view._fmt_gen(last_llm_ms, last_llm_tokens)
                    if agent.cfg.verbose
                    else "";
                _term_print(
                    f"  ⏺ {agent.view.fmt_tool_call(tool, args)}{gen}", style="cyan"
                );
                tool_line = agent.view.fmt_tool_call(tool, args);
                agent.bus.emit("call", {"node": tool, "text": tool_line});
                last_llm_ms = 0.0;
                last_llm_tokens = 0;
                thought_raw = "";
                prose_shown = 0;
                step_t0 = 0.0;
            } elif kind == "tool_result" {
                clear_think();
                end_line();
                flush_result();
                pend_result = {
                    "tool": str(data.get("tool", "")),
                    "result": str(data.get("result", "")),
                    "ms": None
                };
            } elif kind == "tool_timing" {
                if pend_result is not None {
                    pend_result["ms"] = float(data.get("duration_ms", 0) or 0);
                }
                flush_result();
            } elif kind == "usage" {
                total = data.get("total", {});
                if isinstance(total, dict) {
                    usage = total;
                }
            } elif kind == "steps_done" {
                clear_think();
                end_line();
                flush_result();
                _term_print("");
            }
        }
        clear_think();
        end_line();
        flush_result();
    } except KeyboardInterrupt {
        _term_print("\n  [interrupted]", style="yellow");
    } except Exception as e {
        _term_print("");
        if not _term_output_enabled() {
            err_text = f"provider: {e}";
            if not _ui_is_duplicate_provider_error(err_text) {
                agent.bus.emit("error", {"text": err_text});
            }
            register_ui_provider_error(e);
        } else {
            console.error(f"agent error: {e}");
        }
        if os.environ.get("JAC_AI_DEBUG") and _term_output_enabled() {
            import traceback;
            traceback.print_exc();
        }
    }
    return {
        "n_read": n_read,
        "n_write": n_write,
        "n_run": n_run,
        "files": files,
        "usage": usage,
        "answer": answer.strip()
    };
}

impl Ledger.record(phase: str, summary: str) {
    self.changes.append({"phase": phase, "summary": truncate(summary, 400)});
}

impl Ledger.remember(text: str) {
    self.notes.append(text);
}

impl Ledger.render -> str {
    if not self.changes and not self.notes {
        return "(nothing done yet)";
    }
    lines: list = [];
    for c in self.changes {
        lines.append(f"- [{c['phase']}] {c['summary']}");
    }
    for n in self.notes {
        lines.append(f"- note: {n}");
    }
    return "\n".join(lines);
}

impl TurnStats.absorb(st: dict) {
    self.n_read += int(st["n_read"]);
    self.n_write += int(st["n_write"]);
    self.n_run += int(st["n_run"]);
    self.files |= set(st["files"]);
    for (k, v) in st["usage"].items() {
        try {
            self.usage[k] = self.usage.get(k, 0) + v;
        } except Exception {
            self.usage[k] = v;
        }
    }
}

impl TurnRenderer.route_stream_event(event: any) -> None {
    if agent.bus.cancel_requested {
        return;
    }

    if event.event_type == "llm_timing" {
        self._emit_call_usage(event.data, "route");
        return;
    }
    tok = str(event.data.get("content", "")) if event.data else "";
    if not tok {
        return;
    }

    if event.event_type == "thought" {
        cleaned = self._strip_control(tok);
        if cleaned {
            agent.bus.emit_stream("reasoning", cleaned);
        }
    }
}
