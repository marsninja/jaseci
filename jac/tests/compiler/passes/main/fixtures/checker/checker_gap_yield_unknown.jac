"""Gap #37: YieldExpr returns UnknownType — generator not distinguished from return type.

Functions containing yield should return Generator[T, ...], not T directly.
The checker treats `def count_up(n: int) -> int { yield i; }` as returning int,
but it actually returns a generator object. Assigning to int should error
because Generator[int] != int.

Expected errors:
  1. count_up(5) is generator, not int — assigned to int variable
  2. name_generator() is generator, not str — assigned to str variable
  3. chain_ints() is generator, not int — assigned to int variable
  4. Generator used in arithmetic as if scalar
  5. Generator passed where scalar parameter expected
"""

# Simple generator yielding ints
def count_up(n: int) -> int {
    i = 0;
    while i < n {
        yield i;
        i += 1;
    }
}

# Generator yielding strings
def name_generator -> str {
    yield "alice";
    yield "bob";
    yield "charlie";
}

# Generator with yield from
def chain_ints -> int {
    yield from [1, 2, 3];
    yield from range(4, 7);
}

def takes_int(x: int) -> int {
    return x * 2;
}

with entry {
    # Case 1: Generator assigned to declared return type
    # count_up yields ints, so it returns Generator[int], not int
    # But checker thinks it returns int, so no error is raised
    bad1: int = count_up(5);       # Error: Generator[int] != int

    # Case 2: Generator assigned to declared return type
    bad2: str = name_generator();  # Error: Generator[str] != str

    # Case 3: Generator assigned to declared return type
    bad3: int = chain_ints();      # Error: Generator[int] != int

    # Case 4: Generator used in arithmetic (should fail — generator, not int)
    bad4 = count_up(3) + 10;       # Error: Generator + int invalid

    # Case 5: Generator passed where scalar expected
    bad5 = takes_int(count_up(3)); # Error: Generator[int] -> int param
}
