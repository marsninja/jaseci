"""Test fixture for ternary (if-else) expression type checking."""

with entry {
    # Same types - should return that type
    x: int = 10;
    result1: int = x if True else 20;  # <-- Ok
    result2: str = x if True else 20;  # <-- Error: int not assignable to str

    # Different but compatible types
    name: str = "Alice";
    msg: str = name if True else "Unknown";  # <-- Ok

    # One type is subtype of other
    a: float = 1.5;
    b: int = 2;
    result3: float = a if True else b;  # <-- Ok (int is compatible with float)
    result4: int = a if True else b;  # <-- Error: float not assignable to int
}
