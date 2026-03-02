"""Builtin list() and set() type conversion functions.

Cross-backend equivalence fixture.
Note: set iteration order is unspecified; only len and sum are checked for
set-sourced results.
"""

def builtin_convert_py() -> dict {
    nums_list: list[int] = [1, 2, 3];
    nums_set: set[int] = {1, 2, 3};

    # list(list) -> copy, preserves order
    ll: list[int] = list(nums_list);
    # set(set) -> copy, check len only
    ss: set[int] = set(nums_set);
    # list(set) -> conversion; order unspecified, check len and sum
    ls: list[int] = list(nums_set);
    # set(list) -> conversion, check len only
    sl: set[int] = set(nums_list);

    return {
        "ll_len": len(ll), "ll0": ll[0], "ll2": ll[2],
        "ss_len": len(ss),
        "ls_len": len(ls), "ls_sum": sum(ls),
        "sl_len": len(sl)
    };
}

na {
    def builtin_convert_na() -> dict[str, any] {
        nums_list: list[int] = [1, 2, 3];
        nums_set: set[int] = {1, 2, 3};

        ll: list[int] = list(nums_list);
        ss: set[int] = set(nums_set);
        ls: list[int] = list(nums_set);
        sl: set[int] = set(nums_list);

        return {
            "ll_len": len(ll), "ll0": ll[0], "ll2": ll[2],
            "ss_len": len(ss),
            "ls_len": len(ls), "ls_sum": sum(ls),
            "sl_len": len(sl)
        };
    }
}
