"""Float method primitives: is_integer, conjugate, floor division.

Cross-backend equivalence fixture — Python reference + native implementation.
"""

def float_methods_py() -> dict {
    return {
        # is_integer
        "isint_whole": 1 if (3.0).is_integer() else 0,
        "isint_frac": 1 if (3.5).is_integer() else 0,
        "isint_zero": 1 if (0.0).is_integer() else 0,
        "isint_neg_whole": 1 if (-4.0).is_integer() else 0,
        "isint_neg_frac": 1 if (-4.5).is_integer() else 0,
        # conjugate
        "conjugate_pos": (3.14).conjugate(),
        "conjugate_neg": (-2.5).conjugate(),
        "conjugate_zero": (0.0).conjugate(),
        # floor division
        "floordiv_pos": 7.0 // 2.0,
        "floordiv_neg": -7.0 // 2.0,
        "floordiv_exact": 6.0 // 3.0,
        "floordiv_small": 1.0 // 3.0,
        "floordiv_neg2": 7.0 // -2.0
    };
}

na {
    def float_methods_na() -> dict[str, any] {
        a: float = 3.0;
        b: float = 3.5;
        c: float = 0.0;
        d: float = -4.0;
        e: float = -4.5;
        isint_a: int = 0;
        if a.is_integer() { isint_a = 1; }
        isint_b: int = 0;
        if b.is_integer() { isint_b = 1; }
        isint_c: int = 0;
        if c.is_integer() { isint_c = 1; }
        isint_d: int = 0;
        if d.is_integer() { isint_d = 1; }
        isint_e: int = 0;
        if e.is_integer() { isint_e = 1; }
        return {
            # is_integer
            "isint_whole": isint_a,
            "isint_frac": isint_b,
            "isint_zero": isint_c,
            "isint_neg_whole": isint_d,
            "isint_neg_frac": isint_e,
            # conjugate
            "conjugate_pos": (3.14).conjugate(),
            "conjugate_neg": (-2.5).conjugate(),
            "conjugate_zero": (0.0).conjugate(),
            # floor division
            "floordiv_pos": 7.0 // 2.0,
            "floordiv_neg": -7.0 // 2.0,
            "floordiv_exact": 6.0 // 3.0,
            "floordiv_small": 1.0 // 3.0,
            "floordiv_neg2": 7.0 // -2.0
        };
    }
}
