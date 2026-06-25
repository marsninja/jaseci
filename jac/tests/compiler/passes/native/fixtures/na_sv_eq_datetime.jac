"""sv<->na equivalence: datetime.

Same `import from datetime { datetime, timezone }` binds CPython on sv and
na_stdlib/datetime.na.jac on na. Exercises the static-method (fromtimestamp/now)
and class-attribute (timezone.utc) surface plus the floor-division civil split
(a fixed positive and a pre-1970 negative timestamp). now() is non-deterministic,
so only structural range checks are compared.
"""
import from datetime { datetime, timezone }

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

sv {
    def datetime_sv() -> str {
        dt = datetime.fromtimestamp(1700000000.0, timezone.utc);
        neg = datetime.fromtimestamp(-86401.0, timezone.utc);
        now = datetime.now(timezone.utc);
        p: list[str] = [];
        p.append("year=" + str(dt.year));
        p.append("month=" + str(dt.month));
        p.append("day=" + str(dt.day));
        p.append("hour=" + str(dt.hour));
        p.append("minute=" + str(dt.minute));
        p.append("second=" + str(dt.second));
        p.append("weekday=" + str(dt.weekday()));
        p.append("iso=" + dt.isoformat());
        p.append("neg_day=" + str(neg.day));
        p.append("neg_weekday=" + str(neg.weekday()));
        p.append("neg_iso=" + neg.isoformat());
        p.append("now_year_ok=" + str(1 if now.year >= 2024 else 0));
        p.append("now_mon_ok=" + str(1 if now.month >= 1 and now.month <= 12 else 0));
        p.append("now_wd_ok=" + str(1 if now.weekday() >= 0 and now.weekday() <= 6 else 0));
        return "\n".join(p);
    }
}

na {
    def datetime_na() -> str {
        dt: datetime = datetime.fromtimestamp(1700000000.0, timezone.utc);
        neg: datetime = datetime.fromtimestamp(-86401.0, timezone.utc);
        now: datetime = datetime.now(timezone.utc);
        p: list[str] = [];
        p.append("year=" + str(dt.year));
        p.append("month=" + str(dt.month));
        p.append("day=" + str(dt.day));
        p.append("hour=" + str(dt.hour));
        p.append("minute=" + str(dt.minute));
        p.append("second=" + str(dt.second));
        p.append("weekday=" + str(dt.weekday()));
        p.append("iso=" + dt.isoformat());
        p.append("neg_day=" + str(neg.day));
        p.append("neg_weekday=" + str(neg.weekday()));
        p.append("neg_iso=" + neg.isoformat());
        p.append("now_year_ok=" + str(1 if now.year >= 2024 else 0));
        p.append("now_mon_ok=" + str(1 if now.month >= 1 and now.month <= 12 else 0));
        p.append("now_wd_ok=" + str(1 if now.weekday() >= 0 and now.weekday() <= 6 else 0));
        return "\n".join(p);
    }
}

with entry {
    bad = _diff("datetime", datetime_sv(), _dec(datetime_na()));
    assert bad == 0, f"datetime: {bad} mismatch(es)";
}
