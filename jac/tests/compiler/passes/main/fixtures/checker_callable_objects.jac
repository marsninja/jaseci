"""Test fixture for callable object type checking."""

obj Adder {
    has base: int = 0;

    def __call__(x: int, y: int) -> int {
        return self.base + x + y;
    }
}

obj Greeter {
    has prefix: str = "Hello";

    def __call__(name: str) -> str {
        return f"{self.prefix}, {name}!";
    }
}

with entry {
    # Basic callable
    adder = Adder(base=10);
    result1: int = adder(5, 3);  # <-- Ok, returns int
    result2: str = adder(5, 3);  # <-- Error: int not assignable to str

    # Wrong argument types
    adder("a", "b");  # <-- Error: str not assignable to int

    # Missing arguments
    adder(5);  # <-- Error: missing argument 'y'

    # String callable
    greeter = Greeter();
    msg: str = greeter("World");  # <-- Ok
    num: int = greeter("World");  # <-- Error: str not assignable to int

    # Wrong argument type
    greeter(42);  # <-- Error: int not assignable to str
}
