"""Bug #23: set is assignable to frozenset without error.

The type checker has a special case allowing set -> frozenset assignment,
treating it like int -> float coercion. However, in strict typing (mypy/pyright),
set and frozenset are distinct types — a set is mutable and a frozenset is
immutable. Assigning a set to a frozenset variable is unsound because the
caller may still mutate the set through the original reference.

Expected: `fs: frozenset = my_set` should produce a type error.
"""

def take_frozenset(fs: frozenset) -> None {
    # Expects immutable frozenset, but receives mutable set
    ;
}

with entry {
    my_set: set = {1, 2, 3};

    # Direct assignment: set -> frozenset should be an error
    fs: frozenset = my_set;  # <-- Should be Error (set not assignable to frozenset)

    # Via function call: same issue
    take_frozenset(my_set);  # <-- Should be Error (set not assignable to frozenset)
}
