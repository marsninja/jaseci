"""Fixture for W3026: Negated comparison can be simplified."""

with entry {
    x = 5;
    y = not (x == 3);  # <-- Warning W3026: use x != 3 instead
}
