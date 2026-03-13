"""Fixture for E0076: Class body contains duplicate method definitions."""

obj Foo {
    def bar -> None { }
    def baz -> None { }  # <-- Ok: different name
    def bar -> int {     # <-- Error E0076: duplicate 'bar'
        return 0;
    }
}
