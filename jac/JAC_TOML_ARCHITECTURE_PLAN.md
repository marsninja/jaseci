# Jac Project Configuration Architecture Redesign

## Overview

This document outlines a comprehensive plan to introduce `jac.toml` as the central project configuration file for Jac projects, replacing the current `settings.py` approach and introducing proper virtual environment management via `.jac_env/`.

## Goals

1. **Unified Configuration**: Single `jac.toml` file for all project settings (superseding `pyproject.toml` patterns)
2. **Environment Isolation**: Automatic virtual environment creation in `.jac_env/`
3. **Dependency Management**: First-class Jac and Python dependency declaration and installation
4. **Project Initialization**: `jac init` command for project scaffolding
5. **Environment Detection**: All `jac` commands auto-detect and use project environment
6. **Backward Compatibility**: Graceful migration path from current settings system

---

## Current Architecture Analysis

### Current Settings System (`jaclang/pycore/settings.py`)

The current system uses a dataclass-based approach with three-tier loading:

```
~/.jaclang/config.ini < Environment Variables < CLI Arguments
```

**Problems with current approach:**

- Global user-level config only (`~/.jaclang/config.ini`)
- No project-level configuration support
- No dependency management
- No virtual environment isolation
- Settings scattered across env vars, config files, CLI args
- No standardized project structure

### Current Configuration Options

| Category | Setting | Type | Default |
|----------|---------|------|---------|
| Debug | `filter_sym_builtins` | bool | true |
| Debug | `ast_symbol_info_detailed` | bool | false |
| Debug | `pass_timer` | bool | false |
| Debug | `print_py_raised_ast` | bool | false |
| Debug | `show_internal_stack_errs` | bool | false |
| Compiler | `ignore_test_annex` | bool | false |
| Compiler | `pyfile_raise` | bool | false |
| Compiler | `pyfile_raise_full` | bool | false |
| Formatter | `max_line_length` | int | 88 |
| LSP | `lsp_debug` | bool | false |
| Alerts | `all_warnings` | bool | false |

---

## Proposed `jac.toml` Specification

### Complete Schema

```toml
# jac.toml - Jac Project Configuration

[project]
name = "my-jac-project"
version = "0.1.0"
description = "A Jac project"
authors = ["Name <email@example.com>"]
license = "MIT"
readme = "README.md"
jac-version = ">=0.9.3"           # Required Jac version constraint
entry-point = "main.jac"          # Default file for `jac run`

[project.urls]
homepage = "https://example.com"
repository = "https://github.com/user/repo"
documentation = "https://docs.example.com"

# Dependencies section - supports both Jac plugins and Python packages
[dependencies]
# Jac plugins (from PyPI or git)
jac-byllm = ">=0.4.8"
jac-client = ">=0.2.3"

# Python dependencies
requests = ">=2.28.0"
numpy = ">=1.24.0"

[dependencies.git]
# Git-based dependencies
my-jac-plugin = { git = "https://github.com/user/plugin.git", branch = "main" }

[dev-dependencies]
pytest = ">=8.2.1"
pytest-cov = ">=5.0.0"

# All settings from current settings.py + expansions
[settings]
# Compiler settings
max_line_length = 88
ignore_test_annex = false
pyfile_raise = false
pyfile_raise_full = false

# Debug settings
filter_sym_builtins = true
ast_symbol_info_detailed = false
pass_timer = false
print_py_raised_ast = false
show_internal_stack_errs = false

# LSP settings
lsp_debug = false

# Alert settings
all_warnings = false

# NEW: Cache settings
cache_enabled = true
cache_dir = ".jac_cache"

# NEW: Output settings
output_dir = "dist"

[settings.paths]
# Module search paths (replaces JACPATH env var)
include = ["src", "lib", "vendor"]

[environment]
# Virtual environment configuration
python_version = "3.11"           # Minimum Python version
env_dir = ".jac_env"              # Environment directory name
auto_activate = true              # Auto-activate on jac commands

[build]
# Build configuration
target = "python"                 # python | javascript
optimize = false
sourcemaps = true

[build.python]
# Python-specific build options
bytecode = true
type_stubs = true

[build.javascript]
# JavaScript-specific build options
module_format = "esm"             # esm | cjs
minify = false

[test]
# Test configuration
directory = "tests"
pattern = "test_*.jac"
verbose = false
fail_fast = false
max_failures = 0                  # 0 = unlimited

[serve]
# Server configuration
port = 8000
host = "0.0.0.0"
reload = true                     # Hot reload on file changes
cors_origins = ["*"]

[format]
# Formatter configuration
max_line_length = 88
indent_size = 4
use_tabs = false
auto_lint = false                 # Apply linting during format

[plugins]
# Plugin configuration
enabled = ["byllm", "client"]
disabled = []

[plugins.byllm]
# Plugin-specific configuration
default_model = "gpt-4"
temperature = 0.7

[scripts]
# Custom scripts (like npm scripts)
dev = "jac run main.jac --watch"
build = "jac build main.jac"
test = "jac test tests/"
lint = "jac format . --check"
```

---

## New CLI Commands

### `jac init`

Initialize a new Jac project with environment setup.

```bash
# Interactive initialization
jac init

# Quick initialization with defaults
jac init --quick

# Initialize with specific template
jac init --template web-app

# Initialize in existing directory
jac init --name my-project
```

**Behavior:**

1. Create `jac.toml` with project configuration
2. Create `.jac_env/` virtual environment
3. Install `jaclang` in the environment
4. Create basic project structure
5. Add `.jac_env/` to `.gitignore`

**Generated structure:**

```
my-project/
├── jac.toml
├── .jac_env/              # Virtual environment
├── .gitignore
├── src/
│   └── main.jac
└── README.md
```

### `jac install`

Install dependencies from `jac.toml`.

```bash
# Install all dependencies
jac install

# Install specific package
jac install jac-byllm

# Install with version constraint
jac install "numpy>=1.24.0"

# Install dev dependencies
jac install --dev

# Install from git
jac install --git https://github.com/user/plugin.git
```

**Behavior:**

1. Read `jac.toml` dependencies
2. Create/activate `.jac_env/` if not exists
3. Install packages using pip in the virtual environment
4. Update lock file (`jac.lock`)

### `jac env`

Manage the project virtual environment.

```bash
# Show environment info
jac env info

# Activate environment (prints activation command)
jac env activate

# Recreate environment
jac env recreate

# Remove environment
jac env remove

# List installed packages
jac env list
```

### `jac add` / `jac remove`

Add or remove dependencies.

```bash
# Add a dependency
jac add requests

# Add dev dependency
jac add pytest --dev

# Add with version
jac add "numpy>=1.24"

# Remove a dependency
jac remove requests
```

### `jac script`

Run custom scripts defined in `jac.toml`.

```bash
# Run a script
jac script dev
jac script build

# List available scripts
jac script --list
```

### Modified Existing Commands

All existing commands (`run`, `build`, `test`, `format`, `serve`, etc.) will:

1. **Auto-detect** `jac.toml` in current or parent directories
2. **Auto-activate** `.jac_env/` if present
3. **Load settings** from `jac.toml` (overridable by CLI args)
4. **Use project paths** for module resolution

---

## Implementation Architecture

### New Module Structure

```
jaclang/
├── cli/
│   ├── cli.jac              # Updated with new commands
│   ├── cmdreg.jac           # Existing command registry
│   └── commands/            # NEW: Command implementations
│       ├── init.py
│       ├── install.py
│       ├── env.py
│       └── script.py
├── project/                 # NEW: Project management module
│   ├── __init__.py
│   ├── config.py            # JacConfig class (replaces settings.py)
│   ├── toml_parser.py       # jac.toml parser
│   ├── environment.py       # Virtual environment management
│   ├── dependencies.py      # Dependency resolution
│   ├── lockfile.py          # jac.lock management
│   └── discovery.py         # Project root discovery
├── pycore/
│   ├── settings.py          # DEPRECATED - redirect to project/config.py
│   └── ...
└── ...
```

### Core Classes

#### `JacConfig` (replaces `Settings`)

```python
# jaclang/project/config.py

from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional, Dict, Any, List
import tomllib

@dataclass
class ProjectConfig:
    """Project metadata from [project] section."""
    name: str = ""
    version: str = "0.1.0"
    description: str = ""
    authors: List[str] = field(default_factory=list)
    license: str = ""
    jac_version: str = ""
    entry_point: str = "main.jac"

@dataclass
class SettingsConfig:
    """Settings from [settings] section (replaces old Settings class)."""
    # Compiler
    max_line_length: int = 88
    ignore_test_annex: bool = False
    pyfile_raise: bool = False
    pyfile_raise_full: bool = False

    # Debug
    filter_sym_builtins: bool = True
    ast_symbol_info_detailed: bool = False
    pass_timer: bool = False
    print_py_raised_ast: bool = False
    show_internal_stack_errs: bool = False

    # LSP
    lsp_debug: bool = False

    # Alerts
    all_warnings: bool = False

    # New settings
    cache_enabled: bool = True
    cache_dir: str = ".jac_cache"
    output_dir: str = "dist"

@dataclass
class EnvironmentConfig:
    """Environment settings from [environment] section."""
    python_version: str = "3.11"
    env_dir: str = ".jac_env"
    auto_activate: bool = True

@dataclass
class JacConfig:
    """Main configuration class for Jac projects."""

    project: ProjectConfig = field(default_factory=ProjectConfig)
    settings: SettingsConfig = field(default_factory=SettingsConfig)
    environment: EnvironmentConfig = field(default_factory=EnvironmentConfig)
    dependencies: Dict[str, str] = field(default_factory=dict)
    dev_dependencies: Dict[str, str] = field(default_factory=dict)
    scripts: Dict[str, str] = field(default_factory=dict)
    plugins: Dict[str, Any] = field(default_factory=dict)

    # Runtime state
    project_root: Optional[Path] = None
    toml_path: Optional[Path] = None
    env_path: Optional[Path] = None

    @classmethod
    def discover(cls, start_path: Path = None) -> "JacConfig":
        """Discover and load jac.toml from current or parent directories."""
        ...

    @classmethod
    def load(cls, toml_path: Path) -> "JacConfig":
        """Load configuration from a specific jac.toml file."""
        ...

    def apply_env_overrides(self) -> None:
        """Apply environment variable overrides (JAC_*, JACLANG_*)."""
        ...

    def apply_cli_overrides(self, args: dict) -> None:
        """Apply command-line argument overrides."""
        ...

    def ensure_environment(self) -> Path:
        """Ensure virtual environment exists, create if needed."""
        ...

    def get_python_executable(self) -> Path:
        """Get the Python executable from .jac_env."""
        ...

# Global singleton (lazy initialization)
_config: Optional[JacConfig] = None

def get_config() -> JacConfig:
    """Get or create the global configuration."""
    global _config
    if _config is None:
        _config = JacConfig.discover()
    return _config
```

#### `JacEnvironment`

```python
# jaclang/project/environment.py

from pathlib import Path
import venv
import subprocess
import sys

class JacEnvironment:
    """Manages the .jac_env virtual environment."""

    def __init__(self, project_root: Path, env_dir: str = ".jac_env"):
        self.project_root = project_root
        self.env_path = project_root / env_dir

    @property
    def exists(self) -> bool:
        """Check if environment exists."""
        return (self.env_path / "bin" / "python").exists()

    @property
    def python(self) -> Path:
        """Get Python executable path."""
        if sys.platform == "win32":
            return self.env_path / "Scripts" / "python.exe"
        return self.env_path / "bin" / "python"

    @property
    def pip(self) -> Path:
        """Get pip executable path."""
        if sys.platform == "win32":
            return self.env_path / "Scripts" / "pip.exe"
        return self.env_path / "bin" / "pip"

    def create(self, python_version: str = None) -> None:
        """Create the virtual environment."""
        venv.create(self.env_path, with_pip=True)
        # Install jaclang in the environment
        self.install_package("jaclang")

    def install_package(self, package: str, dev: bool = False) -> None:
        """Install a package in the environment."""
        subprocess.run([str(self.pip), "install", package], check=True)

    def install_requirements(self, requirements: dict) -> None:
        """Install all requirements from dependencies dict."""
        for package, version in requirements.items():
            spec = f"{package}{version}" if version else package
            self.install_package(spec)

    def remove(self) -> None:
        """Remove the virtual environment."""
        import shutil
        if self.exists:
            shutil.rmtree(self.env_path)

    def activate_context(self):
        """Context manager for running code in the environment."""
        ...
```

#### Project Discovery

```python
# jaclang/project/discovery.py

from pathlib import Path
from typing import Optional, Tuple

def find_project_root(start: Path = None) -> Optional[Tuple[Path, Path]]:
    """
    Find the project root by looking for jac.toml.

    Returns:
        Tuple of (project_root, toml_path) or None if not found.
    """
    if start is None:
        start = Path.cwd()

    current = start.resolve()

    while current != current.parent:
        toml_path = current / "jac.toml"
        if toml_path.exists():
            return (current, toml_path)
        current = current.parent

    return None

def is_in_project() -> bool:
    """Check if currently in a Jac project."""
    return find_project_root() is not None
```

---

## Migration Strategy

### Phase 1: Add New Infrastructure (Non-Breaking)

1. Create `jaclang/project/` module
2. Implement `JacConfig` class
3. Implement `JacEnvironment` class
4. Add `jac init` command
5. Add `jac install` command
6. Add `jac env` command

### Phase 2: Integrate with Existing Commands

1. Modify `start_cli()` to auto-discover projects
2. Update `run`, `build`, `test`, etc. to use `JacConfig`
3. Add project settings loading before command execution
4. Keep `settings.py` working but deprecated

### Phase 3: Deprecate `settings.py`

1. Add deprecation warnings when `~/.jaclang/config.ini` is used
2. Provide migration guide
3. Eventually remove `settings.py`

### Backward Compatibility

```python
# jaclang/pycore/settings.py (deprecated wrapper)

import warnings
from jaclang.project.config import get_config, SettingsConfig

class Settings:
    """DEPRECATED: Use jaclang.project.config.JacConfig instead."""

    def __init__(self):
        warnings.warn(
            "Settings class is deprecated. Use JacConfig from "
            "jaclang.project.config instead.",
            DeprecationWarning,
            stacklevel=2
        )
        self._config = get_config()

    def __getattr__(self, name: str):
        return getattr(self._config.settings, name)

    def __setattr__(self, name: str, value):
        if name.startswith('_'):
            super().__setattr__(name, value)
        else:
            setattr(self._config.settings, name, value)

# Keep for backward compatibility
settings = Settings()
```

---

## Lock File Format (`jac.lock`)

```toml
# jac.lock - Auto-generated, do not edit manually

[metadata]
generated_at = "2024-01-15T10:30:00Z"
jac_version = "0.9.3"
python_version = "3.11.5"
platform = "darwin"

[[package]]
name = "jac-byllm"
version = "0.4.8"
hash = "sha256:abc123..."
dependencies = ["jaclang>=0.9.3", "litellm", "loguru", "pillow"]

[[package]]
name = "requests"
version = "2.31.0"
hash = "sha256:def456..."
dependencies = ["charset-normalizer", "idna", "urllib3", "certifi"]
```

---

## Configuration Loading Precedence

The new system maintains the three-tier approach but adds project-level configuration:

```
1. jac.toml (project-level)           [Lowest priority]
2. ~/.jaclang/config.ini (user-level) [Deprecated, for backward compat]
3. Environment variables (JAC_*, JACLANG_*)
4. Command-line arguments             [Highest priority]
```

---

## Implementation Tasks

### Task 1: Core Infrastructure

- [ ] Create `jaclang/project/` module structure
- [ ] Implement TOML parser with schema validation
- [ ] Implement `JacConfig` dataclass
- [ ] Implement configuration loading/merging logic
- [ ] Add project root discovery
- [ ] Write unit tests

### Task 2: Virtual Environment Management

- [ ] Implement `JacEnvironment` class
- [ ] Add environment creation logic
- [ ] Add package installation via pip
- [ ] Implement environment activation context
- [ ] Handle cross-platform paths (Windows/Unix)
- [ ] Write unit tests

### Task 3: New CLI Commands

- [ ] Implement `jac init` command
  - [ ] Interactive mode
  - [ ] Quick mode with defaults
  - [ ] Template support
- [ ] Implement `jac install` command
  - [ ] Dependency resolution
  - [ ] Lock file generation
- [ ] Implement `jac env` command
  - [ ] info, activate, recreate, remove subcommands
- [ ] Implement `jac add` / `jac remove` commands
- [ ] Implement `jac script` command
- [ ] Update command registry for new commands

### Task 4: Integrate with Existing Commands

- [ ] Modify `start_cli()` for project auto-detection
- [ ] Update `run` command for project context
- [ ] Update `build` command for project settings
- [ ] Update `test` command for project test config
- [ ] Update `format` command for project format settings
- [ ] Update `serve` command for project server settings
- [ ] Update `lsp` command for project paths

### Task 5: Deprecation and Migration

- [ ] Create backward-compatible `settings.py` wrapper
- [ ] Add deprecation warnings
- [ ] Write migration documentation
- [ ] Create migration script for existing projects

### Task 6: Documentation and Testing

- [ ] Write user documentation for `jac.toml`
- [ ] Document all new CLI commands
- [ ] Add integration tests
- [ ] Add example projects
- [ ] Update README

---

## Example Workflows

### New Project

```bash
$ mkdir my-project && cd my-project
$ jac init
Creating new Jac project...
? Project name: my-project
? Version: 0.1.0
? Description: My awesome Jac project
? Author: John Doe <john@example.com>
? Entry point: main.jac

Creating jac.toml...
Creating .jac_env virtual environment...
Installing jaclang...
Creating project structure...

 Project initialized successfully!

Next steps:
  cd my-project
  jac run             # Run main.jac
  jac test            # Run tests
  jac install <pkg>   # Add dependencies
```

### Existing Project Migration

```bash
$ cd existing-project
$ jac init --migrate

Detected existing Jac files...
? Create jac.toml from detected settings? Yes
? Create virtual environment? Yes

Migrating settings from ~/.jaclang/config.ini...
Creating jac.toml...
Creating .jac_env...

 Migration complete!

Note: ~/.jaclang/config.ini is now deprecated.
      All settings have been moved to jac.toml.
```

### Adding Dependencies

```bash
$ jac add jac-byllm numpy "requests>=2.28"
Installing dependencies...
 jac-byllm>=0.4.8 installed
 numpy>=1.24.0 installed
 requests>=2.28.0 installed

Updated jac.toml and jac.lock
```

### Running in Project Context

```bash
$ jac run
# Automatically:
# 1. Finds jac.toml in current/parent dir
# 2. Activates .jac_env if exists
# 3. Loads settings from [settings]
# 4. Runs entry-point (main.jac)

$ jac run other.jac --port 9000
# Settings from jac.toml, CLI override for port
```

---

## Files to Create/Modify

### New Files

| File | Description |
|------|-------------|
| `jaclang/project/__init__.py` | Module exports |
| `jaclang/project/config.py` | `JacConfig` class |
| `jaclang/project/toml_parser.py` | TOML parsing and validation |
| `jaclang/project/environment.py` | `JacEnvironment` class |
| `jaclang/project/dependencies.py` | Dependency resolution |
| `jaclang/project/lockfile.py` | Lock file management |
| `jaclang/project/discovery.py` | Project root discovery |
| `jaclang/project/templates/` | Project templates |
| `jaclang/cli/commands/init.py` | `jac init` implementation |
| `jaclang/cli/commands/install.py` | `jac install` implementation |
| `jaclang/cli/commands/env.py` | `jac env` implementation |
| `jaclang/cli/commands/script.py` | `jac script` implementation |

### Modified Files

| File | Changes |
|------|---------|
| `jaclang/cli/cli.jac` | Add new commands, project detection |
| `jaclang/pycore/settings.py` | Deprecate, wrap `JacConfig` |
| `jaclang/__init__.py` | Initialize project config |
| `pyproject.toml` | Add tomllib dependency (stdlib in 3.11+) |

### Removed Files (Phase 3)

| File | Replacement |
|------|-------------|
| `jaclang/pycore/settings.py` | `jaclang/project/config.py` |

---

## Open Questions

1. **Workspace Support**: Should we support multi-project workspaces (like Cargo workspaces)?

2. **Lock File Strategy**: Should `jac.lock` be committed to git? (Recommended: yes, for reproducibility)

3. **Plugin Configuration**: How deeply should plugins be configurable via `jac.toml`?

4. **Remote Registries**: Should we have a Jac-specific package registry, or rely entirely on PyPI?

5. **Shell Integration**: Should `jac env activate` modify the current shell, or just print instructions?

---

## Success Criteria

1. New projects can be created with `jac init`
2. Dependencies managed via `jac.toml` and `jac install`
3. Virtual environment automatically created and managed
4. All existing `jac` commands work with project context
5. Settings from `jac.toml` properly loaded and applied
6. Backward compatibility with existing projects
7. Clear migration path documented
8. Comprehensive test coverage
