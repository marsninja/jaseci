"""Set method and operator primitives not covered by prim_jac_runtime.

Cross-backend equivalence fixture.
Covers: add, discard, pop, clear, copy, union, intersection, difference,
symmetric_difference, issubset, issuperset, isdisjoint,
op_or, op_and, op_sub, op_xor, op_contains, op_le, op_ge,
op_ior, op_iand, op_isub, op_ixor.

All set results converted to sorted(list(...)) for JSON serialization.
Note: cl def versions use set([...]) constructor for proper type dispatch.
"""

# ---- Mutation methods ----

def set_mutation_py() -> dict {
    s1 = {1, 2, 3};
    s1.add(4);
    after_add: list = sorted(list(s1));

    s2 = {1, 2, 3};
    s2.discard(2);
    s2.discard(99);
    after_discard: list = sorted(list(s2));

    s3 = {42};
    popped: int = s3.pop();
    after_pop: list = sorted(list(s3));

    s4 = {1, 2, 3};
    s4.clear();
    after_clear: list = sorted(list(s4));

    s5 = {10, 20, 30};
    s5_copy: list = sorted(list(s5.copy()));

    return {
        "after_add": after_add,
        "after_discard": after_discard,
        "popped": popped, "after_pop": after_pop,
        "after_clear": after_clear,
        "copy": s5_copy
    };
}

cl def set_mutation_cl() -> dict {
    s1 = set([1, 2, 3]);
    s1.add(4);
    after_add: list = sorted(list(s1));

    s2 = set([1, 2, 3]);
    s2.discard(2);
    s2.discard(99);
    after_discard: list = sorted(list(s2));

    s3 = set([42]);
    popped: int = s3.pop();
    after_pop: list = sorted(list(s3));

    s4 = set([1, 2, 3]);
    s4.clear();
    after_clear: list = sorted(list(s4));

    s5 = set([10, 20, 30]);
    s5_copy: list = sorted(list(s5.copy()));

    return {
        "after_add": after_add,
        "after_discard": after_discard,
        "popped": popped, "after_pop": after_pop,
        "after_clear": after_clear,
        "copy": s5_copy
    };
}

# ---- Set algebra methods ----

def set_algebra_py() -> dict {
    a = {1, 2, 3, 4};
    b = {3, 4, 5, 6};

    union: list = sorted(list(a.union(b)));
    intersection: list = sorted(list(a.intersection(b)));
    difference: list = sorted(list(a.difference(b)));
    sym_diff: list = sorted(list(a.symmetric_difference(b)));

    sub_yes: bool = {1, 2}.issubset({1, 2, 3});
    sub_no: bool = {1, 4}.issubset({1, 2, 3});
    super_yes: bool = {1, 2, 3}.issuperset({1, 2});
    super_no: bool = {1, 2}.issuperset({1, 2, 3});
    disj_yes: bool = {1, 2}.isdisjoint({3, 4});
    disj_no: bool = {1, 2}.isdisjoint({2, 3});

    return {
        "union": union, "intersection": intersection,
        "difference": difference, "sym_diff": sym_diff,
        "sub_yes": sub_yes, "sub_no": sub_no,
        "super_yes": super_yes, "super_no": super_no,
        "disj_yes": disj_yes, "disj_no": disj_no
    };
}

cl def set_algebra_cl() -> dict {
    a = set([1, 2, 3, 4]);
    b = set([3, 4, 5, 6]);

    union: list = sorted(list(a.union(b)));
    intersection: list = sorted(list(a.intersection(b)));
    difference: list = sorted(list(a.difference(b)));
    sym_diff: list = sorted(list(a.symmetric_difference(b)));

    sub_yes: bool = set([1, 2]).issubset(set([1, 2, 3]));
    sub_no: bool = set([1, 4]).issubset(set([1, 2, 3]));
    super_yes: bool = set([1, 2, 3]).issuperset(set([1, 2]));
    super_no: bool = set([1, 2]).issuperset(set([1, 2, 3]));
    disj_yes: bool = set([1, 2]).isdisjoint(set([3, 4]));
    disj_no: bool = set([1, 2]).isdisjoint(set([2, 3]));

    return {
        "union": union, "intersection": intersection,
        "difference": difference, "sym_diff": sym_diff,
        "sub_yes": sub_yes, "sub_no": sub_no,
        "super_yes": super_yes, "super_no": super_no,
        "disj_yes": disj_yes, "disj_no": disj_no
    };
}

# ---- Set operators ----

def set_operators_py() -> dict {
    a = {1, 2, 3, 4};
    b = {3, 4, 5, 6};

    or_op: list = sorted(list(a | b));
    and_op: list = sorted(list(a & b));
    sub_op: list = sorted(list(a - b));
    xor_op: list = sorted(list(a ^ b));

    in_yes: bool = 2 in a;
    in_no: bool = 9 in a;

    le_yes: bool = {1, 2} <= {1, 2, 3};
    le_eq: bool = {1, 2} <= {1, 2};
    le_no: bool = {1, 4} <= {1, 2, 3};
    ge_yes: bool = {1, 2, 3} >= {1, 2};
    ge_eq: bool = {1, 2} >= {1, 2};
    ge_no: bool = {1, 2} >= {1, 2, 3};

    s1 = {1, 2, 3};
    s1 |= {4, 5};
    ior: list = sorted(list(s1));

    s2 = {1, 2, 3, 4};
    s2 &= {2, 3, 5};
    iand: list = sorted(list(s2));

    s3 = {1, 2, 3, 4};
    s3 -= {2, 4};
    isub: list = sorted(list(s3));

    s4 = {1, 2, 3};
    s4 ^= {2, 3, 4};
    ixor: list = sorted(list(s4));

    return {
        "or_op": or_op, "and_op": and_op,
        "sub_op": sub_op, "xor_op": xor_op,
        "in_yes": in_yes, "in_no": in_no,
        "le_yes": le_yes, "le_eq": le_eq, "le_no": le_no,
        "ge_yes": ge_yes, "ge_eq": ge_eq, "ge_no": ge_no,
        "ior": ior, "iand": iand,
        "isub": isub, "ixor": ixor
    };
}

cl def set_operators_cl() -> dict {
    a = set([1, 2, 3, 4]);
    b = set([3, 4, 5, 6]);

    or_op: list = sorted(list(a | b));
    and_op: list = sorted(list(a & b));
    sub_op: list = sorted(list(a - b));
    xor_op: list = sorted(list(a ^ b));

    in_yes: bool = 2 in a;
    in_no: bool = 9 in a;

    le_yes: bool = set([1, 2]) <= set([1, 2, 3]);
    le_eq: bool = set([1, 2]) <= set([1, 2]);
    le_no: bool = set([1, 4]) <= set([1, 2, 3]);
    ge_yes: bool = set([1, 2, 3]) >= set([1, 2]);
    ge_eq: bool = set([1, 2]) >= set([1, 2]);
    ge_no: bool = set([1, 2]) >= set([1, 2, 3]);

    s1 = set([1, 2, 3]);
    s1 |= set([4, 5]);
    ior: list = sorted(list(s1));

    s2 = set([1, 2, 3, 4]);
    s2 &= set([2, 3, 5]);
    iand: list = sorted(list(s2));

    s3 = set([1, 2, 3, 4]);
    s3 -= set([2, 4]);
    isub: list = sorted(list(s3));

    s4 = set([1, 2, 3]);
    s4 ^= set([2, 3, 4]);
    ixor: list = sorted(list(s4));

    return {
        "or_op": or_op, "and_op": and_op,
        "sub_op": sub_op, "xor_op": xor_op,
        "in_yes": in_yes, "in_no": in_no,
        "le_yes": le_yes, "le_eq": le_eq, "le_no": le_no,
        "ge_yes": ge_yes, "ge_eq": ge_eq, "ge_no": ge_no,
        "ior": ior, "iand": iand,
        "isub": isub, "ixor": ixor
    };
}

na {
    def set_mutation_na() -> dict[str, any] {
        s1 = {1, 2, 3};
        s1.add(4);

        s2 = {1, 2, 3};
        s2.discard(2);
        s2.discard(99);

        s3 = {42};
        popped: int = s3.pop();

        s4 = {1, 2, 3};
        s4.clear();

        s5 = {10, 20, 30};

        return {
            "after_add_len": len(s1),
            "after_add_has_4": 1 if 4 in s1 else 0,
            "after_discard_len": len(s2),
            "after_discard_has_1": 1 if 1 in s2 else 0,
            "after_discard_has_2": 1 if 2 in s2 else 0,
            "popped": popped,
            "after_pop_len": len(s3),
            "after_clear_len": len(s4),
            "copy_len": len(s5.copy()),
            "copy_has_10": 1 if 10 in s5 else 0
        };
    }
}

na {
    def set_algebra_na() -> dict[str, any] {
        a = {1, 2, 3, 4};
        b = {3, 4, 5, 6};

        u = a.union(b);
        i_set = a.intersection(b);
        d_set = a.difference(b);

        sub_yes: int = 1 if {1, 2}.issubset({1, 2, 3}) else 0;
        sub_no: int = 1 if {1, 4}.issubset({1, 2, 3}) else 0;
        super_yes: int = 1 if {1, 2, 3}.issuperset({1, 2}) else 0;
        super_no: int = 1 if {1, 2}.issuperset({1, 2, 3}) else 0;
        disj_yes: int = 1 if {1, 2}.isdisjoint({3, 4}) else 0;
        disj_no: int = 1 if {1, 2}.isdisjoint({2, 3}) else 0;

        return {
            "union_len": len(u),
            "union_has_1": 1 if 1 in u else 0,
            "union_has_5": 1 if 5 in u else 0,
            "inter_len": len(i_set),
            "inter_has_3": 1 if 3 in i_set else 0,
            "inter_has_1": 1 if 1 in i_set else 0,
            "diff_len": len(d_set),
            "diff_has_1": 1 if 1 in d_set else 0,
            "diff_has_3": 1 if 3 in d_set else 0,
            "sub_yes": sub_yes, "sub_no": sub_no,
            "super_yes": super_yes, "super_no": super_no,
            "disj_yes": disj_yes, "disj_no": disj_no
        };
    }
}

na {
    def set_operators_na() -> dict[str, any] {
        a = {1, 2, 3, 4};
        b = {3, 4, 5, 6};

        or_set = a | b;
        and_set = a & b;
        sub_set = a - b;
        xor_set = a ^ b;

        in_yes: int = 1 if 2 in a else 0;
        in_no: int = 1 if 9 in a else 0;

        le_yes: int = 1 if {1, 2} <= {1, 2, 3} else 0;
        le_eq: int = 1 if {1, 2} <= {1, 2} else 0;
        le_no: int = 1 if {1, 4} <= {1, 2, 3} else 0;
        ge_yes: int = 1 if {1, 2, 3} >= {1, 2} else 0;
        ge_eq: int = 1 if {1, 2} >= {1, 2} else 0;
        ge_no: int = 1 if {1, 2} >= {1, 2, 3} else 0;

        s1 = {1, 2, 3};
        s1 |= {4, 5};

        s2 = {1, 2, 3, 4};
        s2 &= {2, 3, 5};

        s3 = {1, 2, 3, 4};
        s3 -= {2, 4};

        s4 = {1, 2, 3};
        s4 ^= {2, 3, 4};

        return {
            "or_len": len(or_set),
            "or_has_1": 1 if 1 in or_set else 0,
            "or_has_6": 1 if 6 in or_set else 0,
            "and_len": len(and_set),
            "and_has_3": 1 if 3 in and_set else 0,
            "and_has_1": 1 if 1 in and_set else 0,
            "sub_len": len(sub_set),
            "sub_has_1": 1 if 1 in sub_set else 0,
            "sub_has_3": 1 if 3 in sub_set else 0,
            "xor_len": len(xor_set),
            "xor_has_1": 1 if 1 in xor_set else 0,
            "xor_has_5": 1 if 5 in xor_set else 0,
            "in_yes": in_yes, "in_no": in_no,
            "le_yes": le_yes, "le_eq": le_eq, "le_no": le_no,
            "ge_yes": ge_yes, "ge_eq": ge_eq, "ge_no": ge_no,
            "ior_len": len(s1),
            "ior_has_4": 1 if 4 in s1 else 0,
            "iand_len": len(s2),
            "iand_has_2": 1 if 2 in s2 else 0,
            "iand_has_1": 1 if 1 in s2 else 0,
            "isub_len": len(s3),
            "isub_has_1": 1 if 1 in s3 else 0,
            "ixor_len": len(s4),
            "ixor_has_1": 1 if 1 in s4 else 0,
            "ixor_has_4": 1 if 4 in s4 else 0
        };
    }
}
