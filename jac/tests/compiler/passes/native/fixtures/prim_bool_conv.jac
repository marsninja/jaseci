"""Bool conversion primitives: bool() on int, float, string.

Cross-backend equivalence fixture — Python reference + native implementation.
"""

def bool_conv_py() -> dict {
    return {
        # bool(int)
        "bool_zero": 1 if bool(0) else 0,
        "bool_one": 1 if bool(1) else 0,
        "bool_neg": 1 if bool(-1) else 0,
        "bool_big": 1 if bool(42) else 0,
        # bool(float)
        "bool_fzero": 1 if bool(0.0) else 0,
        "bool_fone": 1 if bool(1.0) else 0,
        "bool_fneg": 1 if bool(-0.5) else 0,
        # bool(str)
        "bool_empty": 1 if bool("") else 0,
        "bool_nonempty": 1 if bool("hello") else 0,
        "bool_space": 1 if bool(" ") else 0
    };
}

na {
    def bool_conv_na() -> dict[str, any] {
        b_zero: int = 0;
        if bool(0) { b_zero = 1; }
        b_one: int = 0;
        if bool(1) { b_one = 1; }
        b_neg: int = 0;
        if bool(-1) { b_neg = 1; }
        b_big: int = 0;
        if bool(42) { b_big = 1; }
        b_fzero: int = 0;
        if bool(0.0) { b_fzero = 1; }
        b_fone: int = 0;
        if bool(1.0) { b_fone = 1; }
        b_fneg: int = 0;
        if bool(-0.5) { b_fneg = 1; }
        b_empty: int = 0;
        if bool("") { b_empty = 1; }
        b_nonempty: int = 0;
        if bool("hello") { b_nonempty = 1; }
        b_space: int = 0;
        if bool(" ") { b_space = 1; }
        return {
            "bool_zero": b_zero,
            "bool_one": b_one,
            "bool_neg": b_neg,
            "bool_big": b_big,
            "bool_fzero": b_fzero,
            "bool_fone": b_fone,
            "bool_fneg": b_fneg,
            "bool_empty": b_empty,
            "bool_nonempty": b_nonempty,
            "bool_space": b_space
        };
    }
}
