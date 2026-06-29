import os;
import json;
import time;
import secrets;
import from jaclang.cli.console { console }
import from jaclang.cli.guide_store { list_guides as gs_list }

def get_session_dir -> str {
    env = os.environ.get("JAC_AI_CACHE");
    if env {
        return env;
    }
    import from jaclang.jac0core.cache_paths { get_ai_session_cache_dir as _default }
    return str(_default());
}

impl SessionStore._dir -> str {
    base = self.root_dir or get_session_dir();
    d = os.path.join(base, "sessions");
    os.makedirs(d, exist_ok=True);
    return d;
}

impl SessionStore._path(id: str) -> str {
    return os.path.join(self._dir(), f"{id}.json");
}

def _now_iso -> str {
    t = time.time();
    base = time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t));
    micros = int((t - int(t)) * 1000000);
    return f"{base}.{micros:06d}Z";
}

impl SessionStore.create(cwd: str, name: str = "") -> dict {
    now = _now_iso();
    return {
        "id": secrets.token_hex(4),
        "name": name,
        "cwd": os.path.normpath(cwd),
        "created": now,
        "updated": now,
        "cfg": {},
        "ledger": {"changes": [], "notes": []},
        "turns": [],
        "totals": {}
    };
}

impl SessionStore.save(record: dict) -> None {
    if not record or "id" not in record {
        return;
    }
    record["updated"] = _now_iso();
    target = self._path(str(record["id"]));
    tmp = f"{target}.tmp";
    try {
        with open(tmp, "w", encoding="utf-8") as f {
            json.dump(record, f, indent=2);
        }
        os.replace(tmp, target);
    } except Exception as e {
        try {
            if os.path.exists(tmp) {
                os.remove(tmp);
            }
        } except Exception { }
        console.error(f"session save failed: {e}");
    }
}

impl SessionStore.load(id: str) -> dict | None {
    if not id {
        return None;
    }
    path = self._path(id);
    if not os.path.exists(path) {
        return None;
    }
    try {
        with open(path, "r", encoding="utf-8") as f {
            return json.load(f);
        }
    } except (json.JSONDecodeError, OSError) as e {
        console.error(f"session {id} unreadable, skipping: {e}");
        return None;
    }
}

impl SessionStore.delete(id: str) -> bool {
    if not id {
        return False;
    }
    path = self._path(id);
    if os.path.exists(path) {
        try {
            os.remove(path);
            return True;
        } except Exception as e {
            console.error(f"session delete failed: {e}");
        }
    }
    return False;
}

impl SessionStore.list_sessions(cwd: str = "") -> list[dict] {
    d = self._dir();
    results: list[dict] = [];
    for name in os.listdir(d) {
        if not name.endswith(".json") {
            continue;
        }
        path = os.path.join(d, name);
        try {
            with open(path, "r", encoding="utf-8") as f {
                rec = json.load(f);
            }
        } except (json.JSONDecodeError, OSError) as e {
            console.error(f"session file {name} unreadable, skipping: {e}");
            continue;
        }
        if cwd and os.path.normpath(str(rec.get("cwd", ""))) != os.path.normpath(cwd) {
            continue;
        }
        results.append(rec);
    }
    results.sort(key=lambda r : str(r.get("updated", "")), reverse=True);
    return results;
}

impl SessionStore.most_recent(cwd: str) -> dict | None {
    matches = self.list_sessions(cwd);
    return matches[0] if matches else None;
}

impl SessionStore.resolve_by_name(cwd: str, name: str) -> dict | None {
    if not name {
        return None;
    }
    for rec in self.list_sessions(cwd) {
        if str(rec.get("name", "")) == name {
            return rec;
        }
    }
    return None;
}

glob _PERSIST_CFG_FIELDS: list[str] = [
         "yolo_mode",
         "verbose",
         "show_stats",
         "inline_feedback",
         "temperature",
         "n_ctx",
         "threads"
     ];

glob _session_store: SessionStore | None = None,
     _session_record: dict = {};

def _ledger_to_dict(ledger: Ledger | None) -> dict {
    if ledger is None {
        return {"changes": [], "notes": []};
    }
    return {"changes": list(ledger.changes), "notes": list(ledger.notes)};
}

def _ledger_from_dict(d: dict) -> Ledger {
    return Ledger(changes=list(d.get("changes", [])), notes=list(d.get("notes", [])));
}

def _cfg_to_dict -> dict {
    out: dict = {};
    for f in _PERSIST_CFG_FIELDS {
        out[f] = getattr(agent.cfg, f);
    }
    return out;
}

def _restore_cfg(record: dict) -> None {
    d = record.get("cfg", {});
    if not isinstance(d, dict) {
        return;
    }
    for f in _PERSIST_CFG_FIELDS {
        if f in d {
            setattr(agent.cfg, f, d[f]);
        }
    }
}

def _resolve_session(r: any) -> bool {
    global _session_store,_session_record;
    cwd = agent.ws.cwd;
    store = SessionStore();
    resume_id = str(r?.resume or "");
    cont = bool(r?.continue_last);
    sname = str(r?.session_name or "");

    selectors = sum([bool(resume_id), cont, bool(sname)]);
    if selectors > 1 {
        console.error(
            "--resume, --continue, and --session are mutually exclusive; pick one."
        );
        return False;
    }
    record: dict | None = None;
    if resume_id {
        record = store.load(resume_id);
        if record is None {
            console.error(f"session {resume_id} not found; starting a fresh one.");
        }
    } elif cont {
        record = store.most_recent(cwd);
        if record is None {
            console.print(
                "  no prior session for this project; starting fresh.", style="muted"
            );
        }
    } elif sname {
        record = store.resolve_by_name(cwd, sname);
        if record is None {
            record = store.create(cwd, sname);
        }
    }
    if record is None {
        record = store.create(cwd);
    }
    _session_store = store;
    _session_record = record;
    return True;
}

def _save_session(objective: str = "", stats: any = None, phases: list = None) -> None {
    global _session_record;
    if _session_store is None or not _session_record {
        return;
    }
    _session_record["cwd"] = agent.ws.cwd;
    _session_record["cfg"] = _cfg_to_dict();
    _session_record["ledger"] = _ledger_to_dict(agent.ledger);

    try {
        _session_record["model"] = str(agent_model.model_name);
    } except Exception {
        pass;
    }
    if stats is not None {
        st: any = stats;
        usage = st.usage if isinstance(st.usage, dict) else dict(st.usage or {});
        turn = {
            "objective": objective,
            "phases": list(phases or []),
            "stats": {
                "n_read": int(st.n_read),
                "n_write": int(st.n_write),
                "n_run": int(st.n_run),
                "usage": usage
            }
        };
        _session_record["turns"].append(turn);

        totals = _session_record["totals"];
        totals["n_read"] = int(totals.get("n_read", 0)) + int(st.n_read);
        totals["n_write"] = int(totals.get("n_write", 0)) + int(st.n_write);
        totals["n_run"] = int(totals.get("n_run", 0)) + int(st.n_run);
        for (k, v) in usage.items() {
            try {
                totals[k] = int(totals.get(k, 0)) + int(v);
            } except Exception {
                totals[k] = v;
            }
        }
    }
    _session_store.save(_session_record);
}

def _print_scrollback(record: dict) {
    turns = record.get("turns", []);
    if not turns {
        return;
    }
    label = str(record.get("name") or record.get("id", ""));
    cwd = str(record.get("cwd", ""));
    console.print("");
    console.print(
        f"  session {label} -- {len(turns)} prior turn(s) in {cwd}:", style="bold"
    );
    for (i, t) in enumerate(turns) {
        obj_text = str(t.get("objective", ""));
        console.print(f"    {i + 1}. {truncate(obj_text, 120)}", style="cyan");
        phases = t.get("phases", []);
        if phases {
            last = phases[-1];
            ans = str(last.get("answer", "")).strip();
            lines = [
                ln
                for ln in ans.splitlines()
                if ln.strip()
            ];
            for ln in lines[:4] {
                console.print(f"       {truncate(ln, 160)}", style="muted");
            }
            if len(lines) > 4 {
                console.print("       ...", style="muted");
            }
        }
    }
    console.print("");
}

def _restore_session_state(record: dict) {
    agent.ledger = _ledger_from_dict(
        record.get("ledger", {"changes": [], "notes": []})
    );
    _restore_cfg(record);
    rec_cwd = str(record.get("cwd", ""));
    if rec_cwd and rec_cwd != agent.ws.cwd {
        agent.ws.set_cwd(rec_cwd);
    }
}

def cmd_sessions {
    if _session_store is None {
        console.print("  no session store active.", style="muted");
        return;
    }
    cwd = agent.ws.cwd;
    sessions = _session_store.list_sessions(cwd);
    if not sessions {
        console.print(f"  no sessions for {cwd}.", style="muted");
        return;
    }
    current = str(_session_record.get("id", "")) if _session_record else "";
    console.print(f"  sessions in {cwd}:", style="bold");
    for s in sessions {
        sid = str(s.get("id", ""));
        name = str(s.get("name", "")) or "-";
        nturns = len(s.get("turns", []));

        updated = str(s.get("updated", "")).split(".")[0].replace("T", " ") or "?";
        totals = s.get("totals", {});
        tok = int(totals.get("prompt_tokens", 0)) + int(
            totals.get("completion_tokens", 0)
        );
        mark = "*" if sid == current else " ";
        console.print(
            f"  {mark} {sid}  {name:<16} {nturns:>2} turns  {updated}  "
            f"{agent.view._short_num(tok)} tok",
            style="muted"
        );
    }
}

def cmd_resume(target: str) {
    global _session_record;
    if _session_store is None {
        console.print("  no session store active.", style="muted");
        return;
    }
    if not target {
        console.error("usage: /resume <id|name>");
        return;
    }
    cwd = agent.ws.cwd;
    record = _session_store.load(target);
    if record is None {
        record = _session_store.resolve_by_name(cwd, target);
    }
    if record is None {
        console.error(f"no session '{target}' for this project.");
        return;
    }
    _session_record = record;
    _restore_session_state(record);
    label = str(record.get("name") or record.get("id", ""));
    n_turns = len(record.get("turns", []));
    console.print(
        f"  switched to session {label} -- {n_turns} turn(s).", style="bold green"
    );
    _print_scrollback(record);
}

def cmd_name(name: str) {
    if not _session_record {
        return;
    }
    if not name {
        cur = str(_session_record.get("name", "")) or "(unnamed)";
        console.print(f"  current name: {cur}", style="muted");
        return;
    }
    cwd = agent.ws.cwd;
    if _session_store is not None {
        existing = _session_store.resolve_by_name(cwd, name);
        if existing is not None
        and str(existing.get("id", "")) != str(_session_record.get("id", "")) {
            console.error(f"name '{name}' is already used by another session here.");
            return;
        }
    }
    _session_record["name"] = name;
    if _session_store is not None {
        _session_store.save(_session_record);
    }
    console.success(f"session named '{name}'.");
}

def cmd_forget {
    global _session_record;
    if _session_store is None or not _session_record {
        return;
    }
    label = str(_session_record.get("name") or _session_record.get("id", ""));
    if not confirm(f"delete session {label}?") {
        console.print("  cancelled.", style="muted");
        return;
    }
    _session_store.delete(str(_session_record.get("id", "")));

    _session_record = _session_store.create(agent.ws.cwd);
    _restore_session_state(_session_record);
    _session_store.save(_session_record);
    console.success("session forgotten; started a fresh one.");
}

def cmd_cost {
    if not _session_record {
        return;
    }
    totals = _session_record.get("totals", {});
    prompt = int(totals.get("prompt_tokens", 0));
    completion = int(totals.get("completion_tokens", 0));
    n_read = int(totals.get("n_read", 0));
    n_write = int(totals.get("n_write", 0));
    n_run = int(totals.get("n_run", 0));
    label = str(_session_record.get("name") or _session_record.get("id", ""));
    n_turns = len(_session_record.get("turns", []));
    console.print(f"  session {label} -- {n_turns} turn(s):", style="bold");
    tok_str = agent.view._format_tokens(
        {"prompt_tokens": prompt, "completion_tokens": completion}
    );
    console.print(f"    tokens: {tok_str}", style="muted");
    cost = (
        agent.view._estimate_cost(prompt, completion)
            if (prompt > 0 or completion > 0)
            else 0.0
    );
    console.print(f"    est. cost: ${cost:.4f}", style="muted");
    console.print(
        f"    tools: {n_read} read, {n_write} write, {n_run} run", style="muted"
    );
}

def _hc_help(arg: str) -> bool {
    agent.view.print_help();
    return False;
}

def _hc_clear(arg: str) -> bool {
    reset_session();
    if _session_record and _session_store is not None {
        _session_record["turns"] = [];
        _session_record["ledger"] = {"changes": [], "notes": []};
        _session_record["totals"] = {};
        _session_store.save(_session_record);
    }
    console.success("Conversation cleared.");
    return False;
}

def _hc_guides(arg: str) -> bool {
    for g in gs_list() {
        console.print(f"  {g.name}", style="bold");
        console.print(f"      {g.description}", style="muted");
    }
    return False;
}

def _hc_stats(arg: str) -> bool {
    agent.cfg.show_stats = not agent.cfg.show_stats;
    console.success("Turn stats on." if agent.cfg.show_stats else "Turn stats off.");
    return False;
}

def _hc_verbose(arg: str) -> bool {
    agent.cfg.verbose = not agent.cfg.verbose;
    console.success(
        "Verbose: streaming reasoning, timings, and step detail."
            if agent.cfg.verbose
            else "Quiet: tool calls and the answer only."
    );
    return False;
}

def _hc_feedback(arg: str) -> bool {
    agent.cfg.inline_feedback = not agent.cfg.inline_feedback;
    console.success(
        "Inline compiler feedback on: writes report errors they introduce."
            if agent.cfg.inline_feedback
            else "Inline compiler feedback off: use jac_check to compile."
    );
    return False;
}

def _hc_sessions(arg: str) -> bool {
    cmd_sessions();
    return False;
}

def _hc_resume(arg: str) -> bool {
    cmd_resume(arg);
    return False;
}

def _hc_name(arg: str) -> bool {
    cmd_name(arg);
    return False;
}

def _hc_cost(arg: str) -> bool {
    cmd_cost();
    return False;
}

def _hc_forget(arg: str) -> bool {
    cmd_forget();
    return False;
}

def _hc_exit(arg: str) -> bool {
    return True;
}

def _host_cmds -> list[HostCmd] {
    return [
        HostCmd(["/help"], "/help", "show this help", False, _hc_help),
        HostCmd(
            ["/clear"],
            "/clear",
            "reset the conversation (keeps the session)",
            False,
            _hc_clear
        ),
        HostCmd(
            ["/guides"],
            "/guides",
            "list the bundled Jac reference guides",
            False,
            _hc_guides
        ),
        HostCmd(
            ["/stats"], "/stats", "toggle the per-turn stat line", False, _hc_stats
        ),
        HostCmd(
            ["/verbose"],
            "/verbose",
            "toggle live reasoning, timings, and step detail",
            False,
            _hc_verbose
        ),
        HostCmd(
            ["/feedback"],
            "/feedback",
            "toggle inline compiler feedback after each write",
            False,
            _hc_feedback
        ),
        HostCmd(
            ["/sessions"],
            "/sessions",
            "list sessions for this project",
            False,
            _hc_sessions
        ),
        HostCmd(
            ["/resume"],
            "/resume <id|name>",
            "switch to another session",
            True,
            _hc_resume
        ),
        HostCmd(
            ["/name"], "/name <name>", "name or rename this session", True, _hc_name
        ),
        HostCmd(
            ["/cost"],
            "/cost",
            "show cumulative token usage for this session",
            False,
            _hc_cost
        ),
        HostCmd(
            ["/forget"],
            "/forget",
            "delete this session and start fresh",
            False,
            _hc_forget
        ),
        HostCmd(["/exit", "/quit"], "/exit", "quit the session", False, _hc_exit),

    ];
}

def _lookup_host_cmd(name: str) -> HostCmd | None {
    for c in _host_cmds() {
        if name in c.names {
            return c;
        }
    }
    return None;
}
