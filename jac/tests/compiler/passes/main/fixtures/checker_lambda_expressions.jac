"""Test fixture for lambda expression type checking."""

with entry {
    # Simple lambda with type annotations
    add = lambda x: int, y: int -> int { return x + y; };
    result1: int = add(5, 3);  # <-- Ok
    result2: str = add(5, 3);  # <-- Error: int not assignable to str

    # Lambda assigned to variable and called
    double = lambda x: int -> int { return x * 2; };
    doubled: int = double(5);  # <-- Ok
    doubled_str: str = double(5);  # <-- Error: int not assignable to str

    # Lambda with wrong argument types
    add(1, "hello");  # <-- Error: str not assignable to int
}
