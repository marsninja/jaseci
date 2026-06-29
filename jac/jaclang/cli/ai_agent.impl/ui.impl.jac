import os;
import re;
import sys;
import time;
import signal;
import threading;
import subprocess;
import webbrowser;
import from pathlib { Path }
import from jaclang.cli.console { console }
import from jaclang.compiler.code_intel { CodeIntelligence }

glob _ui_recent_errors: dict = {},
     _ui_output_capture_installed = False,
     _ui_emit_tls = threading.local(),
     _ui_capture_bus: any = None,
     _UI_PROVIDER_DEDUP_S = 2.0;

def _ui_provider_fingerprint(text: str) -> str {
    t = " ".join(text.strip().lower().split());
    if t.startswith("provider:") {
        t = t[len("provider:"):].strip();
    }
    if t.startswith("llm ") and ":" in t {
        (head, _, tail) = t.partition(":");
        if "error" in head or "failed" in head {
            t = tail.strip();
        }
    }
    return t[:240];
}

def _ui_purge_stale_provider_errors(now: float) {
    stale: list[str] = [];
    for (key, ts) in _ui_recent_errors.items() {
        if now - ts > _UI_PROVIDER_DEDUP_S {
            stale.append(key);
        }
    }
    for key in stale {
        _ui_recent_errors.pop(key, None);
    }
}

def _ui_remember_provider_error(text: str) {
    now = time.monotonic();
    _ui_purge_stale_provider_errors(now);
    _ui_recent_errors[_ui_provider_fingerprint(text)] = now;
}

def _ui_is_duplicate_provider_error(text: str) -> bool {
    now = time.monotonic();
    _ui_purge_stale_provider_errors(now);
    fp = _ui_provider_fingerprint(text);
    for (key, ts) in _ui_recent_errors.items() {
        if now - ts > _UI_PROVIDER_DEDUP_S {
            continue;
        }
        if key in fp or fp in key {
            return True;
        }
    }
    return False;
}

def _ui_bus_emit_guarded(kind: str, text: str) {
    if getattr(_ui_emit_tls, "active", False) {
        return;
    }
    bus = _ui_capture_bus;
    if bus is None {
        return;
    }
    if kind == "error" and _ui_is_duplicate_provider_error(text) {
        return;
    }
    _ui_emit_tls.active = True;
    try {
        bus.emit(kind, {"text": text});
        if kind == "error" {
            _ui_remember_provider_error(text);
        }
    } finally {
        _ui_emit_tls.active = False;
    }
}

def _ui_loguru_sink(message: any) {
    import traceback;

    record = message.record;
    text = str(record["message"]);
    exc = record.get("exception");
    if exc is not None {
        text += "\n" + "".join(
            traceback.format_exception(exc.type, exc.value, exc.traceback)
        );
    }
    level_no = int(record["level"].no);
    kind = "error" if level_no >= 40 else "system";
    _ui_bus_emit_guarded(kind, f"provider: {text}");
}

impl register_ui_provider_error(exc: any) -> None {
    _ui_remember_provider_error(str(exc));
}

impl _install_ui_provider_capture(target_bus: any = None) -> None {
    global _ui_output_capture_installed,_ui_capture_bus;
    _ui_capture_bus = target_bus if target_bus is not None else agent.bus;
    if _ui_output_capture_installed {
        return;
    }
    import from loguru { logger }
    logger.remove();
    logger.add(_ui_loguru_sink, level="WARNING");
    try {
        import litellm;
        litellm.suppress_debug_info = True;
    } except Exception { }
    _ui_output_capture_installed = True;
}

def _emit_scrollback_to_bus(record: dict) {
    turns = record.get("turns", []);
    if not turns {
        return;
    }
    label = str(record.get("name") or record.get("id", ""));
    n = len(turns);
    agent.bus.emit(
        "system",
        {"text": f"Resumed session {label} — {n} prior turn(s).", "historical": True}
    );
    for t in turns {
        obj_text = str(t.get("objective", "")).strip();
        if obj_text {
            agent.bus.emit("user", {"text": obj_text, "historical": True});
        }
        phases = t.get("phases", []);
        if phases {
            last = phases[-1];
            ans = str(last.get("answer", "")).strip();
            if ans {
                agent.bus.emit(
                    "answer", {"text": truncate(ans, 1200), "historical": True}
                );
            }
        }
    }
}

impl ui_configure -> None {
    global agent_model,_session_store,_session_record;

    proj = os.environ.get("JAC_AI_UI_PROJECT") or os.getcwd();
    agent.ws.cwd = os.path.normpath(proj);

    agent.cfg.yolo_mode = True;
    agent.cfg.verbose = True;
    agent.cfg.show_stats = True;
    agent.bus.active_feed = True;
    if not _term_output_enabled() {
        _install_ui_provider_capture();
    }
    model_flag = os.environ.get("JAC_AI_UI_MODEL") or "";
    n_ctx = 0;
    try {
        n_ctx = int(os.environ.get("JAC_AI_UI_NCTX") or "0");
    } except Exception { }

    agent.ws.ci = CodeIntelligence(proj_dir=agent.ws.cwd, lazy=True);

    cwd = agent.ws.cwd;
    resume_id = os.environ.get("JAC_AI_UI_RESUME", "").strip();
    cont = os.environ.get("JAC_AI_UI_CONTINUE", "") == "1";
    session_name = os.environ.get("JAC_AI_UI_SESSION", "").strip();
    selectors = sum([bool(resume_id), cont, bool(session_name)]);
    store = SessionStore();
    record: dict | None = None;
    if selectors > 1 {
        agent.bus.emit(
            "error",
            {
                "text": "--resume, --continue, and --session are mutually exclusive; starting a fresh session."
            }
        );
    } else {
        if resume_id {
            record = store.load(resume_id);
        } elif cont {
            record = store.most_recent(cwd);
        } elif session_name {
            record = store.resolve_by_name(cwd, session_name);
            if record is None {
                record = store.create(cwd, session_name);
            }
        }
    }
    if record is None {
        record = store.create(cwd);
    }
    _session_store = store;
    _session_record = record;
    _led = _session_record.get("ledger", {});
    resuming = bool(
        _session_record.get("turns") or _led.get("changes") or _led.get("notes")
    );
    if resuming {
        _restore_session_state(_session_record);
        _emit_scrollback_to_bus(_session_record);
    } else {
        reset_session();
    }

    _save_session();

    agent.cfg.n_ctx = n_ctx;
    try {
        agent_model = build_model(model_flag, n_ctx);
    } except Exception as e {
        agent.bus.emit("error", {"text": f"Model failed to load: {e}"});
    }

    _refresh_key_status();
    if agent.bus.needs_key {
        agent.bus.emit(
            "system",
            {
                "text": f"{agent_model.model_name} needs an API key ({agent.bus.key_env}). Open Settings (⚙) to add one."
            }
        );
    }
}

def _ui_turn_worker(prompt: str) {
    try {
        run_turn(prompt);

        if not agent.bus.cancel_requested {
            verify_and_continue();
        }
    } except Exception as e {
        err_text = f"provider: {e}";
        if not _ui_is_duplicate_provider_error(err_text) {
            agent.bus.emit("error", {"text": err_text});
        }
        register_ui_provider_error(e);

        msg = str(e).lower();
        if (
            "authenticationerror" in msg
            or "api key" in msg
            or "api_key" in msg
            or "401" in msg
            or "unauthorized" in msg
        ) {
            (_, env) = _model_needs_key(str(agent_model.model_name));
            agent.bus.needs_key = True;
            if env {
                agent.bus.key_env = env;
            }
            agent.bus.publish_full();
        }
    }
    if agent.bus.cancel_requested {
        agent.bus.emit("system", {"text": "Stopped."});
        agent.bus.cancel_requested = False;
        agent.bus.set_status("idle");
    } elif agent.bus.status != "done" {
        agent.bus.set_status("idle");
    }
}

impl ui_send(prompt: str) -> bool {
    text = prompt.strip();
    if not text {
        return False;
    }

    agent.bus._lock.acquire();
    try {
        if agent.bus.status == "running" or agent.bus.status == "stopping" {
            return False;
        }
        agent.bus.begin_turn();
        agent.bus.emit("user", {"text": text});
        agent.bus.set_status("running");
        threading.Thread(target=_ui_turn_worker, args=(text, ), daemon=True).start();
    } finally {
        agent.bus._lock.release();
    }
    return True;
}

impl ui_poll -> dict {
    return agent.bus.snapshot();
}

impl ui_call_detail(call_id: int) -> dict {
    log = list(agent.bus.call_log);
    entry: any = None;
    for c in log {
        if int(c["id"]) == call_id {
            entry = c;
        }
    }
    if entry is None {
        return {"found": False};
    }
    convo: int = int(entry["convo"]);
    msgs: list = agent.bus.convos.get(convo, []);

    same = [
        c
        for c in log
        if int(c["convo"]) == convo
    ];
    pos = 0;
    i = 0;
    for c in same {
        if int(c["id"]) == call_id {
            pos = i;
        }
        i += 1;
    }

    asst: list = [];
    j = 0;
    for m in msgs {
        if str(m.get("role", "")) == "assistant" {
            asst.append(j);
        }
        j += 1;
    }
    n = len(asst);

    a_k = int(asst[pos]) if pos < n else len(msgs);
    a_prev = int(asst[pos - 1]) if (pos > 0 and pos - 1 < n) else 0;
    a_next = int(asst[pos + 1]) if (pos + 1 < n) else len(msgs);
    prev_id = int(same[pos - 1]["id"]) if pos > 0 else -1;
    next_id = int(same[pos + 1]["id"]) if pos + 1 < len(same) else -1;
    out_slice = [
        m
        for m in msgs[a_k:a_next]
        if str(m.get("role", "")) in ("assistant", "tool")
    ];

    tools: list = agent.bus.convo_tools.get(convo, []);
    tool_chars = 0;
    for t in tools {
        td: any = t;
        tool_chars += len(str(td.get("schema", "")));
    }
    return {
        "found": True,
        "id": call_id,
        "node": str(entry["node"]),
        "input": msgs[:a_k],
        "new_input": msgs[a_prev:a_k],
        "output": out_slice,
        "shared": a_prev,
        "total": a_k,
        "tokens_in": int(entry.get("tokens_in", 0) or 0),
        "tokens_out": int(entry.get("tokens_out", 0) or 0),
        "tools": tools,
        "tool_chars": tool_chars,
        "prev_id": prev_id,
        "next_id": next_id
    };
}

impl ui_phase_context(phase: str) -> dict {
    log = list(agent.bus.call_log);

    convo = -1;
    for c in log {
        if str(c.get("node", "")) == phase {
            convo = int(c["convo"]);
        }
    }
    if convo < 0 {
        return {"phase": phase, "found": False, "messages": []};
    }
    return {"phase": phase, "found": True, "messages": agent.bus.convos.get(convo, [])};
}

impl ui_stream -> any {
    import from queue { Empty }
    q = agent.bus.subscribe();
    try {
        snap = agent.bus.snapshot();
        snap["full"] = True;
        yield snap;
        while True {
            try {
                yield q.get(timeout=3.0);
            } except Empty {
                yield {"heartbeat": True};
            }
        }
    } finally {
        agent.bus.unsubscribe(q);
    }
}

impl ui_graph -> dict {
    nodes = [];
    edges = [];
    seen = set();

    frontier: list = [build_pipeline()];
    while frontier {
        nd = frontier.pop(0);
        nid = type(nd).__name__;
        if nid in seen {
            continue;
        }
        seen.add(nid);

        tool_names = (
            [getattr(t, "__name__", "") for t in nd.tools()] if nd?.tools else []
        );
        nodes.append(
            {
                "id": nid,
                "label": nid,
                "desc": nd.desc,
                "sem": str(type(nd)?._jac_semstr or ""),
                "tools": tool_names
            }
        );

        for succ in [nd->:Flow:->] {
            edges.append({"source": nid, "target": type(succ).__name__});
            frontier.append(succ);
        }
    }
    return {"nodes": nodes, "edges": edges, "state": agent.bus.snapshot()};
}

impl ui_reset -> None {
    if agent.bus.status == "running" or agent.bus.status == "stopping" {
        agent.bus.cancel_requested = True;
        agent.bus.set_status("stopping");
        return;
    }
    reset_session();
    agent.bus.events = [];

    agent.bus.call_log = [];
    agent.bus.convos = {};
    agent.bus.convo_tools = {};
    agent.bus.begin_turn();
    agent.bus.set_status("idle");

    agent.bus.publish_full();
}

impl ui_stop -> None {
    if agent.bus.status == "running" {
        agent.bus.cancel_requested = True;
        agent.bus.set_status("stopping");
        agent.bus.emit("system", {"text": "Stopping…"});
    }
}

impl ui_settings -> dict {
    name = "";
    try {
        name = str(agent_model.model_name);
    } except Exception {
        name = "";
    }
    t = agent.cfg.temperature;
    return {
        "model": name,
        "api_key_set": bool(agent.cfg.api_key),
        "base_url": agent.cfg.base_url,
        "temperature": (float(t) if t is not None else -1.0),
        "n_ctx": agent.cfg.n_ctx,
        "model_source": agent.cfg.model_source,
        "needs_key": agent.bus.needs_key,
        "key_env": agent.bus.key_env,
        "presets": list(_MODEL_PRESETS)
    };
}

impl ui_apply_settings(
    model: str, api_key: str, base_url: str, temperature: str, n_ctx: str
) -> dict {
    global agent_model;

    if agent.bus.status == "running" or agent.bus.status == "stopping" {
        return {
            "ok": False,
            "error": "Cannot apply settings while a turn is running -- stop it first.",
            "needs_key": agent.bus.needs_key,
            "key_env": agent.bus.key_env
        };
    }
    if api_key.strip() {
        agent.cfg.api_key = api_key.strip();
    }
    agent.cfg.base_url = base_url.strip();
    nctx = 0;
    try {
        if n_ctx.strip() {
            nctx = max(0, int(n_ctx.strip()));
        }
    } except Exception {
        nctx = 0;
    }
    agent.cfg.n_ctx = nctx;

    temp_override: float | None = None;
    try {
        if temperature.strip() and float(temperature) >= 0.0 {
            temp_override = float(temperature);
        }
    } except Exception {
        temp_override = None;
    }
    try {
        agent_model = build_model(model.strip(), nctx);
        if temp_override is not None {
            agent.cfg.temperature = temp_override;
        }
        _refresh_key_status();
        agent.bus.emit(
            "system", {"text": f"Settings applied; using {agent_model.model_name}."}
        );
        agent.bus.publish_full();
        return {
            "ok": True,
            "error": "",
            "model": str(agent_model.model_name),
            "needs_key": agent.bus.needs_key,
            "key_env": agent.bus.key_env
        };
    } except Exception as e {
        _refresh_key_status();
        agent.bus.emit("error", {"text": f"Settings error: {e}"});
        agent.bus.publish_full();
        return {
            "ok": False,
            "error": str(e),
            "model": "",
            "needs_key": agent.bus.needs_key,
            "key_env": agent.bus.key_env
        };
    }
}

impl _run_ui_server(r: any) -> int {
    import jaclang;
    pkg_file = jaclang.__file__;
    if pkg_file is None {
        console.error("jaclang package location is unavailable");
        return 1;
    }
    ui_dir = str(Path(pkg_file).parent / "cli" / "ai_ui");
    entry = os.path.join(ui_dir, "main.jac");
    if not os.path.exists(entry) {
        console.error(f"bundled UI app not found at {entry}");
        return 1;
    }
    env = dict(os.environ);
    env["JAC_AI_UI_PROJECT"] = agent.ws.cwd;
    env["JAC_AI_UI_MODEL"] = str(r?.model or "");
    env["JAC_AI_UI_NCTX"] = str(int(r?.n_ctx or 0));
    log_path = "/tmp/jac_ai_ui.log";
    console.print("");
    console.print("  Jac AI -- web UI", style="bold");
    console.print(f"  project: {agent.ws.cwd}", style="muted");
    console.print("  building the client (first run installs deps)…", style="muted");
    proc: any = None;
    try {
        log_f = open(log_path, "w", encoding="utf-8");
        proc = subprocess.Popen(
            [sys.executable, "-m", "jaclang", "start", "main.jac"],
            cwd=ui_dir,
            stdout=log_f,
            stderr=subprocess.STDOUT,
            text=True,
            env=env,
            start_new_session=True
        );

        log_f.close();
    } except Exception as e {
        console.error(f"failed to launch the UI server: {e}");
        return 1;
    }
    url_re = re.compile(
        "https?://(?:localhost|127\\.0\\.0\\.1|0\\.0\\.0\\.0)(?::\\d+)?\\S*"
    );
    timeout = 180.0;
    try {
        raw = os.environ.get("JAC_AI_UI_TIMEOUT");
        if raw {
            timeout = float(raw);
        }
    } except Exception { }
    deadline = time.time() + timeout;
    url = "";
    while time.time() < deadline {
        if proc.poll() is not None {
            break;
        }
        try {
            log_text = Path(log_path).read_text();
        } except Exception {
            log_text = "";
        }
        m = url_re.search(log_text);
        if m {
            url = m.group(0).rstrip("/");
            break;
        }
        time.sleep(1.0);
    }
    if not url {
        tail = "";
        try {
            tail = "\n".join(Path(log_path).read_text().splitlines()[-25:]);
        } except Exception {
            tail = "(no log output)";
        }
        try {
            if hasattr(os, "killpg") {
                os.killpg(os.getpgid(int(proc.pid)), int(signal.SIGTERM));
            } else {
                proc.terminate();
            }
        } except Exception { }
        try {
            proc.wait(timeout=5);
        } except Exception {
            try {
                proc.kill();
            } except Exception { }
        }
        console.error(f"the UI server did not come up within {int(timeout)}s.\n{tail}");
        return 1;
    }
    console.success(f"  UI ready at {url}");
    console.print(f"  logs: {log_path}", style="muted");
    console.print("  press Ctrl-C to stop", style="muted");
    console.print("");
    try {
        webbrowser.open(url);
    } except Exception { }
    try {
        proc.wait();
    } except KeyboardInterrupt {
        console.print("\n  stopping the UI server…", style="muted");
    }
    try {
        if hasattr(os, "killpg") {
            os.killpg(os.getpgid(int(proc.pid)), int(signal.SIGTERM));
        } else {
            proc.terminate();
        }
    } except Exception { }
    try {
        proc.wait(timeout=5);
    } except Exception {
        try {
            proc.kill();
        } except Exception { }
    }
    console.print("Bye.");
    return 0;
}
