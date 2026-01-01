"""Test fixture for null-safe operator (?.) type checking."""

obj Person {
    has name: str,
        age: int;
}

with entry {
    # Optional person
    maybe_person: Person | None = None;

    # Null-safe member access returns T | None
    name = maybe_person?.name;  # <-- type should be str | None

    # Non-optional person
    person: Person = Person(name="Alice", age=30);

    # Regular member access on non-optional
    regular_name: str = person.name;  # <-- Ok

    # Null-safe on non-optional also returns T | None
    safe_name = person?.name;  # <-- type is str | None

    # Error: trying to assign T | None to T
    strict_name: str = maybe_person?.name;  # <-- Error: str | None not assignable to str
}
