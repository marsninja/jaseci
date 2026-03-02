"""String methods not covered by prim_str_methods / prim_jac_runtime.

Cross-backend equivalence fixture.
Covers: format_map, expandtabs, translate + maketrans, op_mod (%),
encode, title, rfind, ljust, rjust, zfill.
"""

def str_extra_py() -> dict {
    fm1: str = "{name} is {age}".format_map({"name": "Bob", "age": "30"});
    fm2: str = "{x}{y}{x}".format_map({"x": "a", "y": "b"});

    tab: str = chr(9);
    et1: str = ("a" + tab + "b" + tab + "c").expandtabs(4);
    et2: str = (tab + tab).expandtabs(8);
    et3: str = "no tabs here".expandtabs(4);

    table = str.maketrans("helo", "HELO");
    tr1: str = "hello world".translate(table);

    mod1: str = "Hello %s" % "world";
    mod2: str = "Value: %d" % 42;

    enc1: list = list("hello".encode());
    enc2: list = list("".encode());

    return {
        "fm1": fm1, "fm2": fm2,
        "et1": et1, "et2": et2, "et3": et3,
        "tr1": tr1,
        "mod1": mod1, "mod2": mod2,
        "enc1": enc1, "enc2": enc2,
        "title_basic": "hello world".title(),
        "title_upper": "HELLO WORLD".title(),
        "title_mixed": "hELLO wORLD".title(),
        "title_single": "hello".title(),
        "title_empty": "".title(),
        "title_spaces": "hello  world".title(),
        "rfind_basic": "hello world hello".rfind("hello"),
        "rfind_single": "abcabc".rfind("abc"),
        "rfind_miss": "hello".rfind("xyz"),
        "rfind_start": "hello".rfind("hello"),
        "rfind_empty_sub": "hello".rfind(""),
        "ljust_pad": "hi".ljust(5),
        "ljust_exact": "hello".ljust(5),
        "ljust_nopad": "hello world".ljust(5),
        "rjust_pad": "hi".rjust(5),
        "rjust_exact": "hello".rjust(5),
        "rjust_nopad": "hello world".rjust(5),
        "zfill_pad": "42".zfill(5),
        "zfill_exact": "12345".zfill(5),
        "zfill_nopad": "123456".zfill(5),
        "zfill_neg": "-42".zfill(5),
        "zfill_plus": "+42".zfill(5)
    };
}

cl def str_extra_cl() -> dict {
    fm1: str = "{name} is {age}".format_map({"name": "Bob", "age": "30"});
    fm2: str = "{x}{y}{x}".format_map({"x": "a", "y": "b"});

    tab: str = chr(9);
    et1: str = ("a" + tab + "b" + tab + "c").expandtabs(4);
    et2: str = (tab + tab).expandtabs(8);
    et3: str = "no tabs here".expandtabs(4);

    table = str.maketrans("helo", "HELO");
    tr1: str = "hello world".translate(table);

    mod1: str = "Hello %s" % "world";
    mod2: str = "Value: %d" % 42;

    enc1: list = list("hello".encode());
    enc2: list = list("".encode());

    return {
        "fm1": fm1, "fm2": fm2,
        "et1": et1, "et2": et2, "et3": et3,
        "tr1": tr1,
        "mod1": mod1, "mod2": mod2,
        "enc1": enc1, "enc2": enc2
    };
}

na {
    def str_extra_na() -> dict[str, any] {
        return {
            "title_basic": "hello world".title(),
            "title_upper": "HELLO WORLD".title(),
            "title_mixed": "hELLO wORLD".title(),
            "title_single": "hello".title(),
            "title_empty": "".title(),
            "title_spaces": "hello  world".title(),
            "rfind_basic": "hello world hello".rfind("hello"),
            "rfind_single": "abcabc".rfind("abc"),
            "rfind_miss": "hello".rfind("xyz"),
            "rfind_start": "hello".rfind("hello"),
            "rfind_empty_sub": "hello".rfind(""),
            "ljust_pad": "hi".ljust(5),
            "ljust_exact": "hello".ljust(5),
            "ljust_nopad": "hello world".ljust(5),
            "rjust_pad": "hi".rjust(5),
            "rjust_exact": "hello".rjust(5),
            "rjust_nopad": "hello world".rjust(5),
            "zfill_pad": "42".zfill(5),
            "zfill_exact": "12345".zfill(5),
            "zfill_nopad": "123456".zfill(5),
            "zfill_neg": "-42".zfill(5),
            "zfill_plus": "+42".zfill(5)
        };
    }
}
