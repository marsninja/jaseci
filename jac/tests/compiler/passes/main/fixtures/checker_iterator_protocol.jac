"""Test fixture for iterator protocol type checking."""

with entry {
    # Standard list iteration
    nums: list[int] = [1, 2, 3];
    for n in nums {
        x: int = n;  # <-- Ok
        y: str = n;  # <-- Error
    }

    # Dict iteration yields keys
    d: dict[str, int] = {"a": 1, "b": 2};
    for k in d {
        s: str = k;  # <-- Ok
        i: int = k;  # <-- Error
    }
}
