"""Test fixture for slice expression type checking."""

with entry {
    # List slicing
    nums: list[int] = [1, 2, 3, 4, 5];

    # Slice returns list type
    sliced1: list[int] = nums[1:3];  # <-- Ok
    sliced2: list[int] = nums[::2];  # <-- Ok
    sliced3: list[int] = nums[:];    # <-- Ok

    # Wrong type assignment for sliced list
    sliced_err: str = nums[1:3];  # <-- Error: list[int] not assignable to str

    # Index access returns element type
    elem: int = nums[0];  # <-- Ok
    elem_err: str = nums[0];  # <-- Error: int not assignable to str

    # String slicing
    s: str = "hello";
    sub: str = s[1:4];  # <-- Ok
}
