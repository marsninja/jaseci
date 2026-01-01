"""Test fixture for MRO and protocol matching with inheritance."""

import from typing { Protocol }

obj Printable(Protocol) {
    def print_info() -> str { return ""; }
}

obj Serializable(Protocol) {
    def to_json() -> str { return ""; }
}

obj Base {
    def print_info() -> str {
        return "Base";
    }
}

obj Child(Base) {
    has name: str;

    def to_json() -> str {
        return "{}";
    }
}

obj NotPrintable {
    has value: int;
}

def print_it(p: Printable) -> None {
    print(p.print_info());
}

def serialize_it(s: Serializable) -> None {
    print(s.to_json());
}

with entry {
    c = Child(name="Test");
    print_it(c);      # <-- Ok: Child inherits print_info from Base
    serialize_it(c);  # <-- Ok: Child has to_json

    np = NotPrintable(value=42);
    print_it(np);     # <-- Error: NotPrintable doesn't have print_info
}
