obj SomeObj {
    has a: int = 5,
        b: int = 0;
}

with entry {
    ob = SomeObj();
    a = {ob: "check"};
    print(a[ob]);
    ob.a = 10;
    ob.b = 20;
    print(a[ob]);
}
