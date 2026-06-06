"""Native fixture: nested functions that capture enclosing-function locals.

Captures are lifted to hidden trailing parameters (by value) and injected
at each call site, mirroring the lambda capture mechanism. Recursion works
because the injection reloads the capture by name from the current scope —
inside the nested function the capture is its own parameter.
"""

def adder(y: int) -> int {
    def inner(x: int) -> int {
        return x + y;
    }
    return inner(5);
}

def multi_capture(a: int, b: int) -> int {
    def combine(x: int) -> int {
        return x * a + b;
    }
    return combine(10);
}

def nested_recursion(n: int) -> int {
    base: int = 100;
    def go(k: int) -> int {
        if k <= 0 {
            return base;
        }
        return go(k - 1) + 1;
    }
    return go(n);
}

def capture_list(scale: int) -> int {
    nums: list[int] = [1, 2, 3];
    def total -> int {
        acc: int = 0;
        for v in nums {
            acc += v * scale;
        }
        return acc;
    }
    return total();
}
