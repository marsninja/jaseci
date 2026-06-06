"""Native fixture for isinstance() and type().

isinstance is inheritance-aware: a base-typed variable holding a subclass
instance matches both the subclass and the base via a runtime type-tag
check. type() returns the value's type name as a string.
"""

obj Animal {
    has legs: int;
}

obj Dog(Animal) {
    has name_len: int;
}

def kind_of(a: Animal) -> int {
    if isinstance(a, Dog) {
        return 2;
    }
    if isinstance(a, Animal) {
        return 1;
    }
    return 0;
}

def is_int_val(x: int) -> bool {
    return isinstance(x, int);
}

def is_str_val(s: str) -> bool {
    return isinstance(s, str);
}

def is_int_a_str(x: int) -> bool {
    return isinstance(x, str);
}

def drive_isinstance -> int {
    d = Dog(legs=4, name_len=3);
    plain = Animal(legs=2);
    # kind_of(d)=2 (Dog), kind_of(plain)=1 (Animal) → 21
    return kind_of(d) * 10 + kind_of(plain);
}

def type_name_of_int -> str {
    x: int = 5;
    return type(x);
}

def type_name_of_obj -> str {
    p = Animal(legs=4);
    return type(p);
}
