"""Custom exception subclass with fields (issue #7320 Cluster 3).

Raising an Exception subclass and reading its field in the handler read
garbage before the fix (the caught binding did not carry the raised
object's fields).
"""

obj ParseError(Exception) {
    has line_no: int = 0,
        hint: str = "";
}

def boom(n: int) -> int {
    raise ParseError(line_no=n, hint="bad" + "token");
    return 0;
}

def:pub subclass_field_roundtrip -> int {
    try {
        boom(42);
    } except ParseError as e {
        ok_hint = 1 if e.hint == "badtoken" else 0;
        return e.line_no * 10 + ok_hint;
    }
    return -1;
}

with entry {
    subclass_field_roundtrip();
}
