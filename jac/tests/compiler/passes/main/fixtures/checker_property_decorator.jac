"""Test fixture for @property decorator type checking."""

obj Circle {
    has radius: float;

    @property
    def area() -> float {
        return 3.14159 * self.radius * self.radius;
    }

    @property
    def diameter() -> float {
        return 2.0 * self.radius;
    }
}

with entry {
    c = Circle(radius=5.0);

    # Property access should return the return type, not FunctionType
    a: float = c.area;  # <-- Ok: area returns float
    d: float = c.diameter;  # <-- Ok: diameter returns float

    # Error cases
    b: str = c.area;  # <-- Error: float not assignable to str
    e: int = c.diameter;  # <-- Error: float not assignable to int
}
