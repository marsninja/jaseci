"""Fixture for W2041: Method overrides parent but changes signature incompatibly."""

obj Base {
    def process(data: str) -> int {
        return len(data);
    }
}

obj GoodChild(Base) {
    def process(data: str) -> int {  # <-- Ok: same signature
        return len(data) * 2;
    }
}

obj BadChild(Base) {
    def process(data: int, extra: str) -> str {  # <-- Warning W2041: incompatible param count
        return str(data);
    }
}
