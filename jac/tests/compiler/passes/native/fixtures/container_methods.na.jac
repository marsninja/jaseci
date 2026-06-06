"""Native fixture locking in the container / string / numeric method surface.

Covers dict (get/pop/update/clear), set (remove/discard/union/intersection),
str (upper/lower/startswith/endswith/find/replace/join), frozenset, complex
numbers (construction / .real / .imag / arithmetic), and custom exception
classes. Each driver returns an encoded scalar.
"""

def dict_ops -> int {
    d: dict[str, int] = {"a": 1, "b": 2};
    a: int = 0;
    a = a + d.get("a");
    v = d.pop("b");
    a = a + v * 10;
    o: dict[str, int] = {"c": 3, "e": 4};
    d.update(o);
    a = a + len(d) * 100;
    d.clear();
    a = a + len(d) * 1000;
    return a;
}

def set_ops -> int {
    s: set[int] = {1, 2, 3, 4};
    s.remove(2);
    s.discard(99);
    t: set[int] = {3, 4, 5};
    u = s.union(t);
    i = s.intersection(t);
    return len(u) * 10 + len(i);
}

def str_ops -> int {
    s: str = "Hello World";
    a: int = 0;
    if s.upper() == "HELLO WORLD" {
        a = a + 1;
    }
    if s.lower() == "hello world" {
        a = a + 2;
    }
    if s.startswith("Hello") {
        a = a + 4;
    }
    if s.endswith("World") {
        a = a + 8;
    }
    if s.find("World") == 6 {
        a = a + 16;
    }
    if s.replace("World", "Jac") == "Hello Jac" {
        a = a + 32;
    }
    return a;
}

def str_join_ret -> str {
    parts: list[str] = ["a", "b", "c"];
    return "-".join(parts);
}

def frozenset_ops -> int {
    f: frozenset = frozenset({1, 2, 3});
    g: frozenset = frozenset({2, 3, 4});
    u = f.union(g);
    i = f.intersection(g);
    return len(u) * 10 + len(i);
}

def complex_ops -> float {
    c: complex = complex(1.0, 2.0);
    d: complex = complex(3.0, 4.0);
    e = c + d;
    return e.real * 100.0 + e.imag;
}

obj AppError(Exception) {
    has code: int;
}

def custom_exc(n: int) -> int {
    try {
        if n < 0 {
            raise AppError(code=7);
        }
        return n;
    } except AppError as e {
        return -1;
    }
}
