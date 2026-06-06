"""Native fixture for structural match patterns.

Exercises sequence patterns (fixed-length, element capture, trailing and
mid-list star), mapping patterns, and class/archetype patterns — all
lowered by NaIRGenPass. Captures are pinned with `as` casts where used in
arithmetic, since match captures infer as Unknown in the type checker.

Each matcher has a `drive_*` helper that builds its inputs natively and
returns an encoded scalar, so the ctypes test never marshals a native
container across the FFI boundary.
"""

def seq_fixed(x: list[int]) -> int {
    match x {
        case [ 1 , 2 , 3 ]:
            return 1;

        case [ 10 , 20 ]:
            return 2;

        case _:
            return 0;

    }
}

def seq_capture(x: list[int]) -> int {
    match x {
        case [ a , b ]:
            return (a as int) * 10 + (b as int);

        case _:
            return -1;

    }
}

def seq_trailing_star(x: list[int]) -> int {
    match x {
        case [ 0 , * rest ]:
            return len((rest as list[int]));

        case _:
            return -1;

    }
}

def seq_mid_star(x: list[int]) -> int {
    match x {
        case [ first , * mid , last ]:
            return (first as int) * 1000 + len((mid as list[int])) * 10 + (last as int);

        case _:
            return -1;

    }
}

obj Point {
    has x: int,
        y: int;
}

def cls_match(p: Point) -> int {
    match p {
        case Point(x = 0, y = 0):
            return 1;

        case Point(x = ax, y = ay):
            return (ax as int) * 100 + (ay as int);

        case _:
            return -1;

    }
}

def map_match(d: dict[str, int]) -> int {
    match d {
        case { "kind" : 1 }:
            return 10;

        case { "kind" : k }:
            return (k as int);

        case _:
            return -1;

    }
}

# ── drivers: build inputs natively, return encoded scalar results ─────────
def drive_seq_fixed -> int {
    a: list[int] = [1, 2, 3];
    b: list[int] = [10, 20];
    c: list[int] = [1, 2];
    return seq_fixed(a) * 100 + seq_fixed(b) * 10 + seq_fixed(c);
}

def drive_seq_capture -> int {
    a: list[int] = [3, 4];
    b: list[int] = [9];
    return seq_capture(a) * 10 + (seq_capture(b) + 1);
}

def drive_seq_trailing_star -> int {
    a: list[int] = [0, 7, 8, 9];
    b: list[int] = [0];
    c: list[int] = [1, 2];
    return seq_trailing_star(a) * 100 + seq_trailing_star(b) * 10 + (
        seq_trailing_star(c) + 1
    );
}

def drive_seq_mid_star -> int {
    a: list[int] = [5, 6, 7, 8, 9];
    b: list[int] = [1, 2];
    return seq_mid_star(a) + seq_mid_star(b);
}

def drive_cls -> int {
    p0 = Point(x=0, y=0);
    p1 = Point(x=2, y=3);
    return cls_match(p0) * 1000 + cls_match(p1);
}

def drive_map -> int {
    d1: dict[str, int] = {"kind": 1};
    d2: dict[str, int] = {"kind": 42};
    return map_match(d1) * 100 + map_match(d2);
}
