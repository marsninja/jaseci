"""List method primitives: append, extend, insert, pop, clear, index, reverse, copy.

Cross-backend equivalence fixture.
"""

def list_methods_py() -> dict {
    a1: list = [1, 2, 3];
    a1.append(4);

    a2: list = [1, 2];
    a2.extend([3, 4, 5]);

    a3: list = [1, 3, 4];
    a3.insert(1, 2);

    a4: list = [10, 20, 30];
    popped_last: int = a4.pop();

    a5: list = [10, 20, 30];
    popped_first: int = a5.pop(0);

    a6: list = [1, 2, 3];
    a6.clear();

    a7: list = [10, 20, 30, 20];
    idx: int = a7.index(20);

    a8: list = [3, 1, 2];
    a8.reverse();

    a9: list = [1, 2, 3];
    a9_copy: list = a9.copy();

    a: list = [10, 20, 30];
    a.append(40);
    append_len: int = len(a);
    append_last: int = a[3];

    b: list = [10, 20, 30];
    get_val: int = b[1];
    b[1] = 99;
    set_val: int = b[1];

    c: list = [];
    c.append(1);
    c.append(2);
    c.append(3);
    c.append(4);
    c.append(5);
    multi_len: int = len(c);

    d: list = [10, 20, 30];
    pop_val: int = d.pop();
    pop_len: int = len(d);

    e: list = [10, 20, 30];
    e.clear();
    clear_len: int = len(e);

    f: list = [10, 20, 30, 20];
    index_found: int = f.index(20);

    g: list = [10, 20, 30];
    g.reverse();
    rev_first: int = g[0];
    rev_last: int = g[2];

    h: list = [10, 20, 30];
    h2: list = h.copy();
    copy_len: int = len(h2);
    copy_first: int = h2[0];

    return {
        "after_append": a1,
        "after_extend": a2,
        "after_insert": a3,
        "popped_last": popped_last,
        "after_pop_last": a4,
        "popped_first": popped_first,
        "after_pop_first": a5,
        "after_clear": a6,
        "index": idx,
        "after_reverse": a8,
        "copy": a9_copy,
        "append_len": append_len,
        "append_last": append_last,
        "get_val": get_val,
        "set_val": set_val,
        "multi_append_len": multi_len,
        "multi_append_first": c[0],
        "multi_append_last": c[4],
        "pop_val": pop_val,
        "pop_len": pop_len,
        "clear_len": clear_len,
        "index_found": index_found,
        "rev_first": rev_first,
        "rev_last": rev_last,
        "copy_len": copy_len,
        "copy_first": copy_first
    };
}

cl def list_methods_cl() -> dict {
    a1: list = [1, 2, 3];
    a1.append(4);

    a2: list = [1, 2];
    a2.extend([3, 4, 5]);

    a3: list = [1, 3, 4];
    a3.insert(1, 2);

    a4: list = [10, 20, 30];
    popped_last: int = a4.pop();

    a5: list = [10, 20, 30];
    popped_first: int = a5.pop(0);

    a6: list = [1, 2, 3];
    a6.clear();

    a7: list = [10, 20, 30, 20];
    idx: int = a7.index(20);

    a8: list = [3, 1, 2];
    a8.reverse();

    a9: list = [1, 2, 3];
    a9_copy: list = a9.copy();

    return {
        "after_append": a1,
        "after_extend": a2,
        "after_insert": a3,
        "popped_last": popped_last,
        "after_pop_last": a4,
        "popped_first": popped_first,
        "after_pop_first": a5,
        "after_clear": a6,
        "index": idx,
        "after_reverse": a8,
        "copy": a9_copy
    };
}

na {
    def list_methods_na() -> dict[str, any] {
        a: list[int] = [10, 20, 30];
        a.append(40);
        append_len: int = len(a);
        append_last: int = a[3];

        b: list[int] = [10, 20, 30];
        get_val: int = b[1];
        b[1] = 99;
        set_val: int = b[1];

        c: list[int] = [];
        c.append(1);
        c.append(2);
        c.append(3);
        c.append(4);
        c.append(5);
        multi_len: int = len(c);

        d: list[int] = [10, 20, 30];
        pop_val: int = d.pop();
        pop_len: int = len(d);

        e: list[int] = [10, 20, 30];
        e.clear();
        clear_len: int = len(e);

        f: list[int] = [10, 20, 30, 20];
        index_found: int = f.index(20);

        g: list[int] = [10, 20, 30];
        g.reverse();
        rev_first: int = g[0];
        rev_last: int = g[2];

        h: list[int] = [10, 20, 30];
        h2: list[int] = h.copy();
        copy_len: int = len(h2);
        copy_first: int = h2[0];

        return {
            "append_len": append_len,
            "append_last": append_last,
            "get_val": get_val,
            "set_val": set_val,
            "multi_append_len": multi_len,
            "multi_append_first": c[0],
            "multi_append_last": c[4],
            "pop_val": pop_val,
            "pop_len": pop_len,
            "clear_len": clear_len,
            "index_found": index_found,
            "rev_first": rev_first,
            "rev_last": rev_last,
            "copy_len": copy_len,
            "copy_first": copy_first
        };
    }
}
