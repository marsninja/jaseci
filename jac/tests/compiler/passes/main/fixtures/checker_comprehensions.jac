"""Test fixture for comprehension type checking."""

with entry {
    # List comprehension
    nums: list[int] = [1, 2, 3, 4, 5];
    squares: list[int] = [x * x for x in nums];  # <-- Ok
    result1: int = squares[0];  # <-- Ok
    result2: str = squares[0];  # <-- Error: int not assignable to str

    # Dict comprehension
    d: dict[str, int] = {str(x): x for x in nums};  # <-- Ok
    val1: int = d["1"];  # <-- Ok
    val2: str = d["1"];  # <-- Error: int not assignable to str

    # Set comprehension
    unique: set[int] = {x % 3 for x in nums};  # <-- Ok
}
