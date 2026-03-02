"""String method primitives: case, search, modify, split/join, alignment, char tests.

Cross-backend equivalence fixture.
"""

def str_methods_py() -> dict {
    s1: str = "HELLO WORLD";
    s2: str = "hello world";
    s3: str = "  Hello, World!  ";
    s4: str = "hello world hello";
    csv: str = "a,b,c";
    short: str = "hi";
    alnum: str = "abc123";
    spaces: str = "   ";
    sep: str = ",";
    items: list = ["x", "y", "z"];

    return {
        "lower": s1.lower(),
        "upper": s2.upper(),
        "casefold": s1.casefold(),
        "find": s2.find("world"),
        "find_miss": s2.find("xyz"),
        "rfind": s4.rfind("hello"),
        "startswith_t": s2.startswith("hello"),
        "startswith_f": s2.startswith("world"),
        "endswith_t": s2.endswith("world"),
        "endswith_f": s2.endswith("hello"),
        "replace": s2.replace("world", "jac"),
        "strip": s3.strip(),
        "lstrip": s3.lstrip(),
        "rstrip": s3.rstrip(),
        "split": csv.split(","),
        "join": sep.join(items),
        "ljust": short.ljust(10),
        "rjust": short.rjust(10),
        "isalnum_t": alnum.isalnum(),
        "isalpha_t": "abc".isalpha(),
        "isalpha_f": alnum.isalpha(),
        "isascii_t": s2.isascii(),
        "isdecimal_t": "123".isdecimal(),
        "isdecimal_f": "12.3".isdecimal(),
        "isdigit_t": "456".isdigit(),
        "isdigit_f": "45x".isdigit(),
        "isidentifier_t": "my_var".isidentifier(),
        "isidentifier_f": "3bad".isidentifier(),
        "islower_t": s2.islower(),
        "islower_f": s1.islower(),
        "isupper_t": s1.isupper(),
        "isupper_f": s2.isupper(),
        "isspace_t": spaces.isspace(),
        "isspace_f": s2.isspace(),
        "isprintable_t": s2.isprintable(),
        "eq_t": s2 == "hello world",
        "eq_f": s2 == "other",
        "ne_t": s2 != "other",
        "lt": "abc" < "xyz",
        "gt": "xyz" > "abc",
        "le": "abc" <= "abc",
        "ge": "xyz" >= "abc",
        "strip_tabs": "\thello\t".strip(),
        "split_len": len("a,b,c".split(",")),
        "split_space_len": len("hello world foo".split(" ")),
        "concat": "hello" + " " + "world",
        "len_hello": len("hello"),
        "len_empty": len(""),
        "upper_mixed": "Hello World".upper(),
        "lower_mixed": "Hello World".lower(),
        "find_start": "hello world".find("hello"),
        "startswith_true": 1 if "hello world".startswith("hello") else 0,
        "startswith_false": 1 if "hello world".startswith("world") else 0,
        "endswith_true": 1 if "hello world".endswith("world") else 0,
        "endswith_false": 1 if "hello world".endswith("hello") else 0
    };
}

cl def str_methods_cl() -> dict {
    s1: str = "HELLO WORLD";
    s2: str = "hello world";
    s3: str = "  Hello, World!  ";
    s4: str = "hello world hello";
    csv: str = "a,b,c";
    short: str = "hi";
    alnum: str = "abc123";
    spaces: str = "   ";
    sep: str = ",";
    items: list = ["x", "y", "z"];

    return {
        "lower": s1.lower(),
        "upper": s2.upper(),
        "casefold": s1.casefold(),
        "find": s2.find("world"),
        "find_miss": s2.find("xyz"),
        "rfind": s4.rfind("hello"),
        "startswith_t": s2.startswith("hello"),
        "startswith_f": s2.startswith("world"),
        "endswith_t": s2.endswith("world"),
        "endswith_f": s2.endswith("hello"),
        "replace": s2.replace("world", "jac"),
        "strip": s3.strip(),
        "lstrip": s3.lstrip(),
        "rstrip": s3.rstrip(),
        "split": csv.split(","),
        "join": sep.join(items),
        "ljust": short.ljust(10),
        "rjust": short.rjust(10),
        "isalnum_t": alnum.isalnum(),
        "isalpha_t": "abc".isalpha(),
        "isalpha_f": alnum.isalpha(),
        "isascii_t": s2.isascii(),
        "isdecimal_t": "123".isdecimal(),
        "isdecimal_f": "12.3".isdecimal(),
        "isdigit_t": "456".isdigit(),
        "isdigit_f": "45x".isdigit(),
        "isidentifier_t": "my_var".isidentifier(),
        "isidentifier_f": "3bad".isidentifier(),
        "islower_t": s2.islower(),
        "islower_f": s1.islower(),
        "isupper_t": s1.isupper(),
        "isupper_f": s2.isupper(),
        "isspace_t": spaces.isspace(),
        "isspace_f": s2.isspace(),
        "isprintable_t": s2.isprintable(),
        "eq_t": s2 == "hello world",
        "eq_f": s2 == "other",
        "ne_t": s2 != "other",
        "lt": "abc" < "xyz",
        "gt": "xyz" > "abc",
        "le": "abc" <= "abc",
        "ge": "xyz" >= "abc"
    };
}

na {
    def str_methods_na() -> dict[str, any] {
        s1: str = "  Hello, World!  ";
        s2: str = "\thello\t";
        s3: str = "a,b,c";
        s4: str = "hello world foo";
        s5: str = "hello world";
        s6: str = "HELLO WORLD";
        s7: str = "Hello World";
        s8: str = "hello world";
        parts1: list[str] = s3.split(",");
        parts2: list[str] = s4.split(" ");
        sw_true: int = 0;
        if s8.startswith("hello") { sw_true = 1; }
        sw_false: int = 0;
        if s8.startswith("world") { sw_false = 1; }
        ew_true: int = 0;
        if s8.endswith("world") { ew_true = 1; }
        ew_false: int = 0;
        if s8.endswith("hello") { ew_false = 1; }
        return {
            "strip": s1.strip(),
            "strip_tabs": s2.strip(),
            "split_len": len(parts1),
            "split_space_len": len(parts2),
            "concat": "hello" + " " + "world",
            "len_hello": len("hello"),
            "len_empty": len(""),
            "upper": s5.upper(),
            "lower": s6.lower(),
            "upper_mixed": s7.upper(),
            "lower_mixed": s7.lower(),
            "find_hit": s8.find("world"),
            "find_miss": s8.find("xyz"),
            "find_start": s8.find("hello"),
            "startswith_true": sw_true,
            "startswith_false": sw_false,
            "endswith_true": ew_true,
            "endswith_false": ew_false
        };
    }
}
