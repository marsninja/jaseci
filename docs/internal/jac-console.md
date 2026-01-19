# Jac Console Usage Guide

A simple guide for using the Jac CLI console wrapper in your code.

## Quick Start

```jac
// In .jac files - import the global console instance
import from jaclang.cli.console { console }

// In .py files
from jaclang.cli.console import console
```

**Important**: Always use the global `console` instance, never create a new `JacConsole()`.

## Common Usage Patterns

### Error Messages

Use `console.error()` for all error messages:

```jac
// ❌ Don't do this
print(f"Error: {message}", file=sys.stderr);

// ✅ Do this instead
console.error(f"{message}");
console.error("File not found: config.toml");
```

### Success Messages

Use `console.success()` for successful operations:

```jac
console.success("Project created successfully!");
console.success(f"Plugin '{name}' enabled");
```

### Warnings

Use `console.warning()` for warnings and non-critical issues:

```jac
console.warning("Configuration file not found, using defaults");
console.warning(f"Hook failed: {error}");
```

### Informational Messages

Use `console.info()` for helpful information:

```jac
console.info("Building project...");
console.info("Run 'jac --help' for usage information");
```

### General Output

Use `console.print()` for general output with optional styling:

```jac
console.print("Available commands:");
console.print("Usage: jac plugins <action>", style="muted");
console.print(f"Version: {version}", style="bold cyan");
```

### Headers and Lists

```jac
// Print section headers
console.print_header("Configuration");

// Print bullet lists
let items = ["item1", "item2", "item3"];
console.print_list(items, title="Available options:");
```

### Progress Indicators

```jac
// For long-running operations
with console.status("Installing dependencies...") {
    // do work
}

// Or use spinner context
with console.spinner("Processing...") {
    // do work
}
```

## When to Use What

| Situation | Method | Example |
|-----------|--------|---------|
| Operation failed | `console.error()` | `console.error("Build failed")` |
| Operation succeeded | `console.success()` | `console.success("Tests passed")` |
| Something might be wrong | `console.warning()` | `console.warning("Deprecated feature")` |
| Helpful information | `console.info()` | `console.info("Starting server...")` |
| General text | `console.print()` | `console.print("Hello world")` |
| Muted/secondary text | `console.print(style="muted")` | `console.print("Hint: ...", style="muted")` |

## Available Styles

When using `console.print(style="...")`, you can use:

- `success` - Bold green
- `error` - Bold red
- `warning` - Bold yellow
- `info` - Bold cyan
- `url` - Underlined green
- `muted` - Dim white (for hints/secondary info)
- `highlight` - Bold cyan
- `bold cyan`, `bold green`, etc. - Rich library styles

## What NOT to Do

❌ **Don't create new console instances**

```python
# Wrong
from jaclang.cli.console import JacConsole
console = JacConsole()
```

❌ **Don't use plain print() for user-facing messages**

```jac
# Wrong
print("Error: something failed", file=sys.stderr);
```

❌ **Don't use console for code/data output**

```jac
# Wrong - this is machine-readable output
console.print(json_data);

# Right - plain print for data
print(json_data);
```

## Quick Reference

```jac
import from jaclang.cli.console { console }

// Styled messages
console.error("Something failed");
console.success("Operation complete");
console.warning("Be careful");
console.info("FYI: useful info");

// General output
console.print("Regular text");
console.print("Styled text", style="bold green");

// Structure
console.print_header("Section Title");
console.print_list(["a", "b", "c"]);

// Progress
with console.status("Working...") { /* ... */ }
```

## Environment Variables

The console automatically respects:

- `NO_COLOR` - Disables all colors
- `NO_EMOJI` - Disables all emojis
- `TERM=dumb` - Disables colors and emojis

You don't need to handle these yourself.

---

**Remember**: Use `console.error()` for errors, `console.success()` for success, `console.warning()` for warnings, and `console.info()` for information. It's that simple!
