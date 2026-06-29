import threading;
import from byllm.lib { IterationAction }

impl _progress_guard(ctx: any) -> str {
    import json;

    if agent.bus.cancel_requested {
        return IterationAction.ABORT_WITH_SUMMARY;
    }

    agent.bus.set_pending(ctx.messages);
    counts: dict[str, int] = {};

    sigs: list[str] = [];
    for m in ctx.messages {
        tcs = m.get("tool_calls") if isinstance(m, dict) else m?.tool_calls;
        if not tcs {
            continue;
        }
        for tc in tcs {
            fn = tc?.function;
            if fn is None and isinstance(tc, dict) {
                fn = tc.get("function");
            }
            name = fn?.name;
            if name is None and isinstance(fn, dict) {
                name = fn.get("name");
            }
            raw = fn?.arguments;
            if raw is None and isinstance(fn, dict) {
                raw = fn.get("arguments");
            }
            args_str = "";
            try {
                parsed = json.loads(raw) if isinstance(raw, str) else (raw or {});
                args_str = json.dumps(parsed, sort_keys=True)
                    if isinstance(parsed, dict)
                    else str(raw);
                path = str(parsed.get("path", "")) if isinstance(parsed, dict) else "";
            } except Exception {
                args_str = str(raw);
                path = "";
            }
            sigs.append(f"{name}|{args_str}");
            if name in _WRITE_TOOLS and path {
                counts[path] = counts.get(path, 0) + 1;
            }
        }
    }

    if len(sigs) >= 3 and sigs[-1] == sigs[-2] and sigs[-2] == sigs[-3] {
        return IterationAction.ABORT_WITH_SUMMARY;
    }
    worst = max(counts.values()) if counts else 0;
    if worst > _REWRITE_LIMIT {
        return IterationAction.ABORT_WITH_SUMMARY;
    }
    return IterationAction.CONTINUE;
}

impl AgentRuntime.postinit -> None {
    self.files.ws = self.ws;
    self.files.cfg = self.cfg;
    self.proc.ws = self.ws;
    self.semantic.ws = self.ws;

    self.bus._lock = threading.Lock();
}

sem AgentRuntime.note = "Record a short note that stays visible to every later phase (Plan, Build, QA) and in later turns. Use it to flag a decision, an assumption, or something to verify.";
sem AgentRuntime.note.text = "The note to remember.";

impl AgentRuntime.note(text: str) -> str {
    if agent.active_session is not None {
        agent.active_session.ledger.remember(text);
        agent.bus.publish_ledger();
        return f"noted: {text}";
    }
    return "(no active session to note onto)";
}

impl PhaseState.tools -> list {
    return [t.fn for t in [self->:Exposes:->]];
}

sem Plan = "the PLANNING state: understand the request and the existing project before writing anything. Use project_map for an unfamiliar small/medium project, but on a large monorepo narrow scope first with list_dir / grep and only map the relevant package. Use find_symbol / find_uses / context_slice to navigate by meaning, read_file to read what you will change, and the guides for unfamiliar Jac (read at least the one for the kind of code you will write -- e.g. jac-cl-components for a UI). Do not write or edit files here. Finish by stating a short, concrete plan: whether to scaffold (and which template -- web-static for a browser-only UI, web-app for server/data, default for a script), the files to create or change, and what each is for.";

sem Build = "the BUILDING state: carry out the plan. For a new app, scaffold it ONCE with `jac create --kind <kind> <name>` via run_command, then `cd <name>` so every later tool works inside the project (the cd persists). Pick the SIMPLEST kind that fits: `web-static` for a browser-only UI with no server or saved data (a calculator, a unit converter, a static page); `web-app` only when you need server endpoints or persistent/multi-user data; `cli` for a non-web script. To create a NEW file, call write_file with its FULL contents -- never create files with shell redirection (`echo >`, `cat <<EOF`, `touch`) and never try to edit a file that does not exist yet. Use edit_file only to change a file that already exists, and read it first. Every write reports the compiler errors it introduced; fix them before moving on. Keep files focused; split large archetypes into impl files.";

sem QA = "the QA state: verify the work end to end and fix what you find. Run `jac check .` (zero errors required). For a runnable app, start_app and confirm it boots cleanly. For a web or full-stack app, drive the built-in browser: call serve(entry) to start the dev server -- it waits until the server is actually ready and returns its URL (the first start is slow, as it installs client deps and builds the client). Then browse_open that URL, browse_snapshot to read the page, exercise the main flows with browse_click / browse_fill / browse_type / browse_press (snapshotting after each), check for errors with browse_eval, then browse_close and stop_server. If serve reports the server failed to start, read the log tail it returns and go back to Build to fix the cause -- do not conclude the app works until you have actually run and exercised it.";

impl PhaseState.directive -> str {
    return f"Carry out the {type(self).__name__} state now.";
}

impl PhaseState.step(visitor: AgentSession) -> dict {
    agent.active_session = visitor;
    label = type(self).__name__;
    _term_print(f"\n  ● {label}", style="bold blue");

    agent.bus.enter(label);

    sysmsg = {
        "role": "system",
        "content": Prompt.for_phase(type(self), visitor.objective, visitor.ledger)
    };
    if not self.ctx {
        self.ctx.append(sysmsg);
    } else {
        self.ctx[0] = sysmsg;
    }

    agent.phase_tools = self.tools();
    agent.phase_ctx = self.ctx;

    agent.bus.open_convo(self.ctx);

    agent.bus.set_convo_tools(agent.phase_tools);
    result = agent.view.render_stream(run_phase(self.directive()));
    agent.bus.close_convo(self.ctx);
    visitor.stats.absorb(result);
    visitor.ledger.record(label, str(result.get("answer", "") or "(no summary)"));

    visitor.phases.append(
        {
            "name": label,
            "answer": truncate(str(result.get("answer", "") or "(no summary)"), 4000)
        }
    );

    agent.bus.publish_ledger();
    return result;
}

impl PhaseState.halt(visitor: AgentSession) -> bool {
    if agent.bus.cancel_requested {
        return True;
    }

    visitor.steps += 1;
    if visitor.steps > visitor.max_steps {
        _term_print("\n  ● step cap reached -- stopping", style="yellow");
        return True;
    }
    return False;
}

impl Plan.directive -> str {
    return (
        "Investigate the request and the existing project, then state a "
        "short, concrete plan. Do not write or edit files in this state."
    );
}

impl Build.directive -> str {
    return (
        "Build the requested feature NOW by writing real code: call "
        "write_file to create each new file with its full contents, and "
        "edit_file to change existing ones. Exploring or describing the "
        "plan is NOT building -- keep working until every file the task "
        "needs exists and the project compiles. After each write, read the "
        "compiler feedback it returns and fix the errors before moving on. "
        "Do not end this state with only reads."
    );
}

impl QA.directive -> str {
    return (
        "Verify the finished work end to end NOW. Run jac_check and require "
        "zero errors. For a web or full-stack app, serve it and drive the "
        "browser (browse_open, browse_snapshot, then click/type the real "
        "controls) to confirm the REQUESTED feature actually works on the "
        "page -- not just that the scaffold loads. If anything is missing, "
        "wrong, or broken, go back to Build to fix it; choose Done only "
        "after you have actually run and exercised the result."
    );
}

sem run_phase.directive = "A short instruction kicking off the current phase.";

impl Plan.run with AgentSession entry {
    if agent.bus.cancel_requested {
        return;
    }
    self.step(visitor);
    if self.halt(visitor) {
        return;
    }

    needs_code = True;
    try {
        needs_code = request_needs_code_changes(
            visitor.objective, visitor.ledger.render()
        );
    } except Exception as e {
        _term_print(
            f"  ↳ classifier failed ({e}); defaulting to Build", style="yellow"
        );
    }
    if needs_code {
        visit [->:Flow:->][?:Build];
    } else {
        _term_print(
            "  ↳ read-only request -- answered in Plan, skipping Build/QA",
            style="green"
        );
        visit [->:Flow:->][?:Done];
    }
}

impl Build.run with AgentSession entry {
    if agent.bus.cancel_requested {
        return;
    }
    result = self.step(visitor);
    if self.halt(visitor) {
        return;
    }
    if int(result.get("n_write", 0) or 0) == 0 and visitor.build_nudges < 2 {
        visitor.build_nudges += 1;
        self.ctx.append(
            {
                "role": "user",
                "content": (
                    "You ended Build having called write_file ZERO times -- you only "
                    "described code, pasted it into your reply, or left notes. That "
                    "is not building. Call write_file NOW with the COMPLETE Jac "
                    "contents of each file the task needs (for a UI, e.g. "
                    "components/Calculator.cl.jac as a `def:pub Calculator() -> "
                    "JsxElement` component, and edit main.jac to render it). Write "
                    "real Jac files this turn -- do not explain, just write them."
                )
            }
        );
        _term_print(
            "  ↳ Build wrote no files -- re-entering Build to actually write code",
            style="yellow"
        );
        visit self;
    } else {
        visit [->:Flow:->];
    }
}

impl QA.run with AgentSession entry {
    if agent.bus.cancel_requested {
        return;
    }
    self.step(visitor);
    if self.halt(visitor) {
        return;
    }
    if agent.ws.project_errors() {
        n = len(agent.ws.project_errors());
        _term_print(
            f"  ↳ project has {n} compile error(s) -- returning to Build",
            style="yellow"
        );
        visit [->:Flow:->][?:Build];
    } else {
        agent.bus.open_convo(
            [
                {
                    "role": "system",
                    "content": "Routing: pick the single next state along this node's out-edges (Build to fix, Plan to rethink, Done only once verified)."
                },
                {
                    "role": "user",
                    "content": f"Objective:\n{visitor.objective}\n\nProgress so far:\n{visitor.ledger.render()}\n\nStep: {visitor.steps} of at most {visitor.max_steps}"
                }
            ]
        );
        visit [->:Flow:->] by agent_model(
            stream=True,
            stream_handler=agent.view.route_stream_event,
            incl_info={
                "Objective": visitor.objective,
                "Progress so far": visitor.ledger.render(),
                "Step": f"{visitor.steps} of at most {visitor.max_steps}",
                "How to choose": "Pick the single next state. Choose Done only once you have actually verified the result; go back to Build to fix problems QA found, or to Plan to rethink the approach."
            }
        );
    }
}

sem Done = "the DONE state: the session is complete. Reach it from QA once the objective is fully built AND verified (type-checked, and for an app, run and exercised), or directly from Plan when the request was a pure question or read-only inspection that needed no file changes and has been answered. Ends the session.";
impl Done.finish{
    _term_print("\n  ● Done", style="bold green");
    agent.bus.enter("Done");
}

impl build_pipeline -> Plan {
    plan = Plan();
    build = Build();
    qa = QA();
    done = Done();
    plan +>:Flow:+> build;

    plan +>:Flow:+> done;
    build +>:Flow:+> qa;
    qa +>:Flow:+> build;
    qa +>:Flow:+> plan;
    qa +>:Flow:+> done;

    for ph in [plan, build, qa] {
        for spec in TOOL_SPECS {
            if type(ph) in spec.phases {
                ph +>:Exposes:+> Tool(
                    fn=spec.fn, category=spec.category, serialize=spec.serialize
                );
            }
        }
    }
    return plan;
}

impl AgentSession.begin{
    visit build_pipeline();
}
