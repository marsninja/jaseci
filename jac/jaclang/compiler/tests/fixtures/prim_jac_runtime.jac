"""Comprehensive tests for every _jac runtime namespace.

Cross-backend equivalence fixture.
"""

# =============================================================================
# int namespace: mod, bit_length, bit_count
# =============================================================================

def jac_rt_int_py() -> dict {
    a: int = -7;
    b: int = 3;
    mod_np: int = a % b;
    c: int = 7;
    d: int = -3;
    mod_pn: int = c % d;
    e: int = -7;
    f: int = -3;
    mod_nn: int = e % f;
    mod_pp: int = 10 % 3;

    n0: int = 0;
    bl_0: int = n0.bit_length();
    n5: int = 5;
    bl_5: int = n5.bit_length();
    n255: int = 255;
    bl_255: int = n255.bit_length();

    n7: int = 7;
    bc_7: int = n7.bit_count();
    n10: int = 10;
    bc_10: int = n10.bit_count();
    bc_255: int = n255.bit_count();

    return {
        "mod_np": mod_np, "mod_pn": mod_pn,
        "mod_nn": mod_nn, "mod_pp": mod_pp,
        "bl_0": bl_0, "bl_5": bl_5, "bl_255": bl_255,
        "bc_7": bc_7, "bc_10": bc_10, "bc_255": bc_255
    };
}

cl def jac_rt_int_cl() -> dict {
    a: int = -7;
    b: int = 3;
    mod_np: int = a % b;
    c: int = 7;
    d: int = -3;
    mod_pn: int = c % d;
    e: int = -7;
    f: int = -3;
    mod_nn: int = e % f;
    mod_pp: int = 10 % 3;

    n0: int = 0;
    bl_0: int = n0.bit_length();
    n5: int = 5;
    bl_5: int = n5.bit_length();
    n255: int = 255;
    bl_255: int = n255.bit_length();

    n7: int = 7;
    bc_7: int = n7.bit_count();
    n10: int = 10;
    bc_10: int = n10.bit_count();
    bc_255: int = n255.bit_count();

    return {
        "mod_np": mod_np, "mod_pn": mod_pn,
        "mod_nn": mod_nn, "mod_pp": mod_pp,
        "bl_0": bl_0, "bl_5": bl_5, "bl_255": bl_255,
        "bc_7": bc_7, "bc_10": bc_10, "bc_255": bc_255
    };
}

# =============================================================================
# float namespace: mod, as_integer_ratio
# =============================================================================

def jac_rt_float_py() -> dict {
    fa: float = -7.5;
    fb: float = 2.0;
    fmod1: float = fa % fb;

    half: float = 0.5;
    ratio = half.as_integer_ratio();
    r0: int = ratio[0];
    r1: int = ratio[1];

    quarter: float = 0.25;
    ratio2 = quarter.as_integer_ratio();
    r2_0: int = ratio2[0];
    r2_1: int = ratio2[1];

    return {
        "fmod1": fmod1,
        "ratio_half": [r0, r1],
        "ratio_quarter": [r2_0, r2_1]
    };
}

cl def jac_rt_float_cl() -> dict {
    fa: float = -7.5;
    fb: float = 2.0;
    fmod1: float = fa % fb;

    half: float = 0.5;
    ratio = half.as_integer_ratio();
    r0: int = ratio[0];
    r1: int = ratio[1];

    quarter: float = 0.25;
    ratio2 = quarter.as_integer_ratio();
    r2_0: int = ratio2[0];
    r2_1: int = ratio2[1];

    return {
        "fmod1": fmod1,
        "ratio_half": [r0, r1],
        "ratio_quarter": [r2_0, r2_1]
    };
}

# =============================================================================
# str namespace: comprehensive string method coverage
# =============================================================================

def jac_rt_str_py() -> dict {
    s: str = "hello world";

    cap: str = s.capitalize();
    ttl: str = s.title();
    swp: str = "Hello World".swapcase();

    cnt: int = s.count("l");
    cnt_range: int = s.count("l", 0, 5);
    fnd: int = s.find("world");
    fnd_miss: int = s.find("xyz");
    rfnd: int = s.rfind("l");
    idx: int = s.index("world");
    ridx: int = s.rindex("l");

    sw: bool = s.startswith("hello");
    sw_off: bool = s.startswith("world", 6);
    ew: bool = s.endswith("world");
    ew_off: bool = s.endswith("hello", 0, 5);

    rep: str = s.replace("world", "jac");
    rep_cnt: str = "abab".replace("ab", "X", 1);

    padded: str = "  hello  ";
    stripped: str = padded.strip();
    lstripped: str = padded.lstrip();
    rstripped: str = padded.rstrip();
    char_strip: str = "xxhelloxx".strip("x");

    no_pre: str = "test_file.py".removeprefix("test_");
    no_suf: str = "test_file.py".removesuffix(".py");
    no_pre_miss: str = "test_file.py".removeprefix("foo_");

    parts: list = s.split(" ");
    parts_max: list = "a.b.c.d".split(".", 2);
    rparts: list = "a.b.c.d".rsplit(".", 2);

    part = s.partition(" ");
    part_list: list = [part[0], part[1], part[2]];
    rpart = s.rpartition(" ");
    rpart_list: list = [rpart[0], rpart[1], rpart[2]];

    fmt: str = "Hello {}!".format("Jac");
    fmt_idx: str = "{0} + {1} = {0}{1}".format("a", "b");

    centered: str = "hi".center(10, "-");
    zfilled: str = "42".zfill(5);
    zfilled_neg: str = "-42".zfill(6);

    is_num: bool = "123".isnumeric();
    not_num: bool = "12.3".isnumeric();
    is_ttl: bool = "Hello World".istitle();
    not_ttl: bool = "hello world".istitle();

    return {
        "capitalize": cap, "title": ttl, "swapcase": swp,
        "count": cnt, "count_range": cnt_range,
        "find": fnd, "find_miss": fnd_miss, "rfind": rfnd,
        "index": idx, "rindex": ridx,
        "startswith": sw, "startswith_off": sw_off,
        "endswith": ew, "endswith_off": ew_off,
        "replace": rep, "replace_count": rep_cnt,
        "strip": stripped, "lstrip": lstripped, "rstrip": rstripped,
        "char_strip": char_strip,
        "removeprefix": no_pre, "removesuffix": no_suf,
        "removeprefix_miss": no_pre_miss,
        "split": parts, "split_max": parts_max,
        "rsplit": rparts,
        "partition": part_list, "rpartition": rpart_list,
        "format": fmt, "format_idx": fmt_idx,
        "center": centered, "zfill": zfilled, "zfill_neg": zfilled_neg,
        "isnumeric": is_num, "isnumeric_false": not_num,
        "istitle": is_ttl, "istitle_false": not_ttl
    };
}

cl def jac_rt_str_cl() -> dict {
    s: str = "hello world";

    cap: str = s.capitalize();
    ttl: str = s.title();
    swp: str = "Hello World".swapcase();

    cnt: int = s.count("l");
    cnt_range: int = s.count("l", 0, 5);
    fnd: int = s.find("world");
    fnd_miss: int = s.find("xyz");
    rfnd: int = s.rfind("l");
    idx: int = s.index("world");
    ridx: int = s.rindex("l");

    sw: bool = s.startswith("hello");
    sw_off: bool = s.startswith("world", 6);
    ew: bool = s.endswith("world");
    ew_off: bool = s.endswith("hello", 0, 5);

    rep: str = s.replace("world", "jac");
    rep_cnt: str = "abab".replace("ab", "X", 1);

    padded: str = "  hello  ";
    stripped: str = padded.strip();
    lstripped: str = padded.lstrip();
    rstripped: str = padded.rstrip();
    char_strip: str = "xxhelloxx".strip("x");

    no_pre: str = "test_file.py".removeprefix("test_");
    no_suf: str = "test_file.py".removesuffix(".py");
    no_pre_miss: str = "test_file.py".removeprefix("foo_");

    parts: list = s.split(" ");
    parts_max: list = "a.b.c.d".split(".", 2);
    rparts: list = "a.b.c.d".rsplit(".", 2);
    lines: list = "a\nb\nc".splitlines();

    part = s.partition(" ");
    part_list: list = [part[0], part[1], part[2]];
    rpart = s.rpartition(" ");
    rpart_list: list = [rpart[0], rpart[1], rpart[2]];

    fmt: str = "Hello {}!".format("Jac");
    fmt_idx: str = "{0} + {1} = {0}{1}".format("a", "b");

    centered: str = "hi".center(10, "-");
    zfilled: str = "42".zfill(5);
    zfilled_neg: str = "-42".zfill(6);

    is_num: bool = "123".isnumeric();
    not_num: bool = "12.3".isnumeric();
    is_ttl: bool = "Hello World".istitle();
    not_ttl: bool = "hello world".istitle();

    return {
        "capitalize": cap, "title": ttl, "swapcase": swp,
        "count": cnt, "count_range": cnt_range,
        "find": fnd, "find_miss": fnd_miss, "rfind": rfnd,
        "index": idx, "rindex": ridx,
        "startswith": sw, "startswith_off": sw_off,
        "endswith": ew, "endswith_off": ew_off,
        "replace": rep, "replace_count": rep_cnt,
        "strip": stripped, "lstrip": lstripped, "rstrip": rstripped,
        "char_strip": char_strip,
        "removeprefix": no_pre, "removesuffix": no_suf,
        "removeprefix_miss": no_pre_miss,
        "split": parts, "split_max": parts_max,
        "rsplit": rparts,
        "partition": part_list, "rpartition": rpart_list,
        "format": fmt, "format_idx": fmt_idx,
        "center": centered, "zfill": zfilled, "zfill_neg": zfilled_neg,
        "isnumeric": is_num, "isnumeric_false": not_num,
        "istitle": is_ttl, "istitle_false": not_ttl
    };
}

# =============================================================================
# list namespace: sort, count, remove, index, repeat, comparisons, imul
# =============================================================================

def jac_rt_list_py() -> dict {
    nums: list = [3, 1, 4, 1, 5, 9, 2, 6];
    nums.sort(key=lambda x: -x);

    items: list = [1, 2, 2, 3, 3, 3];
    cnt_2: int = items.count(2);
    cnt_3: int = items.count(3);
    cnt_0: int = items.count(99);

    removable: list = [10, 20, 30, 20];
    removable.remove(20);

    idx: int = items.index(3);
    idx_start: int = items.index(3, 4);

    base: list = [1, 2];
    repeated: list = base * 3;

    a: list = [1, 2, 3];
    b: list = [1, 2, 3];
    c: list = [1, 2, 4];
    d: list = [1, 2];
    eq_t: bool = a == b;
    eq_f: bool = a == c;
    lt_t: bool = a < c;
    lt_f: bool = c < a;
    gt_t: bool = c > a;
    le_t: bool = a <= b;
    le_t2: bool = a <= c;
    ge_t: bool = c >= a;
    lt_len: bool = d < a;

    grow: list = [1, 2];
    grow *= 3;

    return {
        "sort_desc": nums,
        "count_2": cnt_2, "count_3": cnt_3, "count_miss": cnt_0,
        "after_remove": removable,
        "index": idx, "index_start": idx_start,
        "repeat": repeated,
        "eq_true": eq_t, "eq_false": eq_f,
        "lt_true": lt_t, "lt_false": lt_f, "gt_true": gt_t,
        "le_true": le_t, "le_true2": le_t2, "ge_true": ge_t,
        "lt_shorter": lt_len,
        "imul": grow
    };
}

cl def jac_rt_list_cl() -> dict {
    nums: list = [3, 1, 4, 1, 5, 9, 2, 6];
    nums.sort(key=lambda x: -x);

    items: list = [1, 2, 2, 3, 3, 3];
    cnt_2: int = items.count(2);
    cnt_3: int = items.count(3);
    cnt_0: int = items.count(99);

    removable: list = [10, 20, 30, 20];
    removable.remove(20);

    idx: int = items.index(3);
    idx_start: int = items.index(3, 4);

    base: list = [1, 2];
    repeated: list = base * 3;

    a: list = [1, 2, 3];
    b: list = [1, 2, 3];
    c: list = [1, 2, 4];
    d: list = [1, 2];
    eq_t: bool = a == b;
    eq_f: bool = a == c;
    lt_t: bool = a < c;
    lt_f: bool = c < a;
    gt_t: bool = c > a;
    le_t: bool = a <= b;
    le_t2: bool = a <= c;
    ge_t: bool = c >= a;
    lt_len: bool = d < a;

    grow: list = [1, 2];
    grow *= 3;

    return {
        "sort_desc": nums,
        "count_2": cnt_2, "count_3": cnt_3, "count_miss": cnt_0,
        "after_remove": removable,
        "index": idx, "index_start": idx_start,
        "repeat": repeated,
        "eq_true": eq_t, "eq_false": eq_f,
        "lt_true": lt_t, "lt_false": lt_f, "gt_true": gt_t,
        "le_true": le_t, "le_true2": le_t2, "ge_true": ge_t,
        "lt_shorter": lt_len,
        "imul": grow
    };
}

# =============================================================================
# dict namespace: pop, popitem, setdefault, clear, eq
# =============================================================================

def jac_rt_dict_py() -> dict {
    d: dict = {"a": 1, "b": 2, "c": 3};
    popped: int = d.pop("b");
    pop_default: int = d.pop("z", -1);

    d2: dict = {"x": 10, "y": 20, "z": 30};
    item = d2.popitem();
    popitem_key: str = item[0];
    popitem_val: int = item[1];

    d3: dict = {"a": 1};
    sd_existing: int = d3.setdefault("a", 99);
    sd_new = d3.setdefault("b", 42);

    d4: dict = {"x": 1, "y": 2};
    d4.clear();

    da: dict = {"a": 1, "b": 2};
    db: dict = {"b": 2, "a": 1};
    dc: dict = {"a": 1, "b": 3};
    eq_t: bool = da == db;
    eq_f: bool = da == dc;

    return {
        "pop_val": popped, "pop_default": pop_default,
        "after_pop": d,
        "popitem_key": popitem_key, "popitem_val": popitem_val,
        "sd_existing": sd_existing, "sd_new": sd_new,
        "after_setdefault": d3,
        "after_clear": d4,
        "eq_true": eq_t, "eq_false": eq_f
    };
}

cl def jac_rt_dict_cl() -> dict {
    d: dict = {"a": 1, "b": 2, "c": 3};
    popped: int = d.pop("b");
    pop_default: int = d.pop("z", -1);

    d2: dict = {"x": 10, "y": 20, "z": 30};
    item = d2.popitem();
    popitem_key: str = item[0];
    popitem_val: int = item[1];

    d3: dict = {"a": 1};
    sd_existing: int = d3.setdefault("a", 99);
    sd_new = d3.setdefault("b", 42);

    d4: dict = {"x": 1, "y": 2};
    d4.clear();

    da: dict = {"a": 1, "b": 2};
    db: dict = {"b": 2, "a": 1};
    dc: dict = {"a": 1, "b": 3};
    eq_t: bool = da == db;
    eq_f: bool = da == dc;

    return {
        "pop_val": popped, "pop_default": pop_default,
        "after_pop": d,
        "popitem_key": popitem_key, "popitem_val": popitem_val,
        "sd_existing": sd_existing, "sd_new": sd_new,
        "after_setdefault": d3,
        "after_clear": d4,
        "eq_true": eq_t, "eq_false": eq_f
    };
}

# =============================================================================
# set namespace: remove, update, intersection_update, difference_update,
#   symmetric_difference_update, proper subset/superset, eq
# =============================================================================

def jac_rt_set_py() -> dict {
    s1: set = {1, 2, 3, 4};
    s1.remove(3);
    after_remove: list = sorted(list(s1));

    s2: set = {1, 2};
    s2.update({3, 4});
    after_update: list = sorted(list(s2));

    s3: set = {1, 2, 3, 4};
    s3.intersection_update({2, 4, 6});
    after_isect: list = sorted(list(s3));

    s4: set = {1, 2, 3, 4};
    s4.difference_update({2, 4});
    after_diff: list = sorted(list(s4));

    s5: set = {1, 2, 3};
    s5.symmetric_difference_update({2, 3, 4});
    after_symdiff: list = sorted(list(s5));

    small: set = {1, 2};
    big: set = {1, 2, 3};
    same: set = {1, 2};
    proper_sub: bool = small < big;
    not_proper_sub: bool = small < same;
    proper_sup: bool = big > small;
    eq_t: bool = small == same;
    eq_f: bool = small == big;

    return {
        "after_remove": after_remove,
        "after_update": after_update,
        "after_isect": after_isect,
        "after_diff": after_diff,
        "after_symdiff": after_symdiff,
        "proper_subset": proper_sub,
        "not_proper_subset": not_proper_sub,
        "proper_superset": proper_sup,
        "eq_true": eq_t, "eq_false": eq_f
    };
}

cl def jac_rt_set_cl() -> dict {
    s1: set = {1, 2, 3, 4};
    s1.remove(3);
    after_remove: list = sorted(list(s1));

    s2: set = {1, 2};
    s2.update({3, 4});
    after_update: list = sorted(list(s2));

    s3: set = {1, 2, 3, 4};
    s3.intersection_update({2, 4, 6});
    after_isect: list = sorted(list(s3));

    s4: set = {1, 2, 3, 4};
    s4.difference_update({2, 4});
    after_diff: list = sorted(list(s4));

    s5: set = {1, 2, 3};
    s5.symmetric_difference_update({2, 3, 4});
    after_symdiff: list = sorted(list(s5));

    small: set = {1, 2};
    big: set = {1, 2, 3};
    same: set = {1, 2};
    proper_sub: bool = small < big;
    not_proper_sub: bool = small < same;
    proper_sup: bool = big > small;
    eq_t: bool = small == same;
    eq_f: bool = small == big;

    return {
        "after_remove": after_remove,
        "after_update": after_update,
        "after_isect": after_isect,
        "after_diff": after_diff,
        "after_symdiff": after_symdiff,
        "proper_subset": proper_sub,
        "not_proper_subset": not_proper_sub,
        "proper_superset": proper_sup,
        "eq_true": eq_t, "eq_false": eq_f
    };
}

# =============================================================================
# tuple namespace: count, index, repeat, comparisons
# =============================================================================

def jac_rt_tuple_py() -> dict {
    t: tuple = (1, 2, 3, 2, 1);

    cnt: int = t.count(2);
    idx: int = t.index(3);

    t2: tuple = (1, 2);
    repeated: list = list(t2 * 3);

    a: tuple = (1, 2, 3);
    b: tuple = (1, 2, 3);
    c: tuple = (1, 2, 4);
    d: tuple = (1, 2);
    eq_t: bool = a == b;
    eq_f: bool = a == c;
    lt_t: bool = a < c;
    gt_t: bool = c > a;
    le_t: bool = a <= b;
    ge_t: bool = c >= a;
    lt_len: bool = d < a;

    return {
        "count": cnt, "index": idx,
        "repeat": repeated,
        "eq_true": eq_t, "eq_false": eq_f,
        "lt_true": lt_t, "gt_true": gt_t,
        "le_true": le_t, "ge_true": ge_t,
        "lt_shorter": lt_len
    };
}

cl def jac_rt_tuple_cl() -> dict {
    t: tuple = (1, 2, 3, 2, 1);

    cnt: int = t.count(2);
    idx: int = t.index(3);

    t2: tuple = (1, 2);
    repeated: list = list(t2 * 3);

    a: tuple = (1, 2, 3);
    b: tuple = (1, 2, 3);
    c: tuple = (1, 2, 4);
    d: tuple = (1, 2);
    eq_t: bool = a == b;
    eq_f: bool = a == c;
    lt_t: bool = a < c;
    gt_t: bool = c > a;
    le_t: bool = a <= b;
    ge_t: bool = c >= a;
    lt_len: bool = d < a;

    return {
        "count": cnt, "index": idx,
        "repeat": repeated,
        "eq_true": eq_t, "eq_false": eq_f,
        "lt_true": lt_t, "gt_true": gt_t,
        "le_true": le_t, "ge_true": ge_t,
        "lt_shorter": lt_len
    };
}

# =============================================================================
# builtin namespace: round, sum, sorted, enumerate, zip, map, filter, pow
# =============================================================================

def jac_rt_builtin_py() -> dict {
    r1: int = round(3.7);
    r2: float = round(3.14159, 2);

    s: int = sum([1, 2, 3, 4, 5]);
    s_start: int = sum([1, 2, 3], 10);

    srt: list = sorted([3, 1, 4, 1, 5]);
    srt_key: list = sorted(["banana", "apple", "kiwi"], key=lambda x: len(x));

    raw_enum: list = list(enumerate(["a", "b", "c"]));
    enum_result: list = [];
    for pair in raw_enum {
        enum_result.append([pair[0], pair[1]]);
    }
    raw_enum2: list = list(enumerate(["x", "y"], 5));
    enum_start: list = [];
    for pair in raw_enum2 {
        enum_start.append([pair[0], pair[1]]);
    }

    raw_zip: list = list(zip([1, 2, 3], ["a", "b", "c"]));
    zip_result: list = [];
    for pair in raw_zip {
        zip_result.append([pair[0], pair[1]]);
    }
    raw_zip2: list = list(zip([1, 2], ["a", "b", "c"]));
    zip_uneven: list = [];
    for pair in raw_zip2 {
        zip_uneven.append([pair[0], pair[1]]);
    }

    map_result: list = list(map(lambda x: x * 2, [1, 2, 3, 4]));

    filter_result: list = list(filter(lambda x: x > 2, [1, 2, 3, 4, 5]));

    pow_basic: int = pow(2, 10);
    pow_mod: int = pow(2, 10, 100);

    return {
        "round_int": r1, "round_digits": r2,
        "sum": s, "sum_start": s_start,
        "sorted": srt, "sorted_key": srt_key,
        "enumerate": enum_result, "enumerate_start": enum_start,
        "zip": zip_result, "zip_uneven": zip_uneven,
        "map": map_result,
        "filter": filter_result,
        "pow": pow_basic, "pow_mod": pow_mod
    };
}

cl def jac_rt_builtin_cl() -> dict {
    r1: int = round(3.7);
    r2: float = round(3.14159, 2);

    s: int = sum([1, 2, 3, 4, 5]);
    s_start: int = sum([1, 2, 3], 10);

    srt: list = sorted([3, 1, 4, 1, 5]);
    srt_key: list = sorted(["banana", "apple", "kiwi"], key=lambda x: len(x));

    raw_enum: list = list(enumerate(["a", "b", "c"]));
    enum_result: list = [];
    for pair in raw_enum {
        enum_result.append([pair[0], pair[1]]);
    }
    raw_enum2: list = list(enumerate(["x", "y"], 5));
    enum_start: list = [];
    for pair in raw_enum2 {
        enum_start.append([pair[0], pair[1]]);
    }

    raw_zip: list = list(zip([1, 2, 3], ["a", "b", "c"]));
    zip_result: list = [];
    for pair in raw_zip {
        zip_result.append([pair[0], pair[1]]);
    }
    raw_zip2: list = list(zip([1, 2], ["a", "b", "c"]));
    zip_uneven: list = [];
    for pair in raw_zip2 {
        zip_uneven.append([pair[0], pair[1]]);
    }

    map_result: list = list(map(lambda x: x * 2, [1, 2, 3, 4]));

    filter_result: list = list(filter(lambda x: x > 2, [1, 2, 3, 4, 5]));

    pow_basic: int = pow(2, 10);
    pow_mod: int = pow(2, 10, 100);

    return {
        "round_int": r1, "round_digits": r2,
        "sum": s, "sum_start": s_start,
        "sorted": srt, "sorted_key": srt_key,
        "enumerate": enum_result, "enumerate_start": enum_start,
        "zip": zip_result, "zip_uneven": zip_uneven,
        "map": map_result,
        "filter": filter_result,
        "pow": pow_basic, "pow_mod": pow_mod
    };
}

na {
    def jac_rt_int_na() -> dict[str, any] {
        a: int = -7;
        b: int = 3;
        mod_np: int = a % b;
        c: int = 7;
        d: int = -3;
        mod_pn: int = c % d;
        e: int = -7;
        f: int = -3;
        mod_nn: int = e % f;
        mod_pp: int = 10 % 3;

        return {
            "mod_np": mod_np, "mod_pn": mod_pn,
            "mod_nn": mod_nn, "mod_pp": mod_pp
        };
    }
}

na {
    def jac_rt_float_na() -> dict[str, any] {
        fa: float = -7.5;
        fb: float = 2.0;
        fmod1: float = fa % fb;

        return {
            "fmod1": fmod1
        };
    }
}

na {
    def jac_rt_str_na() -> dict[str, any] {
        s: str = "hello world";

        cap: str = s.capitalize();
        swp: str = "Hello World".swapcase();

        cnt: int = s.count("l");
        fnd: int = s.find("world");
        fnd_miss: int = s.find("xyz");

        sw: int = 1 if s.startswith("hello") else 0;
        ew: int = 1 if s.endswith("world") else 0;

        rep: str = s.replace("world", "jac");

        padded: str = "  hello  ";
        stripped: str = padded.strip();
        lstripped: str = padded.lstrip();
        rstripped: str = padded.rstrip();

        parts: list[str] = s.split(" ");
        split_len: int = len(parts);
        split_first: str = parts[0];
        split_last: str = parts[len(parts) - 1];

        return {
            "capitalize": cap, "swapcase": swp,
            "count": cnt,
            "find": fnd, "find_miss": fnd_miss,
            "startswith": sw,
            "endswith": ew,
            "replace": rep,
            "strip": stripped, "lstrip": lstripped, "rstrip": rstripped,
            "split_len": split_len,
            "split_first": split_first,
            "split_last": split_last
        };
    }
}

na {
    def jac_rt_list_na() -> dict[str, any] {
        items: list[int] = [1, 2, 2, 3, 3, 3];
        cnt_2: int = items.count(2);
        cnt_3: int = items.count(3);
        cnt_0: int = items.count(99);

        removable: list[int] = [10, 20, 30, 20];
        removable.remove(20);
        remove_len: int = len(removable);
        remove_first: int = removable[0];
        remove_has_20: int = 1 if 20 in removable else 0;

        srt: list[int] = [3, 1, 4, 1, 5];
        srt.sort();
        sort_first: int = srt[0];
        sort_last: int = srt[len(srt) - 1];

        a: list[int] = [1, 2, 3];
        b: list[int] = [1, 2, 3];
        c: list[int] = [1, 2, 4];
        eq_t: int = 1 if a == b else 0;
        eq_f: int = 1 if a == c else 0;

        grow: list[int] = [1, 2];
        grow += [3, 4];
        grow_len: int = len(grow);
        grow_last: int = grow[len(grow) - 1];

        return {
            "count_2": cnt_2, "count_3": cnt_3, "count_miss": cnt_0,
            "remove_len": remove_len,
            "remove_first": remove_first,
            "remove_has_20": remove_has_20,
            "sort_first": sort_first,
            "sort_last": sort_last,
            "eq_true": eq_t, "eq_false": eq_f,
            "iadd_len": grow_len,
            "iadd_last": grow_last
        };
    }
}

na {
    def jac_rt_dict_na() -> dict[str, any] {
        d: dict[str, int] = {"a": 1, "b": 2, "c": 3};
        popped: int = d.pop("b");
        pop_default: int = d.pop("z", -1);
        after_pop_len: int = len(d);
        after_pop_has_a: int = 1 if "a" in d else 0;
        after_pop_has_b: int = 1 if "b" in d else 0;

        d3: dict[str, int] = {"a": 1};
        sd_existing: int = d3.setdefault("a", 99);
        sd_new: int = d3.setdefault("b", 42);
        after_sd_len: int = len(d3);
        after_sd_has_b: int = 1 if "b" in d3 else 0;

        d4: dict[str, int] = {"x": 1, "y": 2};
        d4.clear();
        after_clear_len: int = len(d4);

        da: dict[str, int] = {"a": 1, "b": 2};
        db: dict[str, int] = {"b": 2, "a": 1};
        dc: dict[str, int] = {"a": 1, "b": 3};
        eq_t: int = 1 if da == db else 0;
        eq_f: int = 1 if da == dc else 0;

        return {
            "pop_val": popped, "pop_default": pop_default,
            "after_pop_len": after_pop_len,
            "after_pop_has_a": after_pop_has_a,
            "after_pop_has_b": after_pop_has_b,
            "sd_existing": sd_existing, "sd_new": sd_new,
            "after_sd_len": after_sd_len,
            "after_sd_has_b": after_sd_has_b,
            "after_clear_len": after_clear_len,
            "eq_true": eq_t, "eq_false": eq_f
        };
    }
}

na {
    def jac_rt_set_na() -> dict[str, any] {
        s1: set[int] = {1, 2, 3, 4};
        s1.remove(3);
        remove_len: int = len(s1);
        remove_has_3: int = 1 if 3 in s1 else 0;
        remove_has_1: int = 1 if 1 in s1 else 0;

        s2: set[int] = {1, 2};
        s2.update({3, 4});
        update_len: int = len(s2);
        update_has_3: int = 1 if 3 in s2 else 0;

        s3: set[int] = {1, 2, 3, 4};
        s3.intersection_update({2, 4, 6});
        isect_len: int = len(s3);
        isect_has_2: int = 1 if 2 in s3 else 0;
        isect_has_1: int = 1 if 1 in s3 else 0;

        s4: set[int] = {1, 2, 3, 4};
        s4.difference_update({2, 4});
        diff_len: int = len(s4);
        diff_has_1: int = 1 if 1 in s4 else 0;
        diff_has_2: int = 1 if 2 in s4 else 0;

        s5: set[int] = {1, 2, 3};
        s5.symmetric_difference_update({2, 3, 4});
        symdiff_len: int = len(s5);
        symdiff_has_1: int = 1 if 1 in s5 else 0;
        symdiff_has_4: int = 1 if 4 in s5 else 0;
        symdiff_has_2: int = 1 if 2 in s5 else 0;

        small: set[int] = {1, 2};
        big: set[int] = {1, 2, 3};
        same: set[int] = {1, 2};
        proper_sub: int = 1 if small < big else 0;
        not_proper_sub: int = 1 if small < same else 0;
        proper_sup: int = 1 if big > small else 0;
        eq_t: int = 1 if small == same else 0;
        eq_f: int = 1 if small == big else 0;

        return {
            "remove_len": remove_len,
            "remove_has_3": remove_has_3,
            "remove_has_1": remove_has_1,
            "update_len": update_len,
            "update_has_3": update_has_3,
            "isect_len": isect_len,
            "isect_has_2": isect_has_2,
            "isect_has_1": isect_has_1,
            "diff_len": diff_len,
            "diff_has_1": diff_has_1,
            "diff_has_2": diff_has_2,
            "symdiff_len": symdiff_len,
            "symdiff_has_1": symdiff_has_1,
            "symdiff_has_4": symdiff_has_4,
            "symdiff_has_2": symdiff_has_2,
            "proper_subset": proper_sub,
            "not_proper_subset": not_proper_sub,
            "proper_superset": proper_sup,
            "eq_true": eq_t, "eq_false": eq_f
        };
    }
}

na {
    def jac_rt_tuple_na() -> dict[str, any] {
        return {};
    }
}

na {
    def jac_rt_builtin_na() -> dict[str, any] {
        r1: int = round(3.7);
        r2: float = round(3.14159, 2);

        srt: list[int] = [3, 1, 4, 1, 5];
        srt.sort();
        sort_first: int = srt[0];
        sort_last: int = srt[len(srt) - 1];
        sort_len: int = len(srt);

        pow_basic: int = pow(2, 10);

        return {
            "round_int": r1, "round_digits": r2,
            "sort_first": sort_first,
            "sort_last": sort_last,
            "sort_len": sort_len,
            "pow": pow_basic
        };
    }
}
