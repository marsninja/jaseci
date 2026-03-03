"""Test type inference for ternary (if-else) expressions."""

with entry {
    # Same type on both branches → inferred as str.
    label = "yes" if True else "no";
    ok_str: str = label;  # <-- OK
    bad_int: int = label;  # <-- Error

    # Same type on both branches → inferred as list.
    items = [1, 2] if True else [];
    ok_list: list = items;  # <-- OK
    bad_str: str = items;  # <-- Error
}
