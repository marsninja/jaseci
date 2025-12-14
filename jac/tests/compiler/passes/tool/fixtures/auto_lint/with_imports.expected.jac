"""Test that globs are inserted after imports."""

import from os { path }

glob x = 5;
glob y = 10;

def main() {
    print(x + y);
}
