# Jac Project Configuration Architecture Redesign

## Overview

This document outlines a comprehensive plan to introduce `jac.toml` as the central project configuration file for Jac projects, replacing the current `settings.py` approach and introducing proper virtual environment management via `.jac_env/`.

## Goals

1. **Unified Configuration**: Single `jac.toml` file for all project settings (superseding `pyproject.toml` patterns)
2. **Environment Isolation**: Automatic virtual environment creation in `.jac_env/`
3. **Dependency Management**: First-class Jac and Python dependency declaration and installation
4. **Project Initialization**: `jac init` command for project scaffolding
5. **Environment Detection**: All `jac` commands auto-detect and use project environment

**Note**: This is a clean break from the legacy `settings.py` and `~/.jaclang/config.ini` system. No backward compatibility is maintained. All plugins in this repository will be updated directly to use the new configuration system.

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
documentation = "https://docs.example.com"

#===============================================================================
# DEPENDENCIES
#===============================================================================

# Dependencies section - supports both Jac plugins and Python packages
[dependencies]
# Jac plugins (from PyPI or git)
jac-byllm = ">=0.4.8"
jac-client = ">=0.2.3"
jac-scale = ">=0.1.0"
jac-streamlit = ">=0.0.5"

# Python dependencies
requests = ">=2.28.0"
numpy = ">=1.24.0"

[dependencies.git]
# Git-based dependencies
my-jac-plugin = { git = "https://github.com/user/plugin.git", branch = "main" }

[dev-dependencies]
pytest = ">=8.2.1"
pytest-cov = ">=5.0.0"

#===============================================================================
# CORE SETTINGS (from settings.py)
#===============================================================================

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

# Cache settings
cache_enabled = true
cache_dir = ".jac_cache"

# Output settings
output_dir = "dist"

# Configuration behavior
config_hot_reload = false         # Reload config on file change (dev mode)
config_watch_interval = 1.0       # Seconds between config file checks

[settings.paths]
# Module search paths (replaces JACPATH env var)
include = ["src", "lib", "vendor"]

#===============================================================================
# ENVIRONMENT
#===============================================================================

[environment]
# Virtual environment configuration
python_version = "3.11"           # Minimum Python version
env_dir = ".jac_env"              # Environment directory name
auto_activate = true              # Auto-activate on jac commands

#===============================================================================
# BUILD CONFIGURATION
#===============================================================================

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

#===============================================================================
# TEST CONFIGURATION
#===============================================================================

[test]
# Test configuration
directory = "tests"
pattern = "test_*.jac"
verbose = false
fail_fast = false
max_failures = 0                  # 0 = unlimited
coverage = false
coverage_report = "html"          # html | xml | json | term

#===============================================================================
# SERVER CONFIGURATION
#===============================================================================

[serve]
# Server configuration
port = 8000
host = "0.0.0.0"
reload = true                     # Hot reload on file changes
cors_origins = ["*"]
cors_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
cors_headers = ["*"]

#===============================================================================
# FORMATTER CONFIGURATION
#===============================================================================

[format]
# Formatter configuration
max_line_length = 88
indent_size = 4
use_tabs = false
auto_lint = false                 # Apply linting during format
exclude = [".jac_env", "node_modules", "dist", ".jac_cache"]

#===============================================================================
# PLUGIN SYSTEM CONFIGURATION
#===============================================================================

[plugins]
# Plugin discovery and loading
discovery = "auto"                # "auto" | "explicit"
                                  # auto: Load all installed plugins except disabled
                                  # explicit: Only load enabled plugins
enabled = []                      # For explicit mode: plugins to load
disabled = []                     # For auto mode: plugins to skip
load_order = []                   # Optional: explicit load order for hook priority

#-------------------------------------------------------------------------------
# jac-byllm Plugin Configuration
# LLM integration for the `by` operator and AI-powered features
#-------------------------------------------------------------------------------

[plugins.byllm]
# Model settings
default_model = "gpt-4"
temperature = 0.7
max_tokens = 4096
top_p = 1.0
frequency_penalty = 0.0
presence_penalty = 0.0

# API configuration
api_base_url = ""                 # Custom API endpoint (leave empty for default)
api_key_env = "OPENAI_API_KEY"    # Environment variable containing API key
timeout_seconds = 60
retry_attempts = 3
retry_delay_seconds = 1

# Caching
cache_enabled = true
cache_dir = ".jac_cache/llm"
cache_ttl_seconds = 3600          # Cache time-to-live

# Logging (use with caution - may log sensitive data)
log_prompts = false
log_responses = false

# Plugin metadata
depends_on = []                   # No plugin dependencies
conflicts_with = []

[plugins.byllm.logging]
level = "INFO"                    # DEBUG | INFO | WARNING | ERROR
file = ""                         # Optional: log file path
format = "%(asctime)s - %(name)s - %(levelname)s - %(message)s"

# Multi-model support - define named model configurations
[plugins.byllm.models.claude]
model = "claude-sonnet-4-20250514"
api_key_env = "ANTHROPIC_API_KEY"
api_base_url = ""
temperature = 0.7
max_tokens = 4096

[plugins.byllm.models.local]
model = "ollama/llama2"
api_base_url = "http://localhost:11434"
api_key_env = ""                  # Local models typically don't need keys
temperature = 0.8

[plugins.byllm.models.azure]
model = "azure/gpt-4"
api_key_env = "AZURE_API_KEY"
api_base_url = "${AZURE_OPENAI_ENDPOINT}"  # Environment variable interpolation
temperature = 0.7

#-------------------------------------------------------------------------------
# jac-client Plugin Configuration
# Client-side bundling with Vite for web applications
#-------------------------------------------------------------------------------

[plugins.client]
# Output settings
bundle_output_dir = "dist/client"
source_maps = true
minify = false

# Asset handling
asset_dir = "assets"
public_dir = "public"

# Plugin metadata
depends_on = []
conflicts_with = []

[plugins.client.logging]
level = "INFO"
file = ""

[plugins.client.vite]
# Vite plugins to load (npm package names)
plugins = []

# Additional library imports for vite.config.js
lib_imports = []

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
# Module aliases (e.g., "@" -> "./src")
alias = {}

[plugins.client.vite.optimizeDeps]
# Dependencies to pre-bundle
include = []
exclude = []

[plugins.client.typescript]
strict = true
target = "ES2020"
module = "ESNext"
moduleResolution = "bundler"
jsx = "react-jsx"
esModuleInterop = true
skipLibCheck = true
declaration = true

#-------------------------------------------------------------------------------
# jac-scale Plugin Configuration
# Kubernetes and Docker deployment for scalable Jac applications
#-------------------------------------------------------------------------------

[plugins.scale]
# Kubernetes settings
kubernetes_namespace = "default"
kubernetes_context = ""           # Optional: specific k8s context to use
kubernetes_config_path = ""       # Optional: path to kubeconfig file

# Docker settings
docker_registry = ""              # Docker registry URL (e.g., "gcr.io/my-project")
docker_tag_prefix = "jac-"
dockerfile_path = ""              # Custom Dockerfile path (auto-generated if empty)

# Scaling settings
auto_scale = false
min_replicas = 1
max_replicas = 5
cpu_threshold = 80                # CPU percentage to trigger scale-up
memory_threshold = 80             # Memory percentage to trigger scale-up
scale_up_cooldown = 60            # Seconds to wait before scaling up again
scale_down_cooldown = 300         # Seconds to wait before scaling down

# Resource limits
cpu_request = "100m"
cpu_limit = "1000m"
memory_request = "128Mi"
memory_limit = "512Mi"

# Database settings (support environment variable interpolation)
mongodb_uri = "${MONGODB_URI}"
redis_url = "${REDIS_URL}"

# Authentication settings
jwt_secret_env = "JAC_JWT_SECRET" # Env var name containing JWT secret
jwt_algorithm = "HS256"
jwt_expiration_hours = 24

# Plugin metadata
depends_on = []
conflicts_with = []

[plugins.scale.logging]
level = "INFO"
file = ""

[plugins.scale.healthcheck]
enabled = true
path = "/health"
interval_seconds = 30
timeout_seconds = 5
failure_threshold = 3

[plugins.scale.ingress]
enabled = false
host = ""                         # e.g., "myapp.example.com"
tls_enabled = false
tls_secret_name = ""
annotations = {}

#-------------------------------------------------------------------------------
# jac-streamlit Plugin Configuration
# Streamlit integration for data visualization and dashboards
#-------------------------------------------------------------------------------

[plugins.streamlit]
# Page configuration
theme = "light"                   # "light" | "dark"
page_layout = "wide"              # "wide" | "centered"
page_icon = ""                    # Emoji or path to icon file
page_title = ""                   # Browser tab title
initial_sidebar_state = "auto"    # "auto" | "expanded" | "collapsed"

# Server settings
server_port = 8501
server_address = "localhost"
server_headless = true            # Run without opening browser

# Features
enable_xsrf_protection = true
enable_cors = false
enable_websocket_compression = true
max_upload_size = 200             # MB

# Plugin metadata
depends_on = []
conflicts_with = []

[plugins.streamlit.logging]
level = "INFO"
file = ""

[plugins.streamlit.theme_config]
# Custom theme colors (optional)
primaryColor = ""
backgroundColor = ""
secondaryBackgroundColor = ""
textColor = ""
font = ""                         # "sans serif" | "serif" | "monospace"

#===============================================================================
# ENVIRONMENT PROFILES
#===============================================================================

# Environment-specific configuration overrides
# Use with: jac run --env production

[environments.development]
# Development overrides
[environments.development.settings]
show_internal_stack_errs = true
all_warnings = true
config_hot_reload = true

[environments.development.serve]
reload = true
host = "127.0.0.1"

[environments.development.plugins.byllm]
log_prompts = true
log_responses = true
cache_enabled = false

[environments.development.plugins.scale]
auto_scale = false
min_replicas = 1
max_replicas = 1

[environments.staging]
# Staging overrides
[environments.staging.serve]
reload = false
host = "0.0.0.0"

[environments.staging.plugins.scale]
kubernetes_namespace = "staging"
auto_scale = true
min_replicas = 1
max_replicas = 3

[environments.production]
# Production overrides
[environments.production.settings]
show_internal_stack_errs = false
all_warnings = false
config_hot_reload = false

[environments.production.serve]
reload = false
host = "0.0.0.0"
cors_origins = ["https://myapp.example.com"]

[environments.production.plugins.byllm]
log_prompts = false
log_responses = false
cache_enabled = true
retry_attempts = 5

[environments.production.plugins.scale]
kubernetes_namespace = "production"
auto_scale = true
min_replicas = 3
max_replicas = 10
cpu_threshold = 70

#===============================================================================
# CUSTOM SCRIPTS
#===============================================================================

[scripts]
# Custom scripts (like npm scripts)
dev = "jac run main.jac --watch"
build = "jac build main.jac"
test = "jac test tests/"
lint = "jac format . --check"
deploy-staging = "jac scale --env staging"
deploy-prod = "jac scale --env production"
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
5. **Support `--env` flag** to load environment-specific overrides

### `jac config`

Manage and inspect configuration.

```bash
# Show current resolved configuration
jac config show

# Show specific section
jac config show plugins.byllm

# Show resolved value (with env var interpolation)
jac config resolve plugins.scale.mongodb_uri

# Validate configuration
jac config validate

# List all plugin configuration schemas
jac config plugins

# Show specific plugin schema
jac config plugins byllm

# Set a configuration value
jac config set plugins.byllm.temperature 0.5

# Generate JSON Schema for IDE support
jac config schema > jac-toml-schema.json

# Edit config interactively
jac config edit
```

### `jac workspace`

Manage multi-project workspaces.

```bash
# Initialize a workspace
jac workspace init

# List workspace members
jac workspace list

# Add a project to workspace
jac workspace add ./packages/my-plugin

# Run command across all workspace members
jac workspace run test

# Install dependencies for all members
jac workspace install
```

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

### Implementation

```python
# jaclang/project/interpolation.py

import os
import re
from typing import Any

ENV_VAR_PATTERN = re.compile(
    r'\$\{(?P<name>[A-Z_][A-Z0-9_]*)'
    r'(?:(?P<op>:[-?])(?P<value>[^}]*))?\}'
)

def interpolate_value(value: Any, context: dict = None) -> Any:
    """Interpolate environment variables in a value.

    Args:
        value: The value to interpolate (string, dict, or list)
        context: Optional context dict for additional variables

    Returns:
        The interpolated value

    Raises:
        ValueError: If required env var is not set
    """
    if isinstance(value, str):
        return _interpolate_string(value, context)
    elif isinstance(value, dict):
        return {k: interpolate_value(v, context) for k, v in value.items()}
    elif isinstance(value, list):
        return [interpolate_value(item, context) for item in value]
    return value

def _interpolate_string(text: str, context: dict = None) -> str:
    """Interpolate environment variables in a string."""
    def replace(match):
        name = match.group('name')
        op = match.group('op')
        default_or_msg = match.group('value')

        # Check context first, then environment
        if context and name in context:
            return str(context[name])

        env_value = os.environ.get(name)

        if env_value is not None:
            return env_value

        if op == ':-':
            # Default value
            return default_or_msg if default_or_msg else ''
        elif op == ':?':
            # Required with error message
            msg = default_or_msg or f"Environment variable {name} is not set"
            raise ValueError(msg)
        else:
            # Required (no operator)
            raise ValueError(f"Required environment variable {name} is not set")

    return ENV_VAR_PATTERN.sub(replace, text)

def validate_interpolation(config: dict) -> list[str]:
    """Validate that all required environment variables are set.

    Returns list of error messages for missing required variables.
    """
    errors = []

    def check_value(value: Any, path: str):
        if isinstance(value, str):
            for match in ENV_VAR_PATTERN.finditer(value):
                name = match.group('name')
                op = match.group('op')
                if op != ':-' and name not in os.environ:
                    errors.append(f"{path}: Missing required env var ${name}")
        elif isinstance(value, dict):
            for k, v in value.items():
                check_value(v, f"{path}.{k}")
        elif isinstance(value, list):
            for i, item in enumerate(value):
                check_value(item, f"{path}[{i}]")

    check_value(config, "jac.toml")
    return errors
```

### CLI Support

```bash
# Show resolved configuration with interpolated values
jac config resolve

# Validate all environment variables are set
jac config validate --check-env

# Show which env vars are required
jac config env-vars
# Output:
# Required:
#   MONGODB_URI (plugins.scale.mongodb_uri)
#   JAC_JWT_SECRET (plugins.scale.jwt_secret)
# Optional (with defaults):
#   DEBUG=false (plugins.scale.debug_mode)
#   LOG_LEVEL=INFO (plugins.scale.log_level)
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

### Implementation

```python
# jaclang/project/profiles.py

from typing import Any, Dict, Optional
from copy import deepcopy

def merge_configs(base: Dict[str, Any], override: Dict[str, Any]) -> Dict[str, Any]:
    """Deep merge override into base config."""
    result = deepcopy(base)

    for key, value in override.items():
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = merge_configs(result[key], value)
        else:
            result[key] = deepcopy(value)

    return result

def resolve_profile(
    config: Dict[str, Any],
    profile_name: Optional[str] = None
) -> Dict[str, Any]:
    """Resolve configuration with profile overrides.

    Args:
        config: Full parsed jac.toml config
        profile_name: Name of profile to apply (e.g., "production")

    Returns:
        Merged configuration with profile overrides applied
    """
    # Start with base config (excluding environments section)
    result = {k: v for k, v in config.items() if k != 'environments'}

    if not profile_name:
        return result

    environments = config.get('environments', {})

    if profile_name not in environments:
        raise ValueError(f"Unknown profile: {profile_name}")

    profile = environments[profile_name]

    # Handle inheritance
    if 'inherits' in profile:
        parent_name = profile['inherits']
        result = resolve_profile(config, parent_name)
        profile = {k: v for k, v in profile.items() if k != 'inherits'}

    # Merge profile overrides
    return merge_configs(result, profile)
```

---

## Workspace Support

Support for monorepos and multi-project setups using `jac-workspace.toml`.

### Workspace Configuration

```toml
# jac-workspace.toml (in repository root)

[workspace]
# Member projects (glob patterns supported)
members = [
    "packages/*",
    "apps/web",
    "apps/api",
    "plugins/jac-*",
]

# Exclude patterns
exclude = [
    "packages/deprecated-*",
]

# Shared settings for all members
[workspace.settings]
max_line_length = 100
filter_sym_builtins = true

# Shared dependencies (inherited by all members)
[workspace.dependencies]
jaclang = ">=0.9.3"

[workspace.dev-dependencies]
pytest = ">=8.0.0"

# Shared plugin configuration
[workspace.plugins.byllm]
default_model = "gpt-4"
cache_enabled = true
```

### Member Project Configuration

Individual `jac.toml` files can extend workspace settings:

```toml
# packages/my-plugin/jac.toml

[project]
name = "my-plugin"
version = "1.0.0"

# Inherit from workspace
extends = "workspace"  # Special keyword to inherit workspace settings

# Override specific settings
[settings]
max_line_length = 120  # Override workspace default

# Add project-specific dependencies
[dependencies]
requests = ">=2.28.0"
```

### Workspace Commands

```bash
# Initialize workspace
jac workspace init

# List all workspace members
jac workspace list
# Output:
# Workspace: my-monorepo
# Members:
#   - packages/core (jac-core@1.0.0)
#   - packages/utils (jac-utils@0.5.0)
#   - apps/web (web-app@2.0.0)

# Run command in all members
jac workspace run test
jac workspace run build

# Run command in specific members
jac workspace run test --filter "packages/*"

# Install all workspace dependencies
jac workspace install

# Add dependency to workspace
jac workspace add numpy --workspace  # Add to workspace.dependencies
jac workspace add pytest --dev       # Add to workspace.dev-dependencies

# Check workspace consistency
jac workspace check
# Verifies:
#   - All members have valid jac.toml
#   - No conflicting dependency versions
#   - All extends references are valid
```

### Workspace Discovery

```python
# jaclang/project/workspace.py

from pathlib import Path
from typing import Optional, List, Tuple
import tomllib
from glob import glob

WORKSPACE_FILE = "jac-workspace.toml"

def find_workspace_root(start: Path = None) -> Optional[Path]:
    """Find workspace root by looking for jac-workspace.toml."""
    if start is None:
        start = Path.cwd()

    current = start.resolve()

    while current != current.parent:
        if (current / WORKSPACE_FILE).exists():
            return current
        current = current.parent

    return None

def get_workspace_members(workspace_root: Path) -> List[Tuple[Path, dict]]:
    """Get all workspace member projects.

    Returns:
        List of (project_path, parsed_jac_toml) tuples
    """
    workspace_toml = workspace_root / WORKSPACE_FILE
    with open(workspace_toml, 'rb') as f:
        workspace_config = tomllib.load(f)

    members = []
    patterns = workspace_config.get('workspace', {}).get('members', [])
    excludes = workspace_config.get('workspace', {}).get('exclude', [])

    for pattern in patterns:
        for path in glob(str(workspace_root / pattern)):
            project_path = Path(path)
            jac_toml = project_path / 'jac.toml'

            if not jac_toml.exists():
                continue

            # Check exclusions
            rel_path = project_path.relative_to(workspace_root)
            if any(rel_path.match(exc) for exc in excludes):
                continue

            with open(jac_toml, 'rb') as f:
                project_config = tomllib.load(f)

            members.append((project_path, project_config))

    return members

def resolve_workspace_config(
    project_config: dict,
    workspace_config: dict
) -> dict:
    """Resolve project config with workspace inheritance."""
    if project_config.get('extends') != 'workspace':
        return project_config

    # Start with workspace settings
    result = {}
    workspace_settings = workspace_config.get('workspace', {})

    for key in ['settings', 'dependencies', 'dev-dependencies', 'plugins']:
        if key in workspace_settings:
            result[key] = deepcopy(workspace_settings[key])

    # Merge project-specific settings
    for key, value in project_config.items():
        if key == 'extends':
            continue
        if key in result and isinstance(result[key], dict):
            result[key] = merge_configs(result[key], value)
        else:
            result[key] = value

    return result
```

---

## Configuration Inheritance

Projects can inherit configuration from parent files.

### Syntax

```toml
# Inherit from parent directory's jac.toml
extends = "../jac.toml"

# Inherit from user-level shared config
extends = "~/.jaclang/shared.toml"

# Inherit from workspace
extends = "workspace"

# Multiple inheritance (processed in order)
extends = ["~/.jaclang/base.toml", "../common.toml"]
```

### Resolution Order

1. Base file(s) specified in `extends` (in order)
2. Current `jac.toml` values (override inherited values)
3. Environment profile overrides (if `--env` specified)
4. Environment variable overrides
5. CLI argument overrides

---

## Hot Reload Configuration

Support automatic configuration reloading during development.

### Enable Hot Reload

```toml
[settings]
config_hot_reload = true           # Enable hot reload
config_watch_interval = 1.0        # Check every 1 second
config_watch_debounce = 0.5        # Wait for file to stabilize
```

### Plugin Hook for Config Changes

```python
# In JacRuntimeInterface (runtime.py)

@staticmethod
@hookspec
def on_config_changed(
    old_config: dict[str, Any],
    new_config: dict[str, Any],
    changed_keys: list[str]
) -> None:
    """Called when configuration is hot-reloaded.

    Args:
        old_config: Previous configuration values
        new_config: New configuration values
        changed_keys: List of dot-notation keys that changed
                     (e.g., ["plugins.byllm.temperature", "serve.port"])
    """
    pass
```

### Implementation

```python
# jaclang/project/watcher.py

import threading
import time
from pathlib import Path
from typing import Callable, Optional
import hashlib

class ConfigWatcher:
    """Watch jac.toml for changes and trigger reloads."""

    def __init__(
        self,
        config_path: Path,
        on_change: Callable[[dict, dict, list], None],
        interval: float = 1.0,
        debounce: float = 0.5
    ):
        self.config_path = config_path
        self.on_change = on_change
        self.interval = interval
        self.debounce = debounce
        self._stop = threading.Event()
        self._thread: Optional[threading.Thread] = None
        self._last_hash: Optional[str] = None
        self._last_change_time: float = 0

    def start(self):
        """Start watching for config changes."""
        self._last_hash = self._compute_hash()
        self._thread = threading.Thread(target=self._watch_loop, daemon=True)
        self._thread.start()

    def stop(self):
        """Stop watching."""
        self._stop.set()
        if self._thread:
            self._thread.join()

    def _compute_hash(self) -> str:
        """Compute hash of config file."""
        if not self.config_path.exists():
            return ""
        content = self.config_path.read_bytes()
        return hashlib.sha256(content).hexdigest()

    def _watch_loop(self):
        """Main watch loop."""
        while not self._stop.is_set():
            time.sleep(self.interval)

            current_hash = self._compute_hash()
            if current_hash != self._last_hash:
                # File changed, wait for debounce
                now = time.time()
                if now - self._last_change_time < self.debounce:
                    continue

                self._last_change_time = now
                self._last_hash = current_hash

                # Reload and notify
                try:
                    self._reload_and_notify()
                except Exception as e:
                    print(f"Error reloading config: {e}")

    def _reload_and_notify(self):
        """Reload config and notify listeners."""
        from jaclang.project.config import JacConfig, get_config

        old_config = get_config()._to_dict()
        new_config_obj = JacConfig.load(self.config_path)
        new_config = new_config_obj._to_dict()

        # Find changed keys
        changed_keys = self._find_changed_keys(old_config, new_config)

        if changed_keys:
            # Update global config
            from jaclang.project.config import _set_config
            _set_config(new_config_obj)

            # Notify via hook
            from jaclang.pycore.runtime import plugin_manager
            plugin_manager.hook.on_config_changed(
                old_config=old_config,
                new_config=new_config,
                changed_keys=changed_keys
            )

    def _find_changed_keys(
        self,
        old: dict,
        new: dict,
        prefix: str = ""
    ) -> list[str]:
        """Find all keys that changed between two configs."""
        changed = []
        all_keys = set(old.keys()) | set(new.keys())

        for key in all_keys:
            full_key = f"{prefix}.{key}" if prefix else key
            old_val = old.get(key)
            new_val = new.get(key)

            if old_val != new_val:
                if isinstance(old_val, dict) and isinstance(new_val, dict):
                    changed.extend(self._find_changed_keys(old_val, new_val, full_key))
                else:
                    changed.append(full_key)

        return changed
```

---

## JSON Schema Generation

Generate JSON Schema for IDE support (autocomplete, validation).

### CLI Command

```bash
# Generate full schema
jac config schema > jac-toml-schema.json

# Generate schema for specific section
jac config schema --section plugins.byllm

# Generate schema including all installed plugins
jac config schema --include-plugins
```

### Schema Structure

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "https://jac-lang.org/schemas/jac-toml.json",
  "title": "Jac Project Configuration",
  "description": "Schema for jac.toml configuration file",
  "type": "object",
  "properties": {
    "project": {
      "type": "object",
      "properties": {
        "name": {
          "type": "string",
          "description": "Project name"
        },
        "version": {
          "type": "string",
          "pattern": "^\\d+\\.\\d+\\.\\d+",
          "description": "Project version (semver)"
        }
      }
    },
    "plugins": {
      "type": "object",
      "properties": {
        "byllm": {
          "$ref": "#/definitions/plugins/byllm"
        }
      }
    }
  },
  "definitions": {
    "plugins": {
      "byllm": {
        "type": "object",
        "properties": {
          "default_model": {
            "type": "string",
            "default": "gpt-4",
            "description": "Default LLM model"
          },
          "temperature": {
            "type": "number",
            "minimum": 0,
            "maximum": 2,
            "default": 0.7,
            "description": "Temperature for LLM calls"
          }
        }
      }
    }
  }
}
```

### Implementation

```python
# jaclang/project/schema.py

from typing import Any, Dict
from jaclang.pycore.runtime import plugin_manager

def generate_json_schema(include_plugins: bool = True) -> Dict[str, Any]:
    """Generate JSON Schema for jac.toml."""
    schema = {
        "$schema": "http://json-schema.org/draft-07/schema#",
        "$id": "https://jac-lang.org/schemas/jac-toml.json",
        "title": "Jac Project Configuration",
        "type": "object",
        "properties": {},
        "definitions": {"plugins": {}}
    }

    # Add core sections
    schema["properties"]["project"] = _project_schema()
    schema["properties"]["settings"] = _settings_schema()
    schema["properties"]["environment"] = _environment_schema()
    schema["properties"]["dependencies"] = _dependencies_schema()
    schema["properties"]["plugins"] = {"type": "object", "properties": {}}

    # Add plugin schemas
    if include_plugins:
        results = plugin_manager.hook.get_config_schema()
        for plugin_schema in results:
            if plugin_schema:
                section_name = plugin_schema.get("section_name")
                if section_name:
                    json_schema = _convert_plugin_schema(plugin_schema)
                    schema["definitions"]["plugins"][section_name] = json_schema
                    schema["properties"]["plugins"]["properties"][section_name] = {
                        "$ref": f"#/definitions/plugins/{section_name}"
                    }

    return schema

def _convert_plugin_schema(plugin_schema: dict) -> dict:
    """Convert plugin config schema to JSON Schema format."""
    properties = {}
    required = []

    for opt_name, opt_spec in plugin_schema.get("options", {}).items():
        prop = {
            "description": opt_spec.get("description", "")
        }

        # Map types
        type_map = {
            "str": "string",
            "int": "integer",
            "float": "number",
            "bool": "boolean",
            "list": "array",
            "dict": "object"
        }
        prop["type"] = type_map.get(opt_spec.get("type", "str"), "string")

        if "default" in opt_spec:
            prop["default"] = opt_spec["default"]

        if "choices" in opt_spec:
            prop["enum"] = opt_spec["choices"]

        if opt_spec.get("required", False):
            required.append(opt_name)

        properties[opt_name] = prop

    result = {"type": "object", "properties": properties}
    if required:
        result["required"] = required

    return result
```

### VS Code Integration

Create `.vscode/settings.json` for schema association:

```json
{
  "json.schemas": [
    {
      "fileMatch": ["jac.toml"],
      "url": "./jac-toml-schema.json"
    }
  ],
  "evenBetterToml.schema.associations": {
    "jac.toml": "./jac-toml-schema.json"
  }
}
```

---

## Plugin Dependency and Metadata System

Plugins can declare dependencies on other plugins and provide metadata.

### Plugin Metadata Hook

```python
# jaclang/pycore/runtime.py - Add to JacRuntimeInterface

@staticmethod
@hookspec
def get_plugin_metadata() -> dict[str, Any] | None:
    """Return plugin metadata including dependencies.

    Returns:
        {
            "name": "byllm",
            "version": "0.4.8",
            "description": "LLM integration for Jac",
            "author": "Jaseci Team",
            "homepage": "https://github.com/Jaseci-Labs/jaseci",

            # Python package dependencies
            "requires": ["litellm>=1.75.5", "loguru>=0.7.2"],

            # Jac plugin dependencies
            "plugin_depends_on": [],  # e.g., ["client"] if depends on jac-client

            # Plugins that conflict with this one
            "conflicts_with": [],

            # Minimum jaclang version
            "jac_version": ">=0.9.3",

            # Configuration schema version (for migrations)
            "config_schema_version": "1.0"
        }
    """
    return None
```

### Plugin Dependency Resolution

```python
# jaclang/project/plugin_deps.py

from typing import Dict, List, Set
from dataclasses import dataclass

@dataclass
class PluginInfo:
    name: str
    version: str
    depends_on: List[str]
    conflicts_with: List[str]

def resolve_plugin_load_order(
    plugins: Dict[str, PluginInfo],
    enabled: List[str]
) -> List[str]:
    """Resolve plugin load order based on dependencies.

    Args:
        plugins: Dict mapping plugin name to PluginInfo
        enabled: List of enabled plugin names

    Returns:
        Ordered list of plugin names to load

    Raises:
        ValueError: If circular dependency or conflict detected
    """
    # Build dependency graph
    graph: Dict[str, Set[str]] = {}
    for name in enabled:
        if name in plugins:
            deps = set(plugins[name].depends_on) & set(enabled)
            graph[name] = deps
        else:
            graph[name] = set()

    # Topological sort
    result = []
    visited = set()
    temp_visited = set()

    def visit(node: str):
        if node in temp_visited:
            raise ValueError(f"Circular dependency detected involving {node}")
        if node in visited:
            return

        temp_visited.add(node)
        for dep in graph.get(node, []):
            visit(dep)
        temp_visited.remove(node)
        visited.add(node)
        result.append(node)

    for name in enabled:
        visit(name)

    # Check for conflicts
    for name in result:
        if name in plugins:
            for conflict in plugins[name].conflicts_with:
                if conflict in result:
                    raise ValueError(
                        f"Plugin {name} conflicts with {conflict}"
                    )

    return result
```

### CLI Commands

```bash
# Show plugin info
jac plugins info byllm
# Output:
# Plugin: byllm (v0.4.8)
# Description: LLM integration for Jac
# Requires: litellm>=1.75.5, loguru>=0.7.2
# Plugin Dependencies: none
# Conflicts With: none
# Config Schema Version: 1.0

# List all plugins
jac plugins list
# Output:
# Installed Plugins:
#   ✓ byllm (0.4.8) - enabled
#   ✓ client (0.2.3) - enabled
#   ✗ scale (0.1.0) - disabled
#   ✓ streamlit (0.0.5) - enabled

# Show plugin load order
jac plugins order

# Check plugin compatibility
jac plugins check
```

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

### Task 8: Environment Variable Interpolation

- [ ] Create `jaclang/project/interpolation.py` module
- [ ] Implement `${VAR}` syntax parsing and resolution
- [ ] Implement `${VAR:-default}` optional syntax
- [ ] Implement `${VAR:?error}` required with message syntax
- [ ] Add recursive interpolation for nested dicts/lists
- [ ] Add `jac config resolve` command to show resolved values
- [ ] Add `jac config env-vars` command to list required env vars
- [ ] Add `--check-env` flag to `jac config validate`
- [ ] Write unit tests for all interpolation patterns
- [ ] Document environment variable syntax in user docs

### Task 9: Configuration Profiles (Environments)

- [ ] Create `jaclang/project/profiles.py` module
- [ ] Implement `[environments.<name>]` section parsing
- [ ] Implement deep config merging for profile overrides
- [ ] Implement profile inheritance (`inherits` key)
- [ ] Add `--env` flag to all CLI commands
- [ ] Support `JAC_ENV` environment variable for profile selection
- [ ] Add `default_profile` setting in `[environment]` section
- [ ] Validate profile names and inheritance chains
- [ ] Write unit tests for profile resolution
- [ ] Document profile system in user docs

### Task 10: Workspace Support

- [ ] Create `jaclang/project/workspace.py` module
- [ ] Implement `jac-workspace.toml` file format
- [ ] Implement workspace root discovery
- [ ] Implement glob pattern matching for workspace members
- [ ] Implement workspace config inheritance (`extends = "workspace"`)
- [ ] Add `jac workspace init` command
- [ ] Add `jac workspace list` command
- [ ] Add `jac workspace run` command (execute across members)
- [ ] Add `jac workspace install` command
- [ ] Add `jac workspace add` command
- [ ] Add `jac workspace check` command (consistency validation)
- [ ] Support `--filter` flag for selective member operations
- [ ] Write unit tests for workspace operations
- [ ] Document workspace setup and usage

### Task 11: Configuration Inheritance

- [ ] Implement `extends` key parsing in `jac.toml`
- [ ] Support relative path inheritance (`extends = "../jac.toml"`)
- [ ] Support absolute path inheritance (`extends = "~/.jaclang/shared.toml"`)
- [ ] Support workspace inheritance (`extends = "workspace"`)
- [ ] Support multiple inheritance (`extends = ["base.toml", "common.toml"]`)
- [ ] Implement inheritance chain resolution and cycle detection
- [ ] Define clear resolution order documentation
- [ ] Write unit tests for inheritance scenarios

### Task 12: Hot Reload Configuration

- [ ] Create `jaclang/project/watcher.py` module
- [ ] Implement `ConfigWatcher` class with file monitoring
- [ ] Add `config_hot_reload` setting to `[settings]`
- [ ] Add `config_watch_interval` setting
- [ ] Add `config_watch_debounce` setting
- [ ] Add `on_config_changed` hook to `JacRuntimeInterface`
- [ ] Implement change detection and diff calculation
- [ ] Notify plugins of configuration changes
- [ ] Handle reload errors gracefully
- [ ] Write unit tests for watcher functionality
- [ ] Document hot reload feature and limitations

### Task 13: JSON Schema Generation

- [ ] Create `jaclang/project/schema.py` module
- [ ] Implement core section schemas (project, settings, environment, etc.)
- [ ] Implement plugin schema collection from `get_config_schema` hook
- [ ] Implement schema conversion from plugin format to JSON Schema
- [ ] Add `jac config schema` command
- [ ] Add `--section` flag for partial schema generation
- [ ] Add `--include-plugins` flag (default true)
- [ ] Generate VS Code settings.json snippet for schema association
- [ ] Publish schema to jac-lang.org/schemas
- [ ] Write unit tests for schema generation
- [ ] Document IDE integration setup

### Task 14: Plugin Metadata and Dependencies

- [ ] Add `get_plugin_metadata` hook to `JacRuntimeInterface`
- [ ] Create `jaclang/project/plugin_deps.py` module
- [ ] Implement plugin dependency graph construction
- [ ] Implement topological sort for load order
- [ ] Implement conflict detection
- [ ] Add `jac plugins list` command
- [ ] Add `jac plugins info <name>` command
- [ ] Add `jac plugins order` command
- [ ] Add `jac plugins check` command
- [ ] Add `depends_on` and `conflicts_with` to plugin TOML config
- [ ] Update all existing plugins with metadata hooks
- [ ] Write unit tests for dependency resolution
- [ ] Document plugin dependency system for authors

### Task 15: Update Existing Plugins

- [ ] **jac-byllm**: Add `get_config_schema()` hook implementation
- [ ] **jac-byllm**: Add `get_plugin_metadata()` hook implementation
- [ ] **jac-byllm**: Add `on_config_loaded()` hook implementation
- [ ] **jac-byllm**: Add `validate_config()` hook implementation
- [ ] **jac-byllm**: Update to load config from TOML
- [ ] **jac-client**: Add `get_config_schema()` hook implementation
- [ ] **jac-client**: Add `get_plugin_metadata()` hook implementation
- [ ] **jac-client**: Update to load config from TOML (replace `config.json`)
- [ ] **jac-scale**: Add `get_config_schema()` hook implementation
- [ ] **jac-scale**: Add `get_plugin_metadata()` hook implementation
- [ ] **jac-scale**: Update to load config from TOML (replace `.env`)
- [ ] **jac-streamlit**: Add `get_config_schema()` hook implementation
- [ ] **jac-streamlit**: Add `get_plugin_metadata()` hook implementation
- [ ] Write integration tests for each plugin's config loading

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

### New Files - Core Project Module

| File | Description |
|------|-------------|
| `jaclang/project/__init__.py` | Module exports and public API |
| `jaclang/project/config.py` | `JacConfig` class - main configuration |
| `jaclang/project/toml_parser.py` | TOML parsing and schema validation |
| `jaclang/project/environment.py` | `JacEnvironment` class - venv management |
| `jaclang/project/dependencies.py` | Dependency resolution and installation |
| `jaclang/project/lockfile.py` | `jac.lock` file management |
| `jaclang/project/discovery.py` | Project root and workspace discovery |
| `jaclang/project/interpolation.py` | Environment variable interpolation |
| `jaclang/project/profiles.py` | Configuration profiles (dev/staging/prod) |
| `jaclang/project/workspace.py` | Workspace support (`jac-workspace.toml`) |
| `jaclang/project/watcher.py` | Config file hot reload watcher |
| `jaclang/project/schema.py` | JSON Schema generation |
| `jaclang/project/plugin_config.py` | `PluginConfigManager` class |
| `jaclang/project/plugin_deps.py` | Plugin dependency resolution |
| `jaclang/project/templates/` | Project templates directory |
| `jaclang/project/templates/default/` | Default project template |
| `jaclang/project/templates/web-app/` | Web application template |
| `jaclang/project/templates/library/` | Library/plugin template |

### New Files - CLI Commands

| File | Description |
|------|-------------|
| `jaclang/cli/commands/__init__.py` | Commands module exports |
| `jaclang/cli/commands/init.py` | `jac init` implementation |
| `jaclang/cli/commands/install.py` | `jac install` implementation |
| `jaclang/cli/commands/env.py` | `jac env` implementation |
| `jaclang/cli/commands/add.py` | `jac add` implementation |
| `jaclang/cli/commands/remove.py` | `jac remove` implementation |
| `jaclang/cli/commands/script.py` | `jac script` implementation |
| `jaclang/cli/commands/config.py` | `jac config` implementation |
| `jaclang/cli/commands/workspace.py` | `jac workspace` implementation |
| `jaclang/cli/commands/plugins.py` | `jac plugins` implementation |

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
| `schemas/jac-workspace-schema.json` | JSON Schema for workspace files |

### Modified Files

| File | Changes |
|------|---------|
| `jaclang/cli/cli.jac` | Add new commands, project detection, `--env` flag |
| `jaclang/pycore/settings.py` | Deprecate, wrap `JacConfig` (Phase 2) |
| `jaclang/pycore/runtime.py` | Add new plugin hooks (`get_config_schema`, `get_plugin_metadata`, `on_config_loaded`, `validate_config`, `on_config_changed`) |
| `jaclang/__init__.py` | Initialize project config, load plugin configs |
| `jaclang/cli/cmdreg.jac` | Register new commands |
| `pyproject.toml` | Add tomllib dependency (stdlib in 3.11+) |

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

### Removed Files (Phase 3)

| File | Replacement |
|------|-------------|
| `jaclang/pycore/settings.py` | `jaclang/project/config.py` |
| `~/.jaclang/config.ini` | `jac.toml` (project-level) |

### New Project Files (Generated by `jac init`)

| File | Description |
|------|-------------|
| `jac.toml` | Project configuration |
| `jac.lock` | Dependency lock file |
| `.jac_env/` | Virtual environment directory |
| `jac-workspace.toml` | Workspace configuration (monorepos only) |

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

5. **Shell Integration**: Should `jac env activate` modify the current shell, or just print instructions?

   **Decision: PRINT INSTRUCTIONS** - Following the pattern of `poetry shell` and `pipenv shell`:
   ```bash
   $ jac env activate
   # To activate the environment, run:
   source /path/to/project/.jac_env/bin/activate

   # Or use this shortcut:
   eval $(jac env activate --shell)
   ```
   Direct shell modification is not possible from a subprocess.

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
1. ✅ New projects can be created with `jac init`
2. ✅ Dependencies managed via `jac.toml` and `jac install`
3. ✅ Virtual environment automatically created and managed
4. ✅ All existing `jac` commands work with project context
5. ✅ Settings from `jac.toml` properly loaded and applied
6. ✅ Legacy `settings.py` completely removed

### Plugin System
7. ✅ Plugins can register configuration schemas via hooks
8. ✅ Plugin configurations loaded from `[plugins.<name>]` sections
9. ✅ Plugin configuration validation with helpful error messages
10. ✅ Plugin dependency resolution and load ordering

### Developer Experience
11. ✅ Environment variable interpolation for secrets (`${VAR}`)
12. ✅ Configuration profiles for dev/staging/production (`--env`)
13. ✅ Workspace support for monorepos (`jac-workspace.toml`)
14. ✅ Configuration inheritance (`extends` key)
15. ✅ Hot reload during development (`config_hot_reload`)
16. ✅ JSON Schema generation for IDE support

### Documentation & Testing
17. ✅ Plugin author documentation for config hooks
18. ✅ User documentation for `jac.toml`
19. ✅ Comprehensive test coverage

---

## Priority Matrix

| Priority | Feature | Complexity | Impact |
|----------|---------|------------|--------|
| **P0 - Critical** | Core TOML parsing and JacConfig | Medium | High |
| **P0 - Critical** | Plugin config hook system | Medium | High |
| **P0 - Critical** | Basic CLI commands (init, install, env) | Medium | High |
| **P1 - High** | Environment variable interpolation | Low | High |
| **P1 - High** | Update existing plugins with schemas | Medium | High |
| **P2 - Medium** | Configuration profiles | Medium | Medium |
| **P2 - Medium** | Workspace support | High | Medium |
| **P2 - Medium** | JSON Schema generation | Low | Medium |
| **P3 - Low** | Configuration inheritance | Medium | Low |
| **P3 - Low** | Hot reload | Medium | Low |
| **P3 - Low** | Plugin dependencies | Medium | Low |

---

## Recommended Implementation Order

### Phase 1: Foundation (Weeks 1-2)
1. Task 1: Core Infrastructure
2. Task 2: Virtual Environment Management
3. Task 8: Environment Variable Interpolation (basic)

### Phase 2: CLI & Integration (Weeks 3-4)
4. Task 3: New CLI Commands
5. Task 4: Integrate with Existing Commands
6. Task 6: Plugin Configuration System

### Phase 3: Plugin Updates (Weeks 5-6)
7. Task 15: Update Existing Plugins
8. Task 5: Remove Legacy Settings

### Phase 4: Advanced Features (Weeks 7-8)
9. Task 9: Configuration Profiles
10. Task 10: Workspace Support
11. Task 13: JSON Schema Generation

### Phase 5: Polish (Week 9+)
12. Task 11: Configuration Inheritance
13. Task 12: Hot Reload Configuration
14. Task 14: Plugin Metadata and Dependencies
15. Task 7: Documentation and Testing
