"""Test that globs are inserted after imports."""

import from os { path }

with entry {
    x = 5;
    y = 10;
}

def main() {
    print(x + y);
}
