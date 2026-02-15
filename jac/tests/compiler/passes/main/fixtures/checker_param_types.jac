nd A {}
nd B {}

def foo(a: A) -> None { }

with entry {
    foo(A());  # <-- Ok
    foo(B());  # <-- Error
}
