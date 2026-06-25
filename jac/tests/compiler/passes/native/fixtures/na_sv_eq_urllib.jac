"""sv<->na equivalence: urllib.request.

`import urllib.request` binds CPython on sv; the na block imports the bundled
na_stdlib/urllib/request.na.jac (libcurl floor). `with entry` stands up a loopback
HTTP server, publishes its port, and compares status / body-length / body across
both backends. NOTE the API itself diverges -- sv reads the body via `resp.read()`,
na via the `resp.body` (bytes) field -- so each side computes the equivalent value
its own way; only the logical outputs are compared.
"""
import os;
import socket;
import threading;
import urllib.request;

def _diff(label: str, want: str, got: str) -> int {
    wl = want.split("\n");
    gl = got.split("\n");
    n = len(wl) if len(wl) > len(gl) else len(gl);
    bad = 0;
    for i in range(n) {
        w = wl[i] if i < len(wl) else "<none>";
        g = gl[i] if i < len(gl) else "<none>";
        if w != g {
            print(f"  [FAIL] {label}: sv={repr(w)} na={repr(g)}");
            bad += 1;
        }
    }
    status = "OK" if bad == 0 else "MISMATCH";
    print(f"{label}: {n - bad}/{n} lines match -- {status}");
    return bad;
}

def _dec(x: any) -> str {
    if isinstance(x, bytes) { return x.decode("utf-8", "surrogatepass"); }
    return x as str;
}

"""Minimal one-shot loopback HTTP server: every request -> 200 + a fixed body."""
def _serve(srv: any) -> None {
    resp: bytes = b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 19\r\nConnection: close\r\n\r\nhello-from-loopback";
    while True {
        try {
            pair = srv.accept();
            conn = pair[0];
            conn.recv(4096);
            conn.sendall(resp);
            conn.close();
        } except Exception as e {
            return;
        }
    }
}

sv {
    def urllib_sv() -> str {
        base = "http://127.0.0.1:" + (os.getenv("JAC_URLLIB_EQ_PORT") as str);
        resp = urllib.request.urlopen(base + "/hello");
        body = resp.read();
        p: list[str] = [];
        p.append("status=" + str(resp.status));
        p.append("body_len=" + str(len(body)));
        p.append("body=" + body.decode());
        return "\n".join(p);
    }
}

na {
    import from urllib.request { urlopen }

    def urllib_na() -> str {
        base = "http://127.0.0.1:" + (os.getenv("JAC_URLLIB_EQ_PORT") as str);
        resp = urlopen(base + "/hello");
        p: list[str] = [];
        p.append("status=" + str(resp.status));
        p.append("body_len=" + str(resp.body_length));
        p.append("body=" + resp.body.decode());
        return "\n".join(p);
    }
}

with entry {
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM);
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1);
    srv.bind(("127.0.0.1", 0));
    sn = srv.getsockname();
    port = sn[1];
    srv.listen(8);
    os.environ["JAC_URLLIB_EQ_PORT"] = str(port);
    t = threading.Thread(target=_serve, args=(srv,));
    t.daemon = True;
    t.start();
    bad = _diff("urllib", urllib_sv(), _dec(urllib_na()));
    assert bad == 0, f"urllib: {bad} mismatch(es)";
}
