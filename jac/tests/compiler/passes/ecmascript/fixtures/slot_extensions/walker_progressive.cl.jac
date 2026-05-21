"""Rec 10 — walker `report` ↔ progressive `awaiting` frames.

When a slot's `try` body spawns a walker, each `report` issued by the
walker during the dispatched-but-not-joined window should stream a
fresh frame into the slot's `awaiting` body. The cl-target lowering
should auto-import `JacProgressiveAwaiting` from `@jac/runtime` and use
it in place of `JacAwaiting` when a walker spawn is detected inside the
try body, so successive walker reports replace the visible fallback
frame.

Gated on the `flow`/`wait` design in #6056.
"""

walker Searcher {
    has query: str;

    can do_search with `root entry {
        report {"phase": "starting", "query": self.query};
        report {"phase": "matches", "results": [self.query + "_a", self.query + "_b"]};
    }
}

def:pub LiveSearch(query: str) -> JsxElement {
    return
        <section class="live">
            {try {
                <ul>
                    {for r in (root spawn Searcher(query=query)).reports {
                        <li key={r["phase"]}>{r["phase"]}</li>
                    }}
                </ul>
            } awaiting {
                <p>Searching…</p>
            }}
        </section>;
}
