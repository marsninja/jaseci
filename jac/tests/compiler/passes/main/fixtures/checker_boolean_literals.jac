"""Test fixture for boolean literal type checking."""

def accepts_bool(x: bool) -> bool {
    return x;
}

def accepts_int(x: int) -> int {
    return x;
}

with entry {
    # Boolean literals should be typed
    t = True;
    f = False;

    # Should work with bool parameter
    accepts_bool(True);  # <-- Ok
    accepts_bool(False);  # <-- Ok
    accepts_bool(t);  # <-- Ok

    # Bool is subtype of int
    accepts_int(True);  # <-- Ok
    accepts_int(1);  # <-- Ok

    # String should not work
    accepts_bool("true");  # <-- Error
}
