"""Test with entry containing non-pure expressions that should NOT be extracted."""

with entry {
    # Function call - not pure
    result = some_function();

    # Attribute access - not pure (could trigger __getattr__)
    value = obj.attr;

    # Index access - not pure (could trigger __getitem__)
    item = arr[0];
}
