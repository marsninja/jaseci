"""Fixture for W2047: __eq__ defined without __hash__."""

obj Point {
    has x: int, y: int;

    def __eq__(other: object) -> bool {
        if isinstance(other, Point) {
            return self.x == other.x and self.y == other.y;
        }
        return False;
    }
    # Missing __hash__!  # <-- Warning W2047
}

obj GoodPoint {
    has x: int, y: int;

    def __eq__(other: object) -> bool {
        if isinstance(other, GoodPoint) {
            return self.x == other.x and self.y == other.y;
        }
        return False;
    }

    def __hash__ -> int {
        return hash((self.x, self.y));  # <-- Ok: both defined
    }
}
