"""Visit collection element-type validation.

`visit` accepts a node, a list/tuple/set/frozenset of nodes, or any/unknown.
For parameterized collections, the element type must be a node type.
Unparameterized collections are accepted (matches connect operand behavior).
"""

node Place { has name: str; }
node City { has population: int; }

obj NotANode { has v: int; }

walker Bad {
    can on_entry with entry {
        # Element type is a non-node literal — should error.
        visit ["a", "b"];                         # E1094
        visit [1, 2, 3];                          # E1094
        visit (NotANode(1), NotANode(2));         # E1094

        # Typed local of non-node element — should error.
        xs: list[str] = ["a"];
        visit xs;                                 # E1094

        ys: set[int] = {1, 2};
        visit ys;                                 # E1094

        zs: frozenset[str] = frozenset(["a"]);
        visit zs;                                 # E1094

        nas: list[NotANode] = [NotANode(1)];
        visit nas;                                # E1094
    }
}

walker Good {
    can on_entry with entry {
        # Single node — valid.
        p: Place = Place(name="p");
        visit p;

        # Parameterized list/tuple/set of nodes — valid.
        ps: list[Place] = [Place(name="a"), Place(name="b")];
        visit ps;

        cs: tuple[City, Place] = (City(population=1), Place(name="x"));
        visit cs;

        # Mixed but all nodes — valid.
        visit [Place(name="a"), City(population=1)];
    }
}
