"""Builtin function primitives not covered by prim_builtins / prim_jac_runtime.

Cross-backend equivalence fixture.
Covers type constructors: dict, set, tuple, frozenset, bytes, complex, bytearray,
and extra builtins: hex, oct, bin, round, float, str(float), list.count.
"""

def builtins_extra_py() -> dict {
    d: dict = dict([["a", 1], ["b", 2]]);
    s: list = sorted(list(set([3, 1, 2, 1])));
    t: list = list(tuple([10, 20, 30]));
    fs: list = sorted(list(frozenset([5, 3, 5, 1])));
    by: list = list(bytes([65, 66, 67]));
    ba: list = list(bytearray([68, 69]));

    c = complex(3, 4);
    c_eq: bool = c == complex(3, 4);

    return {
        "dict": d, "set": s, "tuple": t,
        "frozenset": fs, "bytes": by, "bytearray": ba,
        "complex_eq": c_eq,
        "hex_0": hex(0),
        "hex_255": hex(255),
        "hex_16": hex(16),
        "hex_neg": hex(-1),
        "oct_0": oct(0),
        "oct_8": oct(8),
        "oct_255": oct(255),
        "oct_neg": oct(-1),
        "bin_0": bin(0),
        "bin_1": bin(1),
        "bin_10": bin(10),
        "bin_255": bin(255),
        "bin_neg": bin(-1),
        "round_int": round(5),
        "round_float_down": round(3.2),
        "round_float_up": round(3.7),
        "round_neg": round(-2.3),
        "float_from_str": float("3.14"),
        "float_from_int_str": float("42"),
        "float_neg_str": float("-1.5"),
        "str_from_int": str(42),
        "str_from_neg": str(-17),
        "list_count_one": [10, 20, 30, 20].count(20),
        "list_count_zero": [10, 20, 30].count(99),
        "list_count_many": [1, 1, 1, 2, 1].count(1)
    };
}

cl def builtins_extra_cl() -> dict {
    d: dict = dict([["a", 1], ["b", 2]]);
    s: list = sorted(list(set([3, 1, 2, 1])));
    t: list = list(tuple([10, 20, 30]));
    fs: list = sorted(list(frozenset([5, 3, 5, 1])));
    by: list = list(bytes([65, 66, 67]));
    ba: list = list(bytearray([68, 69]));

    c = complex(3, 4);
    c_eq: bool = c == complex(3, 4);

    return {
        "dict": d, "set": s, "tuple": t,
        "frozenset": fs, "bytes": by, "bytearray": ba,
        "complex_eq": c_eq
    };
}

na {
    def builtins_extra_na() -> dict[str, any] {
        lst1: list[int] = [10, 20, 30, 20];
        lst2: list[int] = [10, 20, 30];
        lst3: list[int] = [1, 1, 1, 2, 1];

        return {
            "hex_0": hex(0),
            "hex_255": hex(255),
            "hex_16": hex(16),
            "hex_neg": hex(-1),
            "oct_0": oct(0),
            "oct_8": oct(8),
            "oct_255": oct(255),
            "oct_neg": oct(-1),
            "bin_0": bin(0),
            "bin_1": bin(1),
            "bin_10": bin(10),
            "bin_255": bin(255),
            "bin_neg": bin(-1),
            "round_int": round(5),
            "round_float_down": round(3.2),
            "round_float_up": round(3.7),
            "round_neg": round(-2.3),
            "float_from_str": float("3.14"),
            "float_from_int_str": float("42"),
            "float_neg_str": float("-1.5"),
            "str_from_int": str(42),
            "str_from_neg": str(-17),
            "list_count_one": lst1.count(20),
            "list_count_zero": lst2.count(99),
            "list_count_many": lst3.count(1)
        };
    }
}
