"""Dict method primitives: get, keys, values, items, update, copy, fromkeys.

Cross-backend equivalence fixture.
"""

def dict_methods_py() -> dict {
    d: dict = {"a": 1, "b": 2, "c": 3};

    get_hit: int = d.get("a", 0);
    get_miss: int = d.get("z", -1);

    keys: list = list(d.keys());
    values: list = list(d.values());
    items: list = list(d.items());

    d2: dict = {"x": 10};
    d2.update({"y": 20, "z": 30});

    d3: dict = d.copy();

    fk1: dict = dict.fromkeys(["x", "y", "z"], 0);
    fk2: dict = dict.fromkeys(["a", "b"]);

    d4: dict = {"a": 100, "b": 200, "c": 300};

    return {
        "get_hit": get_hit,
        "get_miss": get_miss,
        "keys": keys,
        "values": values,
        "items": items,
        "after_update": d2,
        "copy": d3,
        "fromkeys_val": fk1,
        "fromkeys_none": fk2,
        "len": len(d4),
        "get_a": d4["a"],
        "get_b": d4["b"],
        "get_c": d4["c"]
    };
}

cl def dict_methods_cl() -> dict {
    d: dict = {"a": 1, "b": 2, "c": 3};

    get_hit: int = d.get("a", 0);
    get_miss: int = d.get("z", -1);

    keys: list = list(d.keys());
    values: list = list(d.values());
    items: list = list(d.items());

    d2: dict = {"x": 10};
    d2.update({"y": 20, "z": 30});

    d3: dict = d.copy();

    fk1: dict = dict.fromkeys(["x", "y", "z"], 0);
    fk2: dict = dict.fromkeys(["a", "b"]);

    return {
        "get_hit": get_hit,
        "get_miss": get_miss,
        "keys": keys,
        "values": values,
        "items": items,
        "after_update": d2,
        "copy": d3,
        "fromkeys_val": fk1,
        "fromkeys_none": fk2
    };
}

na {
    def dict_methods_na() -> dict[str, any] {
        d: dict[str, int] = {"a": 100, "b": 200, "c": 300};
        return {
            "len": len(d),
            "get_a": d["a"],
            "get_b": d["b"],
            "get_c": d["c"]
        };
    }
}
