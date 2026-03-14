"""Fixture for E2044: Abstract archetype has unimplemented abstract abilities."""

@abstract
obj Animal {
    def speak() -> str;
    def move() -> str;
}

obj Dog(Animal) {
    def speak() -> str {
        return "Woof";
    }
    # Missing move()!  # <-- Error E2044: Dog does not implement 'move'
}

obj Cat(Animal) {
    def speak() -> str {
        return "Meow";
    }
    def move() -> str {
        return "slink";
    }
    # <-- Ok: all abstract methods implemented
}
