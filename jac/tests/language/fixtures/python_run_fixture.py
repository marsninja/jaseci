"""Simple Python test file for jac run command."""

import importlib.util
import os

# Import sibling module without requiring __init__.py
_spec = importlib.util.spec_from_file_location(
    "py_namedexpr", os.path.join(os.path.dirname(__file__), "py_namedexpr.py")
)
py_namedexpr = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(py_namedexpr)

print("Hello from Python!")
print("This is a test Python file.")


def main() -> int:
    """Main function to demonstrate execution."""
    result = 42
    print(f"Result: {result}")
    return result


if __name__ == "__main__":
    main()
    print("Python execution completed.")

py_namedexpr.walrus_example()
