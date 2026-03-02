"""Test that protocol conformance checks walk the full MRO chain."""
import from typing { Protocol }

obj Describable(Protocol) {
    def describe() -> str { }
}

obj Base {
    def describe() -> str {
        return "base";
    }
}

obj Child(Base) {
    has name: str;
}

obj Unrelated {
    has value: int;
}

def show(d: Describable) -> str {
    return d.describe();
}

with entry {
    # Base directly implements describe -- should be OK
    show(Base());

    # Child inherits describe from Base via MRO -- should be OK
    show(Child(name="test"));

    # Unrelated does not implement describe -- should Error
    show(Unrelated(value=1));  # <-- Error
}
