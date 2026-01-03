# Python Type Checking Integration (Pylance/Pyright)

When working with mixed Jac and Python codebases, you may want Python type checkers like **Pylance** (VSCode's default) or **Pyright** to understand types exported from your Jac modules. This guide explains how to enable automatic stub generation in the Jac Language Server.

## Overview

The Jac Language Server can automatically generate `.pyi` stub files from your compiled Jac modules. These stub files allow Python type checkers to:

- Provide autocompletion for Jac module imports in Python files
- Show type hints and documentation for Jac classes and functions
- Report type errors when using Jac code incorrectly from Python

## How It Works

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  mymodule.jac   │ ──> │   Jac LSP       │ ──> │ typings/        │
│                 │     │   compiles &    │     │ mymodule.pyi    │
│  class Foo {    │     │   generates     │     │                 │
│    has x: int;  │     │   stub          │     │ class Foo:      │
│  }              │     │                 │     │   x: int        │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                                        │
                                                        ▼
                                                ┌─────────────────┐
                                                │  Pylance reads  │
                                                │  stub file for  │
                                                │  type info      │
                                                └─────────────────┘
```

When you save a `.jac` file:

1. The Jac LSP type-checks and compiles the module
2. If stub generation is enabled, it creates a `.pyi` file in the configured output directory
3. Pylance/Pyright detects the new stub and updates its type information

## Setup

### Step 1: Configure VSCode Settings

Add the following to your `.vscode/settings.json`:

```json
{
  "jac.stubGeneration.enabled": true,
  "jac.stubGeneration.outputDir": "typings",
  "python.analysis.stubPath": "./typings",
  "python.analysis.extraPaths": ["./typings"]
}
```

| Setting | Description |
|---------|-------------|
| `jac.stubGeneration.enabled` | Enable/disable automatic stub generation |
| `jac.stubGeneration.outputDir` | Directory where `.pyi` files are written (relative to workspace root) |
| `python.analysis.stubPath` | Tell Pylance where to find type stubs |
| `python.analysis.extraPaths` | Additional paths for Pylance to search |

### Step 2: Configure Pyright (Optional)

If you use Pyright directly or want IDE-independent configuration, create a `pyrightconfig.json` in your project root:

```json
{
  "stubPath": "./typings",
  "extraPaths": ["./typings"],
  "pythonVersion": "3.11",
  "typeCheckingMode": "basic"
}
```

Or add to your `pyproject.toml`:

```toml
[tool.pyright]
stubPath = "./typings"
extraPaths = ["./typings"]
pythonVersion = "3.11"
typeCheckingMode = "basic"
```

### Step 3: Add to .gitignore

Since stubs are auto-generated, you typically don't want to commit them:

```gitignore
# Auto-generated Jac type stubs
typings/
```

## Directory Structure

With stub generation enabled, your project structure will look like:

```
my-project/
├── src/
│   ├── models/
│   │   └── user.jac          # Jac source
│   └── main.py               # Python code importing Jac
├── typings/                  # Auto-generated stubs
│   └── src/
│       └── models/
│           └── user.pyi      # Generated stub
├── .vscode/
│   └── settings.json
├── pyrightconfig.json
└── .gitignore
```

The stub directory structure mirrors your source directory structure.

## Example Usage

### Jac Module (`src/models/user.jac`)

```jac
"""User model for the application."""

obj User {
    has name: str,
        email: str,
        age: int = 0;

    can greet -> str {
        return f"Hello, I'm {self.name}!";
    }
}

def create_user(name: str, email: str) -> User {
    return User(name=name, email=email);
}
```

### Generated Stub (`typings/src/models/user.pyi`)

```python
# Auto-generated stub file for Pylance/Pyright
# Source: src/models/user.jac
# Do not edit manually - regenerated on each save

class User:
    name: str
    email: str
    age: int

    def greet(self) -> str: ...

def create_user(name: str, email: str) -> User: ...
```

### Python Code (`src/main.py`)

```python
# Pylance now understands these types!
from models.user import User, create_user

user = create_user("Alice", "alice@example.com")
print(user.greet())  # Pylance shows: (method) greet() -> str

# Type errors are caught:
user.age = "not a number"  # Pylance error: Cannot assign str to int
```

## Troubleshooting

### Stubs Not Being Generated

1. **Check that stub generation is enabled**: Verify `jac.stubGeneration.enabled` is `true` in your settings
2. **Check the Jac LSP output**: Open the Output panel (View > Output) and select "Jac Language Server" to see debug messages
3. **Verify the Jac LSP is running**: The Jac extension must be active and the language server started

### Pylance Not Finding Stubs

1. **Verify stub path configuration**: Ensure `python.analysis.stubPath` points to the correct directory
2. **Reload the window**: After adding stubs, you may need to reload VSCode (Cmd/Ctrl+Shift+P > "Reload Window")
3. **Check stub file exists**: Look in the `typings/` directory to confirm `.pyi` files are being created

### Type Information Seems Outdated

1. **Save the Jac file**: Stubs are regenerated on save, not on every keystroke
2. **Check for compilation errors**: If the Jac file has errors, stub generation may be skipped
3. **Restart Pylance**: Sometimes Pylance needs a restart to pick up new stubs

## Configuration Reference

### VSCode Settings

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `jac.stubGeneration.enabled` | boolean | `false` | Enable automatic `.pyi` stub generation |
| `jac.stubGeneration.outputDir` | string | `"typings"` | Output directory for generated stubs |

### Pyright/Pylance Settings

| Setting | Description |
|---------|-------------|
| `stubPath` | Path to directory containing custom type stubs |
| `extraPaths` | Additional search paths for imports |
| `pythonVersion` | Python version to use for type checking |
| `typeCheckingMode` | Level of type checking (`off`, `basic`, `standard`, `strict`) |

## Limitations

- **Runtime behavior unchanged**: Stubs only affect static type checking, not runtime behavior
- **Complex Jac features**: Some advanced Jac features may not translate perfectly to Python stubs
- **Impl files**: Changes to `.impl.jac` files also trigger stub regeneration for the main module

## See Also

- [Jac VS Code Extension](../tool_suite.md#jac-vs-code-extension) - The main Jac development extension
- [Pylance Documentation](https://marketplace.visualstudio.com/items?itemName=ms-python.vscode-pylance) - VSCode's Python language server
- [Pyright Documentation](https://github.com/microsoft/pyright) - The underlying type checker
