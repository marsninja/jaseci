"""Test fixture for enum type checking."""
import from enum { Enum }

enum Color(Enum) {
    RED = 1,
    GREEN = 2,
    BLUE = 3
}

enum Status(Enum) {
    PENDING = "pending",
    ACTIVE = "active",
    DONE = "done"
}

def paint(color: Color) -> None {
    print(color);
}

def set_status(status: Status) -> None {
    print(status);
}

with entry {
    # Enum assignment
    c: Color = Color.RED;  # <-- Ok
    s: Status = Status.ACTIVE;  # <-- Ok

    # Function calls with enums
    paint(Color.BLUE);  # <-- Ok
    set_status(Status.DONE);  # <-- Ok

    # Wrong enum type
    paint(Status.ACTIVE);  # <-- Error: Status not assignable to Color
    set_status(Color.RED);  # <-- Error: Color not assignable to Status
}
