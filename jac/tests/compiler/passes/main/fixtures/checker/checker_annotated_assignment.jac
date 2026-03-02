"""Test annotated assignments use the type annotation as the destination type.

Covers both Name targets (local vars) and AtomTrailer targets (attributes).
"""

obj Engine {
    has power: int;
}

obj Car {
    has engine: Engine;

    def init(eng: Engine) {
        # Attribute with type annotation: annotation type is destination
        self.engine: Engine | None = None;  # <-- OK
        self.engine = eng;
    }
}

with entry {
    # Local var annotations
    a: int | None = None;  # <-- OK
    b: Engine | None = Engine(power=100);  # <-- OK

    # Errors: incompatible with declared annotation
    c: int | None = "wrong";  # <-- Error
    d: Engine | None = "bad";  # <-- Error
}
