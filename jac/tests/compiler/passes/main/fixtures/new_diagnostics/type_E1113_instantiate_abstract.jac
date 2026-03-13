"""Fixture for E1113: Cannot instantiate abstract archetype."""

@abstract
obj Shape {
    def area -> float;
}

obj Circle(Shape) {
    has radius: float;
    def area -> float {
        return 3.14159 * self.radius * self.radius;
    }
}

with entry {
    c = Circle(radius=5.0);  # <-- Ok: concrete class
    s = Shape();             # <-- Error E1113: cannot instantiate abstract
}
