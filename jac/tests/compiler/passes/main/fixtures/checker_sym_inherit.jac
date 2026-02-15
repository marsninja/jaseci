nd Parent {
    has val: int = 42;
}

nd Child(Parent) {}

with entry {
    c = Child();
    c.val = 42;  # <-- Ok
    c.val = "str";  # <-- Error
}
