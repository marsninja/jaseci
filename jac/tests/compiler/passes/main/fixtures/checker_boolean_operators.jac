"""Test fixture for boolean operator (and/or) type checking."""

with entry {
    # Same types with 'and' - should return that type
    a: int = 1;
    b: int = 2;
    result1: int = a and b;  # <-- Ok
    result2: str = a and b;  # <-- Error: int not assignable to str

    # Same types with 'or' - should return that type
    x: str = "hello";
    y: str = "world";
    result3: str = x or y;  # <-- Ok
    result4: int = x or y;  # <-- Error: str not assignable to int

    # Comparison expressions return bool
    cmp1: bool = a < b;  # <-- Ok
    cmp2: bool = a == b;  # <-- Ok
    cmp3: bool = x != y;  # <-- Ok
    # Note: bool is a subclass of int in Python, so this is valid
    cmp4: int = a < b;  # <-- Ok (bool is subclass of int)
    cmp5: str = a < b;  # <-- Error: bool not assignable to str

    # Chained comparisons
    in_range: bool = 1 < a < 10;  # <-- Ok
}
