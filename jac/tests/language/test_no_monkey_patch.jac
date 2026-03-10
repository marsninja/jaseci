"""Runtime enforcement tests for disallowing monkey patching on archetypes.

Archetypes (obj/node/edge/walker) only allow setting declared has-fields
and underscore-prefixed attributes. class archetypes remain unrestricted.

These tests use setattr/delattr to bypass compile-time checks (which
are tested separately in the compiler test suite).
"""

# --- Test archetypes ---
obj Foo {
    has x: int = 0,
        y: str = "hi";
}

node Bar {
    has val: str = "";
}

edge Link {
    has weight: float = 1.0;
}

walker Mover {
    has speed: int = 1;
}

obj Base {
    has x: int = 0;
}

obj Child(Base) {
    has y: int = 1;
}

# --- R1: obj rejects undeclared attr set ---
test "obj rejects undeclared attr set" {
    f = Foo();
    caught = False;
    try {
        setattr(f, "bogus", 42);
    } except AttributeError {
        caught = True;
    }
    assert caught , "obj should reject undeclared attribute assignment";
}

# --- R2: node rejects undeclared attr set ---
test "node rejects undeclared attr set" {
    b = Bar();
    caught = False;
    try {
        setattr(b, "nope", "hi");
    } except AttributeError {
        caught = True;
    }
    assert caught , "node should reject undeclared attribute assignment";
}

# --- R3: edge rejects undeclared attr set ---
test "edge rejects undeclared attr set" {
    e = Link();
    caught = False;
    try {
        setattr(e, "color", "red");
    } except AttributeError {
        caught = True;
    }
    assert caught , "edge should reject undeclared attribute assignment";
}

# --- R4: walker rejects undeclared attr set ---
test "walker rejects undeclared attr set" {
    m = Mover();
    caught = False;
    try {
        setattr(m, "direction", "north");
    } except AttributeError {
        caught = True;
    }
    assert caught , "walker should reject undeclared attribute assignment";
}

# --- R5: declared has fields work normally ---
test "obj allows declared field set" {
    f = Foo();
    f.x = 99;
    f.y = "bye";
    assert f.x == 99;
    assert f.y == "bye";
}

# --- R6: private/dunder attrs pass through ---
test "obj allows underscore-prefixed attrs" {
    f = Foo();
    setattr(f, "_internal", 1);
    setattr(f, "__custom", 2);
    assert getattr(f, "_internal") == 1;
}

# --- R7: deleting undeclared attr raises ---
test "obj rejects undeclared attr delete" {
    f = Foo();
    caught = False;
    try {
        delattr(f, "bogus");
    } except AttributeError {
        caught = True;
    }
    assert caught , "obj should reject undeclared attribute deletion";
}

# --- R8: deleting declared has field works ---
test "obj allows declared field delete" {
    f = Foo();
    caught = False;
    try {
        delattr(f, "x");
    } except AttributeError {
        caught = True;
    }
    assert not caught , "obj should allow deleting declared has fields";
}

# --- R9: class archetype allows dynamic attrs ---
test "class allows undeclared attr set" {
    class Flexible {
        has x: int = 0;
    }
    f = Flexible();
    setattr(f, "dynamic_attr", "anything");
    assert getattr(f, "dynamic_attr") == "anything";
}

# --- R10: inherited fields settable on child ---
test "child can set inherited field" {
    c = Child();
    c.x = 10;
    c.y = 20;
    assert c.x == 10;
    assert c.y == 20;
}

# --- R11: child also rejects undeclared attrs ---
test "child rejects undeclared attr" {
    c = Child();
    caught = False;
    try {
        setattr(c, "z", 99);
    } except AttributeError {
        caught = True;
    }
    assert caught , "child archetype should reject undeclared attributes";
}

# --- R12: setattr with declared field works, undeclared raises ---
test "setattr declared works" {
    f = Foo();
    setattr(f, "x", 42);
    assert f.x == 42;
}

test "setattr undeclared raises" {
    f = Foo();
    caught = False;
    try {
        setattr(f, "bogus", 1);
    } except AttributeError {
        caught = True;
    }
    assert caught , "setattr on undeclared attribute should raise";
}
