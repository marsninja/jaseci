"""Test that annotated assignments use the type annotation, not the resolved attribute type."""

obj Foo {
    has name: str;
}

obj Bar {
    has tag: int;
}

with entry {
    # Annotated assignment with union type and None -- should be OK
    a: Foo | None = None;
    b: int | None = None;
    c: str | None = "hello";
    d: int | str = 42;

    # Annotated assignment with compatible value -- should be OK
    e: Foo | None = Foo(name="test");

    # Annotated assignment with incompatible value -- should Error
    f: int | None = "wrong";  # <-- Error: str is not assignable to int | None
    g: Foo | None = Bar(tag=1);  # <-- Error: Bar is not assignable to Foo | None
}
