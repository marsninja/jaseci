impl AgentEventBus.emit(kind: str, fields: dict) -> None {
    if not self.active_feed {
        return;
    }

    if self.events and self.events[-1].get("streaming") {
        self.publish(dict(self.events[-1]));
    }

    ev = {"id": self._next_id, "kind": kind};
    ev.update(fields);
    self._next_id += 1;
    self.events.append(ev);

    if len(self.events) > self._cap {
        self.events = self.events[-self._cap:];
    }
    self.publish(ev);
}

impl AgentEventBus.emit_stream(kind: str, token: str) -> None {
    if not self.active_feed {
        return;
    }
    if (
        self.events
        and self.events[-1].get("kind") == kind
        and self.events[-1].get("streaming")
    ) {
        self.events[-1]["text"] = str(self.events[-1].get("text", "")) + token;

        ev_with_delta = dict(self.events[-1]);
        ev_with_delta["_delta"] = token;
        self.publish(ev_with_delta);
    } else {
        if self.events and self.events[-1].get("streaming") {
            self.publish(dict(self.events[-1]));
        }
        ev = {"id": self._next_id, "kind": kind, "text": token, "streaming": True};
        self._next_id += 1;
        self.events.append(ev);
        if len(self.events) > self._cap {
            self.events = self.events[-self._cap:];
        }
        self.publish(ev);
    }
}

impl AgentEventBus.enter(phase: str) -> None {
    self.active = phase;
    self.path.append(phase);
    self.emit("phase", {"node": phase});
}

impl AgentEventBus.set_status(s: str) -> None {
    self.status = s;
    self.emit("status", {"status": s});
}

impl AgentEventBus.begin_turn -> None {
    self.active = "";
    self.path = [];
    self.cancel_requested = False;
}

impl AgentEventBus._state -> dict {
    return {
        "status": self.status,
        "active": self.active,
        "path": list(self.path),
        "stats": dict(self.last_stats),
        "needs_key": self.needs_key,
        "key_env": self.key_env,
        "model_name": self.model_name
    };
}

impl AgentEventBus.snapshot -> dict {
    snap = self._state();
    snap["events"] = list(self.events);
    snap["ledger"] = self.ledger_view();
    return snap;
}

impl AgentEventBus.ledger_view -> dict {
    led = agent.ledger;
    if led is None {
        return {"changes": [], "notes": []};
    }
    return {"changes": list(led.changes), "notes": list(led.notes)};
}

impl AgentEventBus.publish_ledger -> None {
    if not self.active_feed or not self._subscribers {
        return;
    }

    msg = self._state();
    msg["ledger"] = self.ledger_view();
    for q in list(self._subscribers) {
        try {
            q.put_nowait(msg);
        } except Exception { }
    }
}

impl AgentEventBus.subscribe -> any {
    import from queue { Queue }
    q = Queue(maxsize=512);
    self._subscribers.append(q);
    return q;
}

impl AgentEventBus.unsubscribe(q: any) -> None {
    if q in self._subscribers {
        self._subscribers.remove(q);
    }
}

impl AgentEventBus.publish(ev: dict) -> None {
    if not self.active_feed or not self._subscribers {
        return;
    }

    msg = self._state();
    msg["ev"] = ev;
    for q in list(self._subscribers) {
        try {
            q.put_nowait(msg);
        } except Exception { }
    }
}

impl AgentEventBus.publish_full -> None {
    if not self._subscribers {
        return;
    }
    msg = self._state();
    msg["full"] = True;
    msg["events"] = list(self.events);
    msg["ledger"] = self.ledger_view();
    for q in list(self._subscribers) {
        try {
            q.put_nowait(msg);
        } except Exception { }
    }
}

glob _CALL_LOG_CAP = 500;

impl _san_msg(m: any) -> dict {
    import json;
    role_raw: any = m.get("role") if isinstance(m, dict) else (m?.role or "");
    role = str(role_raw or "");

    if "." in role {
        role = role.split(".")[-1];
    }
    role = role.lower();
    content = m.get("content") if isinstance(m, dict) else (m?.content or "");
    content = "" if content is None else str(content);
    tcs: any = m.get("tool_calls") if isinstance(m, dict) else m?.tool_calls;
    tools: list[str] = [];
    if tcs {
        for tc in tcs {
            fn: any = tc?.function;
            if fn is None and isinstance(tc, dict) {
                fn = tc.get("function");
            }
            name: any = fn?.name;
            if name is None and isinstance(fn, dict) {
                name = fn.get("name");
            }
            raw: any = fn?.arguments;
            if raw is None and isinstance(fn, dict) {
                raw = fn.get("arguments");
            }
            args_str = "";
            try {
                parsed = json.loads(raw) if isinstance(raw, str) else (raw or {});
                args_str = json.dumps(parsed) if isinstance(parsed, dict) else str(raw);
            } except Exception {
                args_str = str(raw);
            }
            tools.append(f"{name or '?'}({args_str})");
        }
    }
    return {"role": role, "content": content, "tools": tools};
}

def _remember_convo(snap: list) {
    cur = agent.bus.convos.get(agent.bus._cur_convo, []);
    if len(snap) > len(cur) {
        agent.bus.convos[agent.bus._cur_convo] = snap;
    }
}

impl AgentEventBus.open_convo(msgs: any) -> None {
    if not self.active_feed {
        return;
    }
    self._convo_seq += 1;
    self._cur_convo = self._convo_seq;
    self.convos[self._cur_convo] = [_san_msg(m) for m in msgs];
}

impl AgentEventBus.set_pending(msgs: any) -> None {
    if self.active_feed {
        _remember_convo([_san_msg(m) for m in msgs]);
    }
}

impl AgentEventBus.close_convo(msgs: any) -> None {
    if self.active_feed {
        _remember_convo([_san_msg(m) for m in msgs]);
    }
}

impl AgentEventBus.set_convo_tools(tools: list[Callable]) -> None {
    if not self.active_feed {
        return;
    }
    import json;
    import from byllm.types { Tool }
    recs: list[dict] = [];
    for fn in tools {
        name = str(getattr(fn, "__name__", "?") or "?");
        try {
            schema: any = Tool(fn).get_json_schema();
            fdef: any = schema.get("function", {});
            recs.append(
                {
                    "name": str(fdef.get("name", "") or name),
                    "description": str(fdef.get("description", "")),
                    "schema": json.dumps(schema, indent=2)
                }
            );
        } except Exception as e {
            recs.append(
                {
                    "name": name,
                    "description": "",
                    "schema": f"(schema unavailable: {e})"
                }
            );
        }
    }
    self.convo_tools[self._cur_convo] = recs;
}

impl AgentEventBus.emit_call(fields: dict) -> None {
    if not self.active_feed {
        return;
    }

    cid = self._next_id;
    self.emit("call", fields);
    self.call_log.append(
        {
            "id": cid,
            "node": str(fields.get("node", "")),
            "convo": self._cur_convo,
            "tokens_in": int(fields.get("tokens_in", 0) or 0),
            "tokens_out": int(fields.get("tokens_out", 0) or 0)
        }
    );
    if len(self.call_log) > _CALL_LOG_CAP {
        self.call_log = self.call_log[-_CALL_LOG_CAP:];
        keep = {c["convo"] for c in self.call_log};
        self.convos = {
            k: v
            for (k, v) in self.convos.items()
            if k in keep
        };
        self.convo_tools = {
            k: v
            for (k, v) in self.convo_tools.items()
            if k in keep
        };
    }
}
