"""sv<->na equivalence: json.

The same `import from json { loads, dumps }` binds CPython on the sv backend and
na_stdlib/json.na.jac on the na backend. Each backend builds the SAME line digest
of every operation and returns it as one string (a dict[str,any] does not marshal
back across the na->sv return boundary, but a scalar str does); `with entry` then
diffs the two digests line-by-line. All values are routed through `dumps` so the
digest is pure str concatenation (no native int(any)/str(any) coercion).
"""
import from json { loads, dumps }

"""Compare two newline digests; print each mismatching line; return the count."""
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

"""Decode an na digest (a native str returns as bytes across the boundary)."""
def _dec(x: any) -> str {
    if isinstance(x, bytes) { return x.decode("utf-8", "surrogatepass"); }
    return x as str;
}

sv {
    def json_sv() -> str {
        sc: any = loads("{\"a\": 1, \"b\": \"hi\", \"c\": true, \"d\": false, \"g\": -7}");
        arr: any = loads("[1, 2, 3]");
        om: dict[str, any] = {"i": 1, "s": "x", "b": True, "z": None};
        p: list[str] = [];
        p.append("rt_a=" + dumps(sc["a"]));
        p.append("rt_b=" + dumps(sc["b"]));
        p.append("rt_c=" + dumps(sc["c"]));
        p.append("rt_d=" + dumps(sc["d"]));
        p.append("rt_g=" + dumps(sc["g"]));
        p.append("rt_null=" + dumps(loads("null")));
        p.append("d_int=" + dumps(42));
        p.append("d_negint=" + dumps(-7));
        p.append("d_str=" + dumps("hi"));
        p.append("d_true=" + dumps(True));
        p.append("d_false=" + dumps(False));
        p.append("d_none=" + dumps(None));
        p.append("d_list=" + dumps(arr));
        p.append("d_obj_mixed=" + dumps(om));
        return "\n".join(p);
    }
}

na {
    def json_na() -> str {
        sc: any = loads("{\"a\": 1, \"b\": \"hi\", \"c\": true, \"d\": false, \"g\": -7}");
        arr: any = loads("[1, 2, 3]");
        om: dict[str, any] = {"i": 1, "s": "x", "b": True, "z": None};
        p: list[str] = [];
        p.append("rt_a=" + dumps(sc["a"]));
        p.append("rt_b=" + dumps(sc["b"]));
        p.append("rt_c=" + dumps(sc["c"]));
        p.append("rt_d=" + dumps(sc["d"]));
        p.append("rt_g=" + dumps(sc["g"]));
        p.append("rt_null=" + dumps(loads("null")));
        p.append("d_int=" + dumps(42));
        p.append("d_negint=" + dumps(-7));
        p.append("d_str=" + dumps("hi"));
        p.append("d_true=" + dumps(True));
        p.append("d_false=" + dumps(False));
        p.append("d_none=" + dumps(None));
        p.append("d_list=" + dumps(arr));
        p.append("d_obj_mixed=" + dumps(om));
        return "\n".join(p);
    }
}

with entry {
    bad = _diff("json", json_sv(), _dec(json_na()));
    assert bad == 0, f"json: {bad} mismatch(es)";
}
