"""Rec 8 — `try { } awaiting { }` slot on the `sv` (streaming SSR) target.

Today this fixture fires W2020 ("`awaiting` is not yet implemented on
the 'sv' target") and the awaiting body is silently dropped at codegen
time. Once the streaming-SSR lowering lands, the awaiting body should
render as the fallback frame during the dispatched-but-not-joined window
and W2020 should no longer fire.
"""

obj User {
    has name: str,
        bio: str;
}

def:pub UserPanel(user: User) -> JsxElement {
    return
        <section class="panel">
            {try {
                <div class="card">
                    <h2>{user.name}</h2>
                    <p>{user.bio}</p>
                </div>
            } awaiting {
                <p>Loading…</p>
            }}
        </section>;
}
