"""Test various pure expressions that should be extracted."""

with entry {
    # Literals
    int_val = 42;
    float_val = 3.14;
    str_val = "hello";
    bool_val = True;
    null_val = None;

    # Collections
    list_val = [1, 2, 3];
    dict_val = {"a": 1, "b": 2};
    tuple_val = (1, 2, 3);
    set_val = {1, 2, 3};

    # Binary operations on literals
    sum_val = 1 + 2;
    product = 3 * 4;

    # Unary operations
    neg_val = -5;
    not_val = not False;
}
