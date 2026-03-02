"""Builtin str.partition(), str.rpartition(), str.splitlines(), str.rsplit().

Cross-backend equivalence fixture.
Note: rsplit() without maxsplit is identical to split() in result ordering.
"""

def str_partition_py() -> dict {
    # partition: separator found
    p1: list[str] = list("hello world".partition(" "));
    # partition: separator not found -> [original, "", ""]
    p2: list[str] = list("hello".partition("x"));
    # rpartition: last occurrence
    rp1: list[str] = list("hello world foo".rpartition(" "));
    # rpartition: not found -> ["", "", original]
    rp2: list[str] = list("hello".rpartition("x"));
    # splitlines
    sl: list[str] = "a\nb\nc".splitlines();
    # rsplit without maxsplit == split
    rs: list[str] = "a b c".rsplit(" ");

    return {
        "p1_0": p1[0], "p1_1": p1[1], "p1_2": p1[2],
        "p2_0": p2[0], "p2_2": p2[2],
        "rp1_0": rp1[0], "rp1_1": rp1[1], "rp1_2": rp1[2],
        "rp2_0": rp2[0], "rp2_2": rp2[2],
        "sl_len": len(sl), "sl0": sl[0], "sl2": sl[2],
        "rs_len": len(rs), "rs0": rs[0], "rs2": rs[2]
    };
}

cl def str_partition_cl() -> dict {
    # partition: separator found
    p1: list[str] = list("hello world".partition(" "));
    # partition: separator not found -> [original, "", ""]
    p2: list[str] = list("hello".partition("x"));
    # rpartition: last occurrence
    rp1: list[str] = list("hello world foo".rpartition(" "));
    # rpartition: not found -> ["", "", original]
    rp2: list[str] = list("hello".rpartition("x"));
    # splitlines
    sl: list[str] = "a\nb\nc".splitlines();
    # rsplit without maxsplit == split
    rs: list[str] = "a b c".rsplit(" ");

    return {
        "p1_0": p1[0], "p1_1": p1[1], "p1_2": p1[2],
        "p2_0": p2[0], "p2_2": p2[2],
        "rp1_0": rp1[0], "rp1_1": rp1[1], "rp1_2": rp1[2],
        "rp2_0": rp2[0], "rp2_2": rp2[2],
        "sl_len": len(sl), "sl0": sl[0], "sl2": sl[2],
        "rs_len": len(rs), "rs0": rs[0], "rs2": rs[2]
    };
}

na {
    def str_partition_na() -> dict[str, any] {
        p1: list[str] = "hello world".partition(" ");
        p2: list[str] = "hello".partition("x");
        rp1: list[str] = "hello world foo".rpartition(" ");
        rp2: list[str] = "hello".rpartition("x");
        sl: list[str] = "a\nb\nc".splitlines();
        rs: list[str] = "a b c".rsplit(" ");

        return {
            "p1_0": p1[0], "p1_1": p1[1], "p1_2": p1[2],
            "p2_0": p2[0], "p2_2": p2[2],
            "rp1_0": rp1[0], "rp1_1": rp1[1], "rp1_2": rp1[2],
            "rp2_0": rp2[0], "rp2_2": rp2[2],
            "sl_len": len(sl), "sl0": sl[0], "sl2": sl[2],
            "rs_len": len(rs), "rs0": rs[0], "rs2": rs[2]
        };
    }
}
