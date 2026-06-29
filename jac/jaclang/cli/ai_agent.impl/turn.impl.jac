import os;
import time;
import from jaclang.cli.console { console }

impl run_turn(message: str) {
    agent.turn_wrote = False;

    ledger = agent.ledger;
    if ledger is None {
        ledger = Ledger();
        agent.ledger = ledger;
    }
    started = time.time();
    session = AgentSession(
        objective=message, ledger=ledger, stats=TurnStats()
    ) spawn root;
    if agent.cfg.show_stats {
        st = session.stats;
        agent.view.print_stats(
            time.time() - started, st.n_read, st.n_write, st.n_run, st.files, st.usage
        );
    }

    if agent.bus.active_feed {
        st2 = session.stats;
        elapsed = time.time() - started;
        usage = st2.usage;
        prompt = int(usage.get("prompt_tokens", 0) or 0);
        completion = int(usage.get("completion_tokens", 0) or 0);
        cost = (
            agent.view._estimate_cost(prompt, completion)
                if (prompt > 0 or completion > 0)
                else 0.0
        );
        tok_per_s = completion / elapsed if (completion > 0 and elapsed > 0) else 0.0;

        n_err = 0;
        n_warn = 0;
        health_loaded = False;
        ci = agent.ws.code_intel();
        if ci is not None and ci.is_loaded() {
            try {
                (n_err, n_warn) = _count_diags(list(ci.diagnostics()));
                health_loaded = True;
            } except Exception {
                health_loaded = False;
            }
        }
        agent.bus.last_stats = {
            "elapsed": round(elapsed, 1),
            "tools": st2.n_read + st2.n_write + st2.n_run,
            "reads": st2.n_read,
            "writes": st2.n_write,
            "runs": st2.n_run,
            "files": len(st2.files),
            "tokens_in": prompt,
            "tokens_out": completion,
            "cost": cost,
            "tok_per_s": round(tok_per_s, 1),
            "errors": n_err,
            "warnings": n_warn,
            "health_loaded": health_loaded,
            "has_run": True
        };
    }

    _save_session(message, session.stats, session.phases);
}

impl verify_and_continue(max_rounds: int = 3) {
    if not agent.turn_wrote {
        return;
    }
    rnd = 0;
    prev_count = -1;
    while rnd < max_rounds {
        errs = agent.ws.project_errors();
        if not errs {
            break;
        }

        if prev_count >= 0 and len(errs) >= prev_count {
            break;
        }
        prev_count = len(errs);
        rnd += 1;
        shown = errs[:12];
        lines = [f"  {d.file}:{d.line}: {d.message}" for d in shown];
        more = (
            f"\n  ... and {len(errs) - len(shown)} more"
                if len(errs) > len(shown)
                else ""
        );
        _term_print("");
        _term_print(
            f"  build left {len(errs)} compile error(s); continuing to fix "
            f"(round {rnd}/{max_rounds})",
            style="yellow"
        );
        msg = (
            f"The project does not compile yet -- {len(errs)} error(s):\n" + "\n".join(
                lines
            ) + more + "\n\nFix these. Read each failing file, correct it, and re-run " + "jac_check until the whole project compiles cleanly. Do not finish " + "while errors remain."
        );
        run_turn(msg);
    }
}

impl run_agent(req: AgentRequest) -> int {
    global agent_model;

    r: any = req;

    agent.ws.cwd = os.path.normpath(str(r?.cwd or os.getcwd()));

    if bool(r?.ui) {
        return _run_ui_server(r);
    }
    agent.cfg.yolo_mode = not r.safe;
    agent.cfg.verbose = not bool(r?.quiet);

    agent.ws.ci = r.code_intel;
    if agent.ws.ci is not None {
        agent.ws.ci.on_event = agent.view._ci_event;
    }
    initial_prompt = str(r.prompt);

    if not _resolve_session(r) {
        return 1;
    }

    _led = _session_record.get("ledger", {});
    resuming = bool(
        _session_record.get("turns") or _led.get("changes") or _led.get("notes")
    );

    if r.model or r.n_ctx > 0 {
        agent_model = build_model(str(r.model), int(r.n_ctx));
    } elif resuming and _session_record.get("model") {
        rec_n_ctx = int(_session_record.get("cfg", {}).get("n_ctx", agent.cfg.n_ctx));
        agent_model = build_model(str(_session_record["model"]), rec_n_ctx);
    }
    agent.view.print_banner();
    if resuming {
        _restore_session_state(_session_record);
        n_turns = len(_session_record.get("turns", []));
        label = str(_session_record.get("name") or _session_record.get("id", ""));
        console.print(
            f"  resumed session {label} -- {n_turns} prior turn(s), "
            f"{len(
                _session_record["ledger"].get("changes", [])
            )} change(s) remembered.",
            style="bold green"
        );

        _print_scrollback(_session_record);
    } else {
        reset_session();
    }

    _save_session();

    if initial_prompt {
        try {
            run_turn(initial_prompt);

            verify_and_continue();
        } except Exception as e {
            console.error(f"Turn failed: {e}");
        } finally {
            agent.web._browse_shutdown();
            agent.proc._serve_shutdown();
        }
        return 0;
    }

    while True {
        try {
            line = input("\n> ").strip();
        } except EOFError {
            console.print("");
            break;
        } except KeyboardInterrupt {
            console.print("");
            continue;
        }
        if not line {
            continue;
        }
        head = line.split(None, 1);
        cmd = _lookup_host_cmd(head[0]);
        if cmd is not None {
            arg = head[1].strip() if len(head) > 1 else "";
            if cmd.handler(arg) {
                break;
            }
            continue;
        }
        try {
            run_turn(line);
        } except Exception as e {
            console.error(f"Turn failed: {e}");
        }
    }

    agent.web._browse_shutdown();
    agent.proc._serve_shutdown();
    console.print("Bye.");
    return 0;
}
