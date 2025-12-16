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

### Phase 3: Remove `settings.py`

1. Delete `jaclang/pycore/settings.py` entirely
2. Delete `~/.jaclang/config.ini` support
3. Update all internal references to use `JacConfig`

**Note:** No backward compatibility will be maintained. The old `settings.py` and `~/.jaclang/config.ini` will be completely removed in favor of `jac.toml`.

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

### Task 5: Remove Legacy Settings

- [ ] Delete `jaclang/pycore/settings.py`
- [ ] Remove `~/.jaclang/config.ini` support
- [ ] Update all internal imports from `settings` to `JacConfig`
- [ ] Write migration documentation for users

### Task 6: Plugin Configuration System

- [ ] Add `get_config_schema`, `on_config_loaded`, `validate_config` hooks to `JacRuntimeInterface`
- [ ] Create `jaclang/project/plugin_config.py` with `PluginConfigManager`
- [ ] Integrate plugin config loading into `JacConfig.load()`
- [ ] Add `jac config` CLI command with subcommands
- [ ] Update existing plugins (jac-byllm, jac-client, jac-scale) with config schemas
- [ ] Write plugin author documentation

### Task 7: Documentation and Testing

- [ ] Write user documentation for `jac.toml`
- [ ] Document all new CLI commands
- [ ] Document plugin configuration interface for plugin authors
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

## Plugin Configuration Interface

This section describes how plugins can register their own configuration options that will be loaded from `jac.toml` and made available through the configuration system.

### Current Plugin Architecture

The current plugin system in `runtime.py` uses `pluggy` for hook-based extensibility:

```python
plugin_manager = pluggy.PluginManager("jac")
hookspec = pluggy.HookspecMarker("jac")
hookimpl = pluggy.HookimplMarker("jac")
```

Plugins implement hooks defined in `JacRuntimeInterface` and are loaded via setuptools entry points:

```python
# In jaclang/__init__.py
plugin_manager.register(JacRuntimeImpl)
plugin_manager.load_setuptools_entrypoints("jac")
```

### New Plugin Configuration Hook

Add a new hook specification for plugins to declare their configuration schema:

```python
# jaclang/pycore/runtime.py - Add to JacRuntimeInterface

class JacPluginConfig:
    """Plugin configuration hooks."""

    @staticmethod
    @hookspec
    def get_config_schema() -> dict[str, Any] | None:
        """Return the plugin's configuration schema.

        Returns a dictionary describing configuration options:
        {
            "section_name": "byllm",  # Section in jac.toml [plugins.byllm]
            "options": {
                "option_name": {
                    "type": "str" | "int" | "bool" | "list" | "dict",
                    "default": <default_value>,
                    "description": "Human readable description",
                    "required": False,
                    "choices": ["opt1", "opt2"],  # Optional: valid values
                    "env_var": "JAC_BYLLM_OPTION",  # Optional: env var override
                }
            }
        }
        """
        return None

    @staticmethod
    @hookspec
    def on_config_loaded(config: dict[str, Any]) -> None:
        """Called when plugin configuration is loaded.

        Args:
            config: The plugin's configuration section from jac.toml
        """
        pass

    @staticmethod
    @hookspec
    def validate_config(config: dict[str, Any]) -> list[str]:
        """Validate plugin configuration.

        Args:
            config: The plugin's configuration section

        Returns:
            List of validation error messages (empty if valid)
        """
        return []
```

### Plugin Configuration Registration

Plugins register their configuration schema at load time:

```python
# Example: jac-byllm/byllm/plugin.py

from jaclang.pycore.runtime import hookimpl
from typing import Any

class ByllmPlugin:
    """LLM integration plugin."""

    @staticmethod
    @hookimpl
    def get_config_schema() -> dict[str, Any]:
        return {
            "section_name": "byllm",
            "options": {
                "default_model": {
                    "type": "str",
                    "default": "gpt-4",
                    "description": "Default LLM model to use",
                    "env_var": "JAC_BYLLM_MODEL",
                },
                "temperature": {
                    "type": "float",
                    "default": 0.7,
                    "description": "Default temperature for LLM calls",
                    "env_var": "JAC_BYLLM_TEMPERATURE",
                },
                "max_tokens": {
                    "type": "int",
                    "default": 4096,
                    "description": "Maximum tokens per response",
                },
                "api_key_env": {
                    "type": "str",
                    "default": "OPENAI_API_KEY",
                    "description": "Environment variable containing API key",
                },
                "retry_attempts": {
                    "type": "int",
                    "default": 3,
                    "description": "Number of retry attempts on failure",
                },
                "cache_responses": {
                    "type": "bool",
                    "default": True,
                    "description": "Cache LLM responses for identical prompts",
                },
            }
        }

    @staticmethod
    @hookimpl
    def on_config_loaded(config: dict[str, Any]) -> None:
        """Initialize plugin with loaded configuration."""
        ByllmPlugin._config = config
        # Initialize LLM client with config values
        ByllmPlugin._init_client()

    @staticmethod
    @hookimpl
    def validate_config(config: dict[str, Any]) -> list[str]:
        """Validate byllm configuration."""
        errors = []
        if config.get("temperature", 0.7) < 0 or config.get("temperature", 0.7) > 2:
            errors.append("temperature must be between 0 and 2")
        if config.get("max_tokens", 4096) < 1:
            errors.append("max_tokens must be positive")
        return errors
```

### Configuration in jac.toml

Plugin configurations appear under `[plugins.<section_name>]`:

```toml
# jac.toml

[plugins]
# List of enabled/disabled plugins
enabled = ["byllm", "client", "scale"]
disabled = []

[plugins.byllm]
default_model = "gpt-4-turbo"
temperature = 0.5
max_tokens = 8192
cache_responses = true
retry_attempts = 5

[plugins.client]
bundle_output_dir = "dist/client"
minify = true
source_maps = false

[plugins.scale]
kubernetes_namespace = "jac-prod"
auto_scale = true
min_replicas = 2
max_replicas = 10
```

### Plugin Configuration Loading Flow

```python
# jaclang/project/plugin_config.py

from typing import Any, Dict, List
from jaclang.pycore.runtime import plugin_manager

class PluginConfigManager:
    """Manages plugin configuration loading and validation."""

    def __init__(self):
        self._schemas: Dict[str, dict] = {}
        self._configs: Dict[str, dict] = {}

    def collect_schemas(self) -> None:
        """Collect configuration schemas from all registered plugins."""
        results = plugin_manager.hook.get_config_schema()
        for schema in results:
            if schema:
                section = schema.get("section_name")
                if section:
                    self._schemas[section] = schema

    def load_from_toml(self, plugins_section: dict) -> None:
        """Load plugin configurations from jac.toml [plugins] section."""
        for section_name, schema in self._schemas.items():
            raw_config = plugins_section.get(section_name, {})

            # Apply defaults
            config = {}
            for opt_name, opt_spec in schema.get("options", {}).items():
                if opt_name in raw_config:
                    config[opt_name] = self._coerce_type(
                        raw_config[opt_name],
                        opt_spec.get("type", "str")
                    )
                else:
                    config[opt_name] = opt_spec.get("default")

            # Apply environment variable overrides
            for opt_name, opt_spec in schema.get("options", {}).items():
                env_var = opt_spec.get("env_var")
                if env_var:
                    import os
                    env_value = os.getenv(env_var)
                    if env_value is not None:
                        config[opt_name] = self._coerce_type(
                            env_value,
                            opt_spec.get("type", "str")
                        )

            self._configs[section_name] = config

    def validate_all(self) -> List[str]:
        """Validate all plugin configurations."""
        all_errors = []
        for section_name, config in self._configs.items():
            # Call plugin's validate_config hook
            errors = plugin_manager.hook.validate_config(config=config)
            for error_list in errors:
                if error_list:
                    for err in error_list:
                        all_errors.append(f"[plugins.{section_name}] {err}")
        return all_errors

    def notify_plugins(self) -> None:
        """Notify plugins that configuration has been loaded."""
        for section_name, config in self._configs.items():
            plugin_manager.hook.on_config_loaded(config=config)

    def get_plugin_config(self, section_name: str) -> dict:
        """Get configuration for a specific plugin."""
        return self._configs.get(section_name, {})

    def _coerce_type(self, value: Any, type_name: str) -> Any:
        """Coerce a value to the specified type."""
        if type_name == "int":
            return int(value)
        elif type_name == "float":
            return float(value)
        elif type_name == "bool":
            if isinstance(value, str):
                return value.lower() in ("true", "yes", "1", "t", "y")
            return bool(value)
        elif type_name == "list":
            if isinstance(value, str):
                return [v.strip() for v in value.split(",")]
            return list(value)
        return value
```

### Integration with JacConfig

```python
# jaclang/project/config.py

from jaclang.project.plugin_config import PluginConfigManager

@dataclass
class JacConfig:
    """Main configuration class for Jac projects."""

    # ... existing fields ...

    plugin_manager: PluginConfigManager = field(
        default_factory=PluginConfigManager
    )

    def load_plugin_configs(self, plugins_section: dict) -> None:
        """Load and validate plugin configurations."""
        self.plugin_manager.collect_schemas()
        self.plugin_manager.load_from_toml(plugins_section)

        # Validate all plugin configs
        errors = self.plugin_manager.validate_all()
        if errors:
            for err in errors:
                print(f"Warning: {err}", file=sys.stderr)

        # Notify plugins
        self.plugin_manager.notify_plugins()

    def get_plugin_config(self, plugin_name: str) -> dict:
        """Get configuration for a specific plugin."""
        return self.plugin_manager.get_plugin_config(plugin_name)
```

### Plugin Configuration Access

Plugins can access their configuration at runtime:

```python
# In plugin code
from jaclang.project.config import get_config

def my_plugin_function():
    config = get_config()
    my_config = config.get_plugin_config("my_plugin")

    model = my_config.get("default_model", "gpt-4")
    temperature = my_config.get("temperature", 0.7)
    # Use configuration values...
```

### CLI for Plugin Configuration

```bash
# List all plugin configuration options
jac config plugins

# Show specific plugin configuration
jac config plugins byllm

# Set a plugin configuration value
jac config set plugins.byllm.temperature 0.5

# Validate all configurations
jac config validate
```

### Implementation Tasks for Plugin Configuration

- [ ] Add `get_config_schema`, `on_config_loaded`, `validate_config` hooks to `JacRuntimeInterface`
- [ ] Create `jaclang/project/plugin_config.py` with `PluginConfigManager`
- [ ] Integrate plugin config loading into `JacConfig.load()`
- [ ] Add `jac config` CLI commands
- [ ] Update existing plugins (jac-byllm, jac-client, jac-scale) with config schemas
- [ ] Write documentation for plugin authors
- [ ] Add unit tests for plugin configuration system

### Example: jac-scale Plugin Configuration

```python
# jac-scale/jac_scale/plugin.py

from jaclang.pycore.runtime import hookimpl

class JacScalePlugin:

    @staticmethod
    @hookimpl
    def get_config_schema() -> dict:
        return {
            "section_name": "scale",
            "options": {
                "kubernetes_namespace": {
                    "type": "str",
                    "default": "default",
                    "description": "Kubernetes namespace for deployments",
                    "env_var": "JAC_K8S_NAMESPACE",
                },
                "auto_scale": {
                    "type": "bool",
                    "default": False,
                    "description": "Enable automatic scaling",
                },
                "min_replicas": {
                    "type": "int",
                    "default": 1,
                    "description": "Minimum number of replicas",
                },
                "max_replicas": {
                    "type": "int",
                    "default": 5,
                    "description": "Maximum number of replicas",
                },
                "cpu_threshold": {
                    "type": "int",
                    "default": 80,
                    "description": "CPU threshold percentage for scaling",
                },
                "storage_class": {
                    "type": "str",
                    "default": "standard",
                    "description": "Kubernetes storage class",
                    "choices": ["standard", "ssd", "premium"],
                },
            }
        }

    @staticmethod
    @hookimpl
    def validate_config(config: dict) -> list[str]:
        errors = []
        min_r = config.get("min_replicas", 1)
        max_r = config.get("max_replicas", 5)
        if min_r > max_r:
            errors.append("min_replicas cannot be greater than max_replicas")
        if config.get("cpu_threshold", 80) < 1 or config.get("cpu_threshold", 80) > 100:
            errors.append("cpu_threshold must be between 1 and 100")
        return errors
```

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
6. Legacy `settings.py` completely removed
7. Plugins can register and use their own configuration options
8. Clear migration documentation for users
9. Comprehensive test coverage
