"""Test fixture for context manager type checking."""

obj FileHandle {
    has path: str;

    def __enter__()  -> str {
        return self.path;
    }

    def __exit__(exc_type: type, exc_val: object, exc_tb: object)  -> bool {
        return False;
    }
}

with entry {
    # Context manager with alias
    with FileHandle(path="/tmp/test.txt") as f {
        name: str = f;  # <-- Ok: f is str (from __enter__)
        num: int = f;  # <-- Error: str not assignable to int
    }

    # Using context manager without alias
    with FileHandle(path="/tmp/test2.txt") {
        print("No alias");
    }
}
