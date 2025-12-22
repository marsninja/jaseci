# Jac Project Configuration Architecture Redesign

## Overview

This document outlines a comprehensive plan to introduce `jac.toml` as the central project configuration file for Jac projects.

## Goals

1. **Unified Configuration**: Single `jac.toml` file for all project settings (superseding `pyproject.toml` patterns)
2. **Dependency Management**: First-class Jac and Python dependency declaration and installation
3. **Project Initialization**: `jac init` command for project scaffolding
4. **Project Detection**: All `jac` commands auto-detect and use project configuration

---

## `jac.toml` Specification

### Complete Schema

Based on actual CLI arguments and plugin configurations found in the codebase:

```toml
# jac.toml - Jac Project Configuration

#===============================================================================
# PROJECT METADATA
#===============================================================================

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

#===============================================================================
# DEPENDENCIES
#===============================================================================

[dependencies]
# Jac plugins (from PyPI)
jac-byllm = ">=0.4.8"
jac-client = ">=0.2.3"
jac-scale = ">=0.1.0"

# Python dependencies
requests = ">=2.28.0"

[dependencies.git]
# Git-based dependencies
my-plugin = { git = "https://github.com/user/plugin.git", branch = "main" }

[dependencies.npm]
# NPM dependencies (used by jac-client) - actual defaults from codebase
react = "^19.2.0"
react-dom = "^19.2.0"
react-router-dom = "^6.30.1"

[dependencies.npm.dev]
vite = "^6.4.1"
typescript = "^5.3.3"
"@vitejs/plugin-react" = "^4.2.1"
"@types/react" = "^18.2.45"
"@types/react-dom" = "^18.2.18"

[dev-dependencies]
pytest = ">=8.2.1"

#===============================================================================
# RUN COMMAND DEFAULTS (from cli.jac run command)
#===============================================================================

[run]
# Default arguments for `jac run`
session = ""                      # Session identifier for persistent state
main = true                       # Treat file as __main__
cache = true                      # Use cached compilation (.jbc files)

#===============================================================================
# BUILD COMMAND DEFAULTS (from cli.jac build command)
#===============================================================================

[build]
typecheck = false                 # Run type checking during build

#===============================================================================
# TEST COMMAND DEFAULTS (from cli.jac test command)
#===============================================================================

[test]
directory = ""                    # Test directory (empty = current)
filter = ""                       # Filter test files by pattern
verbose = false                   # Detailed output
fail_fast = false                 # Stop on first failure (xit flag)
max_failures = 0                  # Stop after N failures (0 = unlimited)

#===============================================================================
# SERVE COMMAND DEFAULTS (from cli.jac serve command)
#===============================================================================

[serve]
port = 8000                       # Server port
session = ""                      # Session identifier
main = true                       # Treat as __main__

#===============================================================================
# FORMAT COMMAND DEFAULTS (from cli.jac format command)
#===============================================================================

[format]
outfile = ""                      # Output file (empty = in-place)
fix = false                       # Apply auto-linting fixes

#===============================================================================
# CHECK COMMAND DEFAULTS (from cli.jac check command)
#===============================================================================

[check]
print_errs = true                 # Print error messages
warnonly = false                  # Treat errors as warnings only

#===============================================================================
# DOT/GRAPH VISUALIZATION DEFAULTS (from cli.jac dot command)
#===============================================================================

[dot]
depth = -1                        # Traversal depth (-1 = unlimited)
traverse = false                  # Traverse graph from initial node
bfs = false                       # Use BFS instead of DFS
edge_limit = 512                  # Maximum edges to render
node_limit = 512                  # Maximum nodes to render
format = "dot"                    # Output format

#===============================================================================
# CACHE SETTINGS
#===============================================================================

[cache]
enabled = true                    # Enable bytecode caching
dir = ".jac_cache"                # Cache directory

#===============================================================================
# PLUGIN SYSTEM
#===============================================================================

[plugins]
# Plugin discovery
discovery = "auto"                # "auto" | "explicit"
enabled = []                      # Plugins to enable (explicit mode)
disabled = []                     # Plugins to disable (auto mode)

#-------------------------------------------------------------------------------
# jac-client Plugin (from jac-client/config.json structure)
#-------------------------------------------------------------------------------

[plugins.client.vite]
plugins = []                      # Vite plugins to load
lib_imports = []                  # Additional library imports

[plugins.client.vite.build]
outDir = "dist/client"
sourcemap = true
minify = "esbuild"                # "esbuild" | "terser" | false
target = "es2020"
cssCodeSplit = true
chunkSizeWarningLimit = 500

[plugins.client.vite.server]
port = 5173
host = "localhost"
open = false
strictPort = false
https = false

[plugins.client.vite.resolve]
alias = {}                        # Module aliases
extensions = [".mjs", ".js", ".ts", ".jsx", ".tsx", ".json"]

[plugins.client.vite.optimizeDeps]
include = []
exclude = []

[plugins.client.typescript]
# Maps to tsconfig.json compilerOptions
strict = true
target = "ES2020"
module = "ESNext"
moduleResolution = "bundler"
jsx = "react-jsx"
esModuleInterop = true
skipLibCheck = true
declaration = true
declarationMap = false
sourceMap = true
noEmit = false
isolatedModules = true
allowSyntheticDefaultImports = true
forceConsistentCasingInFileNames = true
resolveJsonModule = true
include = ["src/**/*"]
exclude = ["node_modules", "dist"]

[plugins.client.package]
# Maps to package.json fields (defaults from project section)
name = ""                         # Defaults to project.name
version = "1.0.0"
description = ""
main = "dist/index.js"
types = "dist/index.d.ts"
private = true
scripts = {}
keywords = []

#-------------------------------------------------------------------------------
# jac-scale Plugin (from K8s.impl.jac environment variables)
#-------------------------------------------------------------------------------

[plugins.scale]
# These map to environment variables used by jac-scale
app_name = "jaseci"               # APP_NAME env var
docker_image = ""                 # DOCKER_IMAGE_NAME (default: {app_name}:latest)
namespace = "default"             # K8s_NAMESPACE
container_port = 8000             # K8s_CONTAINER_PORT
node_port = 30001                 # K8s_NODE_PORT
docker_username = ""              # DOCKER_USERNAME
mongodb_enabled = true            # K8s_MONGODB
redis_enabled = true              # K8s_REDIS

# Database URIs (environment variable interpolation)
mongodb_uri = "${MONGODB_URI}"
redis_url = "${REDIS_URL}"

#-------------------------------------------------------------------------------
# jac-byllm Plugin (LLM configuration)
#-------------------------------------------------------------------------------

[plugins.byllm]
default_model = "gpt-4"
temperature = 0.7
max_tokens = 4096
api_key_env = "OPENAI_API_KEY"    # Environment variable for API key

# Named model configurations
[plugins.byllm.models.claude]
model = "claude-sonnet-4-20250514"
api_key_env = "ANTHROPIC_API_KEY"
temperature = 0.7
max_tokens = 4096

[plugins.byllm.models.local]
model = "ollama/llama2"
api_base_url = "http://localhost:11434"
temperature = 0.8

#===============================================================================
# ENVIRONMENT PROFILES
#===============================================================================

[environments.development]
[environments.development.serve]
port = 3000

[environments.development.plugins.byllm]
cache_enabled = false

[environments.production]
[environments.production.serve]
port = 8000

[environments.production.plugins.scale]
namespace = "production"
mongodb_enabled = true
redis_enabled = true

#===============================================================================
# CUSTOM SCRIPTS
#===============================================================================

[scripts]
dev = "jac run main.jac"
build = "jac build main.jac --typecheck"
test = "jac test tests/"
lint = "jac format . --fix"
deploy = "jac scale main.jac --build"
```

---

## New CLI Commands

### `jac init`

Initialize a new Jac project.

```bash
# Initialize with current directory name as project name
jac init

# Initialize with specific project name
jac init --name my-project
```

**Behavior:**

1. Create `jac.toml` with project configuration
2. Create basic project structure
3. Add appropriate entries to `.gitignore`

**Generated structure:**

```
my-project/
├── jac.toml
├── .gitignore
├── main.jac            # Entry point
├── packages/           # Python/Jac dependencies (added to .gitignore)
├── client/             # Client-side files (created by jac-client, added to .gitignore)
│   ├── node_modules/   # NPM dependencies
│   ├── package.json    # Generated from [dependencies.npm]
│   ├── package-lock.json
│   └── tsconfig.json   # Generated from [plugins.client.typescript]
└── README.md
```

**Note:** The `client/` directory is only created when jac-client plugin is used. It contains all NPM-related files, keeping them separate from Python/Jac dependencies in `packages/`.

### `jac install`

Install all dependencies from `jac.toml` into the local `packages/` directory.

```bash
# Install all dependencies from jac.toml
jac install

# Install including dev dependencies
jac install --dev
```

**Behavior:**

1. Read `jac.toml` dependencies
2. Install packages into `packages/` directory using pip (`pip install --target packages/`)
3. Update lock file (`jac.lock`)

### `jac add` / `jac remove`

Add or remove dependencies. `jac add` is the primary interface for adding new dependencies - it updates `jac.toml` AND installs the package.

```bash
# Add a Python/Jac dependency (updates [dependencies] and installs to packages/)
jac add requests

# Add dev dependency (updates [dev-dependencies])
jac add pytest --dev

# Add with version constraint
jac add "numpy>=1.24"

# Add from git (updates [dependencies.git])
jac add --git https://github.com/user/plugin.git

# Add client-side NPM dependency (requires jac-client plugin)
jac add --cl react

# Add client-side NPM dev dependency
jac add --cl -d vite

# Remove a dependency
jac remove requests
jac remove --cl react
```

**Behavior:**

1. Add/remove package from appropriate `jac.toml` section
2. For Python/Jac deps: Install to / remove from `packages/` directory
3. For NPM deps: Install to / remove from `client/node_modules/` (via npm/pnpm in `client/` directory)
4. Update lock file (`jac.lock`)

### NPM Dependencies Architecture

The `[dependencies.npm]` section is a **plugin-provided feature** - only available when jac-client is installed:

```toml
[dependencies.npm]
react = "^19.2.0"
react-dom = "^19.2.0"

[dependencies.npm.dev]
vite = "^6.4.1"
typescript = "^5.3.3"
```

**Client Directory Structure:**

All NPM-related files are placed in a `client/` directory at the project root, keeping them separate from Python dependencies:

```
my-project/
├── jac.toml
├── main.jac               # Jac entry point
├── packages/              # Python/Jac dependencies
├── client/                # All client-side/NPM files
│   ├── node_modules/      # NPM packages installed here
│   ├── package.json       # Generated from [dependencies.npm]
│   ├── package-lock.json  # NPM lock file
│   ├── tsconfig.json      # Generated from [plugins.client.typescript]
│   ├── vite.config.ts     # Generated from [plugins.client.vite]
│   └── src/               # Client source (if using jac-client's bundler)
│       └── ...
└── README.md
```

**Why a separate `client/` directory?**

- **Clean separation**: Python deps in `packages/`, NPM deps in `client/`
- **Standard npm workflow**: `client/` acts as a standard npm project root
- **Gitignore simplicity**: Just add `client/node_modules/` to `.gitignore`
- **IDE support**: IDEs can treat `client/` as a separate TypeScript/JavaScript project

**How jac-client provides this:**

1. **jac-client registers a dependency handler** via a new `register_dependency_type` hook
2. **JacConfig** stores unknown `[dependencies.*]` sections in a `plugin_dependencies: dict[str, dict]` field
3. **jac-client** reads its section via `get_config().plugin_dependencies.get("npm", {})`
4. **jac-client extends the CLI** - adds `jac add --cl` flag for client-side packages
5. **PackageInstaller** generates `client/package.json` and runs `npm install` in `client/`

**Plugin Dependency Hook:**

```jac
# In JacRuntimeInterface
@hookspec
def register_dependency_type() -> dict | None;
"""Register a custom dependency type.

Returns:
    {
        "name": "npm",           # Section name: [dependencies.npm]
        "cli_flag": "--cl",      # Flag for `jac add`
        "install_handler": fn,   # Called to install packages
        "remove_handler": fn,    # Called to remove packages
    }
"""
```

This keeps the core lean - it doesn't need to know about NPM, Go modules, or any other package managers. Plugins register their own dependency types.

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
2. **Load settings** from `jac.toml` (overridable by CLI args)
3. **Add `packages/`** directory to Python path for local dependencies
4. **Use project paths** for module resolution
5. **Support `--env` flag** to load environment-specific overrides

---

## Environment Variable Interpolation

Values in `jac.toml` can reference environment variables using special syntax. This is critical for managing secrets and environment-specific configuration.

### Syntax

| Syntax | Behavior |
|--------|----------|
| `${VAR_NAME}` | Required - fails if not set |
| `${VAR_NAME:-default}` | Optional with default value |
| `${VAR_NAME:?error message}` | Required with custom error message |

### Examples

```toml
[plugins.scale]
# Required environment variables
mongodb_uri = "${MONGODB_URI}"
jwt_secret = "${JAC_JWT_SECRET:?JWT secret must be set}"

# Optional with defaults
debug_mode = "${DEBUG:-false}"
log_level = "${LOG_LEVEL:-INFO}"

# Nested in URLs
api_base_url = "https://${API_HOST:-localhost}:${API_PORT:-8080}/api"

[plugins.byllm]
# Reference env var name (alternative pattern for sensitive data)
api_key_env = "OPENAI_API_KEY"  # Plugin reads from this env var at runtime
```

---

## Configuration Profiles (Environments)

Support different configurations for development, staging, and production environments.

### Profile Definition

Profiles are defined under `[environments.<name>]` and can override any configuration value:

```toml
# Base configuration (always applied)
[settings]
show_internal_stack_errs = false

[serve]
port = 8000

[plugins.byllm]
temperature = 0.7

# Development profile
[environments.development]
# Nested overrides
[environments.development.settings]
show_internal_stack_errs = true
all_warnings = true

[environments.development.serve]
reload = true
port = 3000

[environments.development.plugins.byllm]
log_prompts = true

# Production profile
[environments.production.serve]
reload = false
host = "0.0.0.0"

[environments.production.plugins.scale]
min_replicas = 3
```

### Profile Selection

Profiles can be selected via:

1. **CLI flag**: `jac run --env production`
2. **Environment variable**: `JAC_ENV=production jac run`
3. **Config file**: Set default in `jac.toml`:

   ```toml
   [environment]
   default_profile = "development"
   ```

### Profile Inheritance

Profiles can inherit from other profiles:

```toml
[environments.staging]
inherits = "production"  # Start with production settings

# Then override specific values
[environments.staging.plugins.scale]
kubernetes_namespace = "staging"
min_replicas = 1
```

---

## Implementation Architecture

### New Module Structure

Following the existing jaclang pattern (signature/implementation split):

```
jaclang/
├── cli/
│   ├── cli.jac              # Updated with new commands (add init, install, add, remove, script)
│   ├── cmdreg.jac           # Existing command registry
│   └── impl/
│       └── cli.impl.jac     # Updated with new command implementations
├── project/                 # NEW: Project management module
│   ├── __init__.py          # Python module init for imports
│   ├── config.jac           # JacConfig class and related types
│   ├── discovery.jac        # Project root discovery
│   ├── dependencies.jac     # Dependency resolution
│   ├── lockfile.jac         # jac.lock management
│   ├── plugin_config.jac    # PluginConfigManager
│   └── impl/
│       ├── config.impl.jac       # JacConfig implementations
│       ├── discovery.impl.jac    # Discovery implementations
│       ├── dependencies.impl.jac # Dependency implementations
│       ├── lockfile.impl.jac     # Lockfile implementations
│       └── plugin_config.impl.jac # Plugin config implementations
├── pycore/
│   └── ...
└── ...
```

**Pattern Notes:**

- `.jac` files contain class definitions, type signatures, and `glob` declarations
- `.impl.jac` files in `impl/` subdirectory contain method implementations
- New CLI commands (`init`, `install`, `add`, `remove`, `script`) added to existing `cli.jac` using `@cmd_registry.register`
- Use `glob` for module-level singletons (e.g., `glob _config: JacConfig | None = None;`)

### Core Classes

#### `JacConfig` (replaces `Settings`)

```jac
# jaclang/project/config.jac

import from pathlib { Path }

obj ProjectConfig {
    has name: str = "",
        version: str = "0.1.0",
        description: str = "",
        authors: list[str] = [],
        license: str = "",
        jac_version: str = "",
        entry_point: str = "main.jac";
}

obj SettingsConfig {
    has max_line_length: int = 88,
        ignore_test_annex: bool = False,
        cache_enabled: bool = True,
        cache_dir: str = ".jac_cache",
        output_dir: str = "dist";
    # ... additional settings
}

class JacConfig {
    has project: ProjectConfig,
        settings: SettingsConfig,
        # Core dependencies (Python/Jac packages)
        dependencies: dict[str, str],
        dev_dependencies: dict[str, str],
        git_dependencies: dict[str, dict],
        # Plugin-provided dependency types (e.g., npm, go, etc.)
        # Populated from [dependencies.<type>] sections
        plugin_dependencies: dict[str, dict[str, str]],
        # Scripts and plugins
        scripts: dict[str, str],
        plugins: dict[str, dict],
        # Runtime state
        project_root: Path | None = None,
        toml_path: Path | None = None;

    static def discover(start_path: Path | None = None) -> JacConfig;
    static def load(toml_path: Path) -> JacConfig;
    def apply_env_overrides(self: JacConfig) -> None;
    def apply_cli_overrides(self: JacConfig, args: dict) -> None;
    def get_plugin_deps(self: JacConfig, dep_type: str) -> dict[str, str];
}

# Global singleton
glob _config: JacConfig | None = None;

def get_config -> JacConfig;
```

#### Project Discovery

```jac
# jaclang/project/discovery.jac

import from pathlib { Path }

def find_project_root(start: Path | None = None) -> tuple[Path, Path] | None;
"""Find project root by looking for jac.toml. Returns (project_root, toml_path) or None."""

def is_in_project -> bool;
"""Check if currently in a Jac project."""
```

---

## Migration Strategy

**Note:** This is a clean break from legacy plugin configuration files (e.g., `config.json`, `.env`). The `jac.toml` configuration fully subsumes all plugin configuration - no backward compatibility or dual-loading is provided. Plugins must be updated to use the new hook-based configuration system.

### Phase 1: Core Infrastructure

1. Create `jaclang/project/` module with Jac files
2. Implement `JacConfig` class and discovery
3. Add `jac init`, `jac install`, `jac add`, `jac remove` commands
4. Implement plugin configuration hooks

### Phase 2: Integration

1. Modify `start_cli()` to auto-discover projects
2. Update `run`, `build`, `test`, `format`, `serve` to use `JacConfig`
3. Add `packages/` directory to Python path when project detected
4. Update plugins (jac-client, jac-byllm, jac-scale) to use new config system

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

### Task 2: New CLI Commands

- [ ] Implement `jac init` command
- [ ] Implement `jac install` command (install all deps from jac.toml to packages/)
- [ ] Implement `jac add` command (add to jac.toml AND install to packages/)
- [ ] Implement `jac remove` command (remove from jac.toml AND packages/)
- [ ] Implement lock file generation (`jac.lock`)
- [ ] Implement `jac script` command
- [ ] Update command registry for new commands

### Task 3: Integrate with Existing Commands

- [ ] Modify `start_cli()` for project auto-detection
- [ ] Add `packages/` directory to Python path when project detected
- [ ] Update `run` command for project context
- [ ] Update `build` command for project settings
- [ ] Update `test` command for project test config
- [ ] Update `format` command for project format settings
- [ ] Update `serve` command for project server settings
- [ ] Update `lsp` command for project paths

### Task 4: Complete Legacy Migration

- [ ] Remove `~/.jaclang/config.ini` support
- [ ] Update all internal references to use `JacConfig`
- [ ] Write migration documentation for users

### Task 5: Plugin Configuration System

- [ ] Add `get_config_schema`, `on_config_loaded`, `validate_config` hooks to `JacRuntimeInterface`
- [ ] Create `jaclang/project/plugin_config.py` with `PluginConfigManager`
- [ ] Integrate plugin config loading into `JacConfig.load()`
- [ ] Update existing plugins (jac-byllm, jac-client, jac-scale) with config schemas
- [ ] Write plugin author documentation

### Task 6: Documentation and Testing

- [ ] Write user documentation for `jac.toml`
- [ ] Document all new CLI commands
- [ ] Document plugin configuration interface for plugin authors
- [ ] Add integration tests
- [ ] Add example projects
- [ ] Update README

### Task 7: Python Compatibility

- [ ] Add `tomli` to dependencies for Python <3.11 support
- [ ] Create compatibility shim: use `tomllib` (stdlib) on 3.11+, `tomli` on 3.10
- [ ] Test on Python 3.10, 3.11, 3.12

### Task 8: Update Existing Plugins

**Note:** jac-client should be implemented first as the **reference implementation** since it has the cleanest existing config infrastructure (JacClientConfig class with defaults, deep merge, lazy loading). All plugins will be updated directly - no backward compatibility with legacy config files.

- [ ] **jac-client** (Reference Implementation - Do First):
  - [ ] Add `get_config_schema()` hook implementation
  - [ ] Add `get_plugin_metadata()` hook implementation
  - [ ] Add `on_config_loaded()` hook implementation
  - [ ] Add `validate_config()` hook (vite options, port ranges, etc.)
  - [ ] Remove config.json loading from JacClientConfig (use jac.toml only)
  - [ ] Update ViteBundler to read from plugin config
  - [ ] Update PackageInstaller to use [dependencies.npm] section
- [ ] **jac-byllm**:
  - [ ] Add `get_config_schema()` hook implementation
  - [ ] Add `get_plugin_metadata()` hook implementation
  - [ ] Add `on_config_loaded()` hook implementation
  - [ ] Add `validate_config()` hook implementation
- [ ] **jac-scale**:
  - [ ] Add `get_config_schema()` hook implementation
  - [ ] Add `get_plugin_metadata()` hook implementation
  - [ ] Add `on_config_loaded()` hook implementation
  - [ ] Add `validate_config()` hook (k8s namespace, replicas, etc.)
- [ ] **jac-streamlit**:
  - [ ] Add `get_config_schema()` hook implementation
  - [ ] Add `get_plugin_metadata()` hook implementation
  - [ ] Add `on_config_loaded()` hook implementation
- [ ] Write integration tests for each plugin's config loading

---

## Example Workflows

### New Project

```bash
$ mkdir my-project && cd my-project
$ jac init
Created jac.toml
Created main.jac

Project 'my-project' initialized successfully!

$ jac run             # Run main.jac
$ jac add <pkg>       # Add dependencies
```

### Adding Dependencies

```bash
$ jac add jac-byllm numpy "requests>=2.28"
Adding to jac.toml and installing to packages/...
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
# 2. Adds packages/ to Python path
# 3. Loads settings from [settings]
# 4. Runs entry-point (main.jac)

$ jac run other.jac --port 9000
# Settings from jac.toml, CLI override for port
```

---

## Files to Create/Modify

### New Files - Core Project Module (Jac)

| File | Description |
|------|-------------|
| `jaclang/project/__init__.py` | Python module init for imports |
| `jaclang/project/config.jac` | `JacConfig`, `ProjectConfig`, `SettingsConfig` class definitions |
| `jaclang/project/discovery.jac` | `find_project_root()`, `is_in_project()` signatures |
| `jaclang/project/dependencies.jac` | Dependency resolution class definitions |
| `jaclang/project/lockfile.jac` | `jac.lock` file management class definitions |
| `jaclang/project/plugin_config.jac` | `PluginConfigManager` class definition |
| `jaclang/project/impl/config.impl.jac` | `JacConfig` method implementations |
| `jaclang/project/impl/discovery.impl.jac` | Discovery function implementations |
| `jaclang/project/impl/dependencies.impl.jac` | Dependency resolution implementations |
| `jaclang/project/impl/lockfile.impl.jac` | Lockfile management implementations |
| `jaclang/project/impl/plugin_config.impl.jac` | `PluginConfigManager` implementations |

### Modified Files - CLI (Jac)

New commands added to existing CLI files following the established pattern:

| File | Changes |
|------|---------|
| `jaclang/cli/cli.jac` | Add `init`, `install`, `add`, `remove`, `script` command signatures with `@cmd_registry.register` |
| `jaclang/cli/impl/cli.impl.jac` | Add implementations for new commands |

### New Files - Plugin Updates

| File | Description |
|------|-------------|
| `jac-byllm/byllm/config_schema.py` | byllm plugin config schema |
| `jac-client/jac_client/config_schema.py` | client plugin config schema |
| `jac-scale/jac_scale/config_schema.py` | scale plugin config schema |
| `jac-streamlit/jaclang_streamlit/config_schema.py` | streamlit plugin config schema |

### New Files - Documentation & Schemas

| File | Description |
|------|-------------|
| `docs/configuration/jac-toml.md` | User documentation for jac.toml |
| `docs/configuration/plugins.md` | Plugin configuration documentation |
| `docs/plugins/config-hooks.md` | Plugin author config documentation |
| `schemas/jac-toml-schema.json` | JSON Schema for IDE support |

### Modified Files

| File | Changes |
|------|---------|
| `jaclang/pycore/runtime.py` | Add new plugin hooks (`get_config_schema`, `on_config_loaded`, `validate_config`) |
| `jaclang/__init__.py` | Initialize project config, load plugin configs |
| `pyproject.toml` | Add tomli dependency for Python <3.11 compatibility |

### Modified Files - Plugins

| File | Changes |
|------|---------|
| `jac-byllm/byllm/plugin.jac` | Add config hook implementations |
| `jac-byllm/pyproject.toml` | Update entry points for config hooks |
| `jac-client/jac_client/plugin/client.jac` | Add config hook implementations, replace JSON config loading |
| `jac-client/pyproject.toml` | Update entry points for config hooks |
| `jac-scale/jac_scale/plugin.py` | Add config hook implementations |
| `jac-scale/pyproject.toml` | Update entry points for config hooks |
| `jac-streamlit/jaclang_streamlit/commands.py` | Add config hook implementations |
| `jac-streamlit/pyproject.toml` | Update entry points for config hooks |

### Already Removed Files

| File | Status |
|------|--------|
| `jaclang/pycore/settings.py` | Already removed |

### New Project Files (Generated by `jac init`)

| File | Description |
|------|-------------|
| `jac.toml` | Project configuration |
| `jac.lock` | Dependency lock file (generated by `jac install`/`jac add`) |
| `packages/` | Local dependency directory (added to .gitignore) |

---

## Plugin Configuration Interface

This section describes how plugins can register their own configuration options that will be loaded from `jac.toml` and made available through the configuration system.

### Current Plugin Architecture

The current plugin system in `runtime.py` uses `pluggy` for hook-based extensibility. Plugins implement hooks defined in `JacRuntimeInterface` and are loaded via setuptools entry points.

### New Plugin Configuration Hooks

Four new hooks will be added to `JacRuntimeInterface`:

1. **`get_config_schema()`**: Returns the plugin's configuration schema with section name, options (type, default, description, env_var override)
2. **`on_config_loaded(config)`**: Called when plugin configuration is loaded from `jac.toml`
3. **`validate_config(config)`**: Returns list of validation error messages (empty if valid)
4. **`register_dependency_type()`**: Registers a custom dependency type (e.g., `npm` for jac-client)

The `register_dependency_type` hook allows plugins to extend `[dependencies.*]` sections:

```jac
# jac-client implements this hook
@hookimpl
def register_dependency_type() -> dict {
    return {
        "name": "npm",
        "dev_name": "npm.dev",           # For dev dependencies
        "cli_flag": "--cl",              # Flag for `jac add --cl`
        "install_dir": "client",         # Directory for all npm-related files
        "install_cmd": "npm install",
        "install_handler": install_npm_package,
        "remove_handler": remove_npm_package,
    };
}
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

The `PluginConfigManager` class in `jaclang/project/plugin_config.py` handles:

1. **Schema Collection**: Gathers configuration schemas from all registered plugins via `get_config_schema()` hook
2. **Config Loading**: Loads values from `[plugins.<name>]` sections, applies defaults for missing values
3. **Environment Overrides**: Applies environment variable overrides specified in schema
4. **Validation**: Calls each plugin's `validate_config()` hook
5. **Notification**: Calls `on_config_loaded()` to notify plugins

### Integration with JacConfig

`JacConfig` includes a `PluginConfigManager` instance and provides:

- `load_plugin_configs()`: Load and validate all plugin configurations
- `get_plugin_config(plugin_name)`: Get configuration for a specific plugin

### Plugin Configuration Access

Plugins access their configuration via `get_config().get_plugin_config("plugin_name")`.

---

## Open Questions (Resolved)

1. **Workspace Support**: Should we support multi-project workspaces (like Cargo workspaces)?

   **Decision: YES** - Implemented via `jac-workspace.toml`. This is essential for the jaseci monorepo structure and allows shared configuration across plugins. See "Workspace Support" section for full specification.

2. **Lock File Strategy**: Should `jac.lock` be committed to git? (Recommended: yes, for reproducibility)

   **Decision: YES** - Lock files should be committed for reproducible builds. The lock file includes:
   - Package versions with hashes
   - Platform information
   - Config hash for change detection
   - Plugin config schema versions

3. **Plugin Configuration**: How deeply should plugins be configurable via `jac.toml`?

   **Decision: FULLY CONFIGURABLE** - Plugins define their own configuration schema via the `get_config_schema()` hook. This allows:
   - All plugin settings in `[plugins.<name>]` section
   - Type validation and defaults
   - Environment variable overrides
   - Per-environment profile overrides
   - IDE autocomplete via JSON Schema generation

   See complete plugin schemas for jac-byllm, jac-client, jac-scale, and jac-streamlit in the "Complete Schema" section.

4. **Remote Registries**: Should we have a Jac-specific package registry, or rely entirely on PyPI?

   **Decision: PyPI ONLY (for now)** - Continue using PyPI for package distribution. A Jac-specific registry could be considered in the future for:
   - Pure Jac packages (not Python)
   - Faster discovery of Jac plugins
   - Curated/verified plugin listings

   **Future consideration**: Add `[registries]` section for custom registries when needed.

---

## Remaining Open Questions

1. **Configuration Schema Versioning**: How should we handle breaking changes to plugin configuration schemas?
   - Option A: Automatic migration with `config_schema_version`
   - Option B: Manual migration via `jac migrate-config`
   - Option C: Both (auto-migrate when possible, prompt otherwise)

2. **Secrets Management**: Should we integrate with external secrets managers (Vault, AWS Secrets Manager)?
   - Current approach: Environment variable interpolation (`${SECRET}`)
   - Future: Optional integration with secrets backends

3. **Remote Configuration**: Should we support loading configuration from remote URLs?
   - Use case: Shared team configurations
   - Security implications need consideration

---

## Success Criteria

### Core Functionality

1. New projects can be created with `jac init`
2. Dependencies managed via `jac.toml` and `jac install`
3. All existing `jac` commands work with project context
4. Settings from `jac.toml` properly loaded and applied

### Plugin System

1. Plugins can register configuration schemas via hooks
2. Plugin configurations loaded from `[plugins.<name>]` sections
3. Plugin configuration validation with helpful error messages
4. Plugin dependency resolution and load ordering

### Developer Experience

1. Environment variable interpolation for secrets (`${VAR}`)
2. Configuration profiles for dev/staging/production (`--env`)
3. Workspace support for monorepos (`jac-workspace.toml`)
4. Configuration inheritance (`extends` key)
5. Hot reload during development (`config_hot_reload`)
6. JSON Schema generation for IDE support

### Documentation & Testing

1. Plugin author documentation for config hooks
2. User documentation for `jac.toml`
3. Comprehensive test coverage

---
