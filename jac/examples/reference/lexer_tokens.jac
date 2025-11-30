# Lexer tokens - Builtin type keywords
with entry {
    # These lexer tokens are used as type annotations
    # They are keywords that represent builtin types
    x: str = "string";
    y: int = 42;
    z: float = 3.14;
    lst: list = [1, 2, 3];
    tup: tuple = (1, 2);
    s: set = {1,2};
    d: dict = {"key": "value"};
    b: bool = True;

<<<<<<< HEAD
    print(x, y, z, lst, tup, s, d, b);# Note: These are tokenized specially so they can be used as types
=======
    print(x, y, z, lst, tup, s, d, b);  # Note: These are tokenized specially so they can be used as types
>>>>>>> c690ab9f4 (ok, hooks running internally)
    # See builtin_types.jac for more comprehensive type usage examples

}
