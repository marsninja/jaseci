# Installation

Get Jac installed and ready to use in under 2 minutes.

---

## Requirements

- **Python 3.10+** (check with `python --version`)
- **pip** (comes with Python)

---

## Quick Install

```bash
pip install jaclang[all]
```

This installs:

- `jaclang` - The Jac language and compiler
- `byllm` - AI/LLM integration
- `jac-client` - Full-stack web development
- `jac-scale` - Production deployment

Verify the installation:

```bash
jac --version
```

---

## Installation Options

### Minimal Install (Language Only)

If you only need the core language:

```bash
pip install jaclang
```

### Individual Plugins

Install plugins as needed:

```bash
# AI/LLM integration
pip install byllm

# Full-stack web development
pip install jac-client

# Production deployment & scaling
pip install jac-scale

# Enhanced console output
pip install jac-super
```

### Virtual Environment (Recommended)

```bash
# Create environment
python -m venv jac-env

# Activate it
source jac-env/bin/activate   # Linux/Mac
jac-env\Scripts\activate      # Windows

# Install Jac
pip install jaclang[all]
```

---

## IDE Setup

### VS Code (Recommended)

1. Open Extensions (`Ctrl+Shift+X` / `Cmd+Shift+X`)
2. Search for "Jac"
3. Install **Jac Language Support** by Jaseci Labs

Features: Syntax highlighting, autocomplete, error detection, graph visualization.

### Cursor

1. Download the latest `.vsix` from [GitHub releases](https://github.com/Jaseci-Labs/jac-vscode/releases/latest)
2. Press `Ctrl+Shift+P` / `Cmd+Shift+P`
3. Select "Extensions: Install from VSIX"
4. Choose the downloaded file

---

## Verify Installation

Create a test file `test.jac`:

```jac
with entry {
    print("Jac is working!");
}
```

Run it:

```bash
jac run test.jac
```

Expected output:

```
Jac is working!
```

---

## Troubleshooting

### "command not found: jac"

Your Python scripts directory isn't in PATH. Try:

```bash
python -m jaclang.cli run test.jac
```

Or add Python scripts to PATH:

```bash
# Find the path
python -c "import site; print(site.USER_BASE + '/bin')"

# Add to ~/.bashrc or ~/.zshrc
export PATH="$PATH:$(python -c 'import site; print(site.USER_BASE)')/bin"
```

### Permission Errors

Use `--user` flag:

```bash
pip install --user jaclang[all]
```

### Conflicting Packages

Use a virtual environment (see above) to isolate Jac from other Python projects.

---

## For Contributors

To work on Jac itself:

```bash
git clone --recurse --depth 1 https://github.com/Jaseci-Labs/jaseci
cd jaseci
pip install -e ./jac[dev]
```

See the [Contributing Guide](../community/contributing.md) for development setup.

---

## Next Steps

- [Hello World](hello-world.md) - Write your first program
- [Your First App](first-app.md) - Build a complete application
