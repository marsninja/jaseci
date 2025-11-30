class Foo {
    has bar: int;
    has baz: int;
}

with entry {
    foo = Foo();
    foo.recover_name_token;
}
