# Jac Project Configuration - Simplified Architecture

## Overview

This document outlines a streamlined approach to introduce `jac.toml` as the central project configuration file. This is a **clean break** from the legacy `settings.py` and `~/.jaclang/config.ini` system.

**Key Priorities:**

1. Virtual environment management (`.jac_env/`)
2. Unified plugin configuration (all plugins configured via `jac.toml`)
3. Complete replacement of `settings.py`
4. Removal of CLI flags for settings (too many to expose)
5. **Cached compilation** - Pre-compiled JacProgram stored in `.jac_env/` for fast startup

**Implementation Language:** Maximum Jac (~735 lines), Python bootstrap with cache loading (~150 lines).

---

## Bootstrap Architecture

### The Bootstrap Problem

Some settings must be loaded **before** the Jac compiler runs. This creates a chicken-and-egg problem: we can't load settings from Jac code if those settings affect how Jac code is compiled.

### Settings Classification

| Setting | When Needed | Location |
|---------|-------------|----------|
| `ignore_test_annex` | Compile-time | Python bootstrap |
| `pyfile_raise` | Compile-time | Python bootstrap |
| `pyfile_raise_full` | Compile-time | Python bootstrap |
| `all_warnings` | Compile-time | Python bootstrap |
| `max_line_length` | Compile-time | Python bootstrap |
| `pass_timer` | Compile-time | Python bootstrap |
| `print_py_raised_ast` | Compile-time | Python bootstrap |
| `filter_sym_builtins` | Runtime only | Jac |
| `ast_symbol_info_detailed` | Runtime only | Jac |
| `show_internal_stack_errs` | Runtime only | Jac |
| `lsp_debug` | Runtime only | Jac |

### Bootstrap Sequence

```
1. Python: find_jac_toml() - walk up directories
2. Python: Parse TOML (stdlib tomllib / tomli)
3. Python: Extract [settings.compiler] + [settings.debug] → BootstrapSettings
4. Python: Check for cached JacProgram in .jac_env/cache/
   └─ If valid cache: Load pickled .jir → SKIP compilation entirely
   └─ If no cache: Continue to step 5
5. Python: Initialize compiler with bootstrap settings (only if cache miss)
6. Jac: Load full JacConfig (plugins, runtime settings, profiles)
7. Jac: Handle CLI commands, venv management, cache building, etc.
```

**Key optimization:** Cache loading happens in Python BEFORE any Jac infrastructure loads. On cache hit, we skip compilation entirely and go straight to execution.

### Python Bootstrap with Cache Loading (`jaclang/pycore/bootstrap_config.py`)

```python
"""Bootstrap configuration with JacProgram cache loading.

This replaces settings.py with a ~150 line implementation that:
1. Discovers jac.toml by walking up directories
2. Parses bootstrap-critical settings
3. Loads cached JacProgram if available (BEFORE any Jac code runs)
4. Provides fast startup by skipping compilation on cache hit

Everything else (plugins, runtime settings, profiles) is handled in Jac.
"""

import hashlib
import json
import pickle
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from jaclang.pycore.program import JacProgram

# Python 3.11+ has tomllib, older versions need tomli
if sys.version_info >= (3, 11):
    import tomllib
else:
    try:
        import tomli as tomllib
    except ImportError:
        tomllib = None  # Will use defaults


@dataclass
class BootstrapSettings:
    """Settings needed before Jac compiler runs (~7 settings)."""

    # Compiler settings
    ignore_test_annex: bool = False
    pyfile_raise: bool = False
    pyfile_raise_full: bool = False
    all_warnings: bool = False

    # Formatter (runs as compiler pass)
    max_line_length: int = 88

    # Debug (needed during compilation)
    pass_timer: bool = False
    print_py_raised_ast: bool = False


@dataclass
class BootstrapConfig:
    """Minimal config for bootstrap phase."""

    settings: BootstrapSettings = field(default_factory=BootstrapSettings)
    project_root: Path | None = None
    toml_path: Path | None = None
    env_dir: str = ".jac_env"
    cache_enabled: bool = True
    _raw_toml: dict = field(default_factory=dict)  # For config hash


def find_jac_toml(start: Path | None = None) -> Path | None:
    """Walk up directories to find jac.toml."""
    current = (start or Path.cwd()).resolve()
    while current != current.parent:
        toml_path = current / "jac.toml"
        if toml_path.exists():
            return toml_path
        current = current.parent
    return None


def load_bootstrap() -> BootstrapConfig:
    """Load bootstrap configuration from jac.toml."""
    config = BootstrapConfig()

    toml_path = find_jac_toml()
    if toml_path is None or tomllib is None:
        return config

    config.toml_path = toml_path
    config.project_root = toml_path.parent

    try:
        with open(toml_path, "rb") as f:
            raw = tomllib.load(f)
        config._raw_toml = raw
    except Exception:
        return config

    # Extract environment config
    if "environment" in raw:
        config.env_dir = raw["environment"].get("env_dir", ".jac_env")

    # Extract cache config
    if "cache" in raw:
        config.cache_enabled = raw["cache"].get("enabled", True)

    # Extract bootstrap settings
    if "settings" in raw:
        s = raw["settings"]
        config.settings.max_line_length = s.get("max_line_length", 88)
        config.settings.all_warnings = s.get("alerts", {}).get("all_warnings", False)

        if "compiler" in s:
            c = s["compiler"]
            config.settings.ignore_test_annex = c.get("ignore_test_annex", False)
            config.settings.pyfile_raise = c.get("pyfile_raise", False)
            config.settings.pyfile_raise_full = c.get("pyfile_raise_full", False)

        if "debug" in s:
            d = s["debug"]
            config.settings.pass_timer = d.get("pass_timer", False)
            config.settings.print_py_raised_ast = d.get("print_py_raised_ast", False)

    return config


def get_config_hash(config: BootstrapConfig) -> str:
    """Generate hash of settings that affect compilation."""
    data = {
        "max_line_length": config.settings.max_line_length,
        "ignore_test_annex": config.settings.ignore_test_annex,
        "pyfile_raise": config.settings.pyfile_raise,
        "all_warnings": config.settings.all_warnings,
        "dependencies": config._raw_toml.get("dependencies", {}),
    }
    content = json.dumps(data, sort_keys=True)
    return hashlib.sha256(content.encode()).hexdigest()[:16]


def get_cache_path(config: BootstrapConfig, source: Path) -> Path:
    """Get the .jir cache path for a source file."""
    if config.project_root is None:
        return source.with_suffix(".jir")
    rel = source.relative_to(config.project_root)
    return config.project_root / config.env_dir / "cache" / rel.with_suffix(".jir")


def get_meta_path(jir_path: Path) -> Path:
    """Get the .jir.meta path for a cache file."""
    return jir_path.with_suffix(".jir.meta")


def is_cache_valid(
    config: BootstrapConfig, source: Path, jac_version: str
) -> bool:
    """Check if cached JacProgram is still valid."""
    if not config.cache_enabled or config.project_root is None:
        return False

    jir_path = get_cache_path(config, source)
    meta_path = get_meta_path(jir_path)

    if not jir_path.exists() or not meta_path.exists():
        return False

    try:
        with open(meta_path, "r") as f:
            meta = json.load(f)

        # Check Jac version
        if meta.get("jac_version") != jac_version:
            return False

        # Check config hash
        if meta.get("config_hash") != get_config_hash(config):
            return False

        # Check source file mtimes
        for src_path, src_info in meta.get("sources", {}).items():
            src = config.project_root / src_path
            if not src.exists():
                return False
            if src.stat().st_mtime > src_info.get("mtime", 0):
                return False

        return True
    except Exception:
        return False


def load_cached_program(
    config: BootstrapConfig, source: Path, jac_version: str
) -> "JacProgram | None":
    """Load cached JacProgram if valid, returns None if cache miss.

    This is called BEFORE any Jac code runs, enabling fastest possible startup.
    """
    if not is_cache_valid(config, source, jac_version):
        return None

    jir_path = get_cache_path(config, source)
    try:
        with open(jir_path, "rb") as f:
            return pickle.load(f)
    except Exception:
        return None


def save_cached_program(
    config: BootstrapConfig,
    source: Path,
    program: "JacProgram",
    sources: dict[str, Path],
    jac_version: str,
) -> None:
    """Save compiled JacProgram to cache."""
    if not config.cache_enabled or config.project_root is None:
        return

    jir_path = get_cache_path(config, source)
    meta_path = get_meta_path(jir_path)

    # Ensure cache directory exists
    jir_path.parent.mkdir(parents=True, exist_ok=True)

    # Save pickled program
    try:
        with open(jir_path, "wb") as f:
            pickle.dump(program, f)

        # Build source info
        sources_info = {}
        for name, path in sources.items():
            rel_path = path.relative_to(config.project_root)
            sources_info[str(rel_path)] = {
                "mtime": path.stat().st_mtime,
            }

        # Save metadata
        from datetime import datetime
        meta = {
            "jac_version": jac_version,
            "created_at": datetime.now().isoformat(),
            "config_hash": get_config_hash(config),
            "sources": sources_info,
        }

        with open(meta_path, "w") as f:
            json.dump(meta, f, indent=2)
    except Exception:
        # Cache save failure is non-fatal
        pass


# Global instance - replaces `settings` singleton
bootstrap = load_bootstrap()

__all__ = [
    "bootstrap",
    "BootstrapSettings",
    "BootstrapConfig",
    "find_jac_toml",
    "load_cached_program",
    "save_cached_program",
    "is_cache_valid",
    "get_cache_path",
]
```

---

## Cached Compilation (JacProgram Cache)

### Overview

To dramatically speed up `jac run` and other commands, the project system caches the compiled `JacProgram` as a pickled `.jir` file in the `.jac_env/` directory. This is similar to how `jac build` works, but integrated into the project workflow.

### Cache Location

```
my-project/
├── jac.toml
├── main.jac
├── src/
│   └── *.jac
└── .jac_env/
    ├── bin/
    ├── lib/
    └── cache/
        ├── main.jir              # Cached JacProgram for main.jac
        ├── main.jir.meta         # Metadata (timestamps, hashes)
        └── modules/
            └── src/
                └── *.jir         # Cached modules
```

### Cache Invalidation

The cache is invalidated when:

1. Any `.jac` source file is modified (mtime check)
2. `jac.toml` is modified
3. Dependencies change (hash of `[dependencies]` section)
4. Jac version changes

### Cache Metadata (`.jir.meta`)

```json
{
  "jac_version": "0.9.3",
  "created_at": "2024-01-15T10:30:00Z",
  "source_hash": "sha256:...",
  "config_hash": "sha256:...",
  "dependencies_hash": "sha256:...",
  "sources": {
    "main.jac": {"mtime": 1705312200, "hash": "sha256:..."},
    "src/utils.jac": {"mtime": 1705312100, "hash": "sha256:..."}
  }
}
```

### CLI Behavior

```bash
# First run - compiles and caches
jac run main.jac
# → Compiles main.jac
# → Saves to .jac_env/cache/main.jir
# → Executes

# Subsequent runs - loads from cache (fast!)
jac run main.jac
# → Checks cache validity
# → Loads .jac_env/cache/main.jir
# → Executes (skips compilation)

# Force recompile
jac run main.jac --no-cache
# → Ignores cache, recompiles

# Explicit cache management
jac cache build              # Build cache for entry_point
jac cache build --all        # Build cache for all .jac files
jac cache clear              # Clear all cached .jir files
jac cache status             # Show cache status
```

### Implementation

Cache **loading** is in Python (`bootstrap_config.py`) for maximum speed.
Cache **management** (build, clear, status) is in Jac (`cache.jac`).

#### Cache Management (`jaclang/project/cache.jac`)

```jac
"""JacProgram cache management - build, clear, status.

Note: Cache LOADING is handled in Python (bootstrap_config.py) for fastest startup.
This module handles cache building and management commands.
"""
import shutil;
import from pathlib { Path }

import from jaclang.pycore.program { JacProgram }
import from jaclang.pycore.bootstrap_config {
    bootstrap,
    get_cache_path,
    save_cached_program
}
import from jaclang { version as jac_version }

"""Cache management utilities."""
obj CacheManager {
    has project_root: Path,
        env_dir: str = ".jac_env";

    """Get the cache directory path."""
    def cache_path() -> Path {
        return self.project_root / self.env_dir / "cache";
    }

    """Build cache for a single source file."""
    def build_single(source: Path) -> bool {
        """Compile and cache a source file. Returns True on success."""
        program = JacProgram();
        program.compile(file_path=str(source));

        if program.errors_had {
            return False;
        }

        # Collect sources (main + imports)
        sources = {"main": source};
        # TODO: Extract imported sources from program IR

        save_cached_program(
            config=bootstrap,
            source=source,
            program=program,
            sources=sources,
            jac_version=jac_version()
        );
        return True;
    }

    """Build cache for all .jac files in project."""
    def build_all() -> tuple[int, int] {
        """Build cache for all .jac files. Returns (success_count, error_count)."""
        success = 0;
        errors = 0;

        for jac_file in self.project_root.rglob("*.jac") {
            # Skip files in .jac_env
            if self.env_dir in str(jac_file) {
                continue;
            }
            print(f"  Caching {jac_file.relative_to(self.project_root)}...");
            if self.build_single(jac_file) {
                success += 1;
            } else {
                errors += 1;
            }
        }
        return (success, errors);
    }

    """Clear all cached files."""
    def clear() -> None {
        cache = self.cache_path();
        if cache.exists() {
            shutil.rmtree(cache);
            print(f"Cleared cache at {cache}");
        } else {
            print("Cache directory does not exist.");
        }
    }

    """Get cache status."""
    def status() -> dict {
        cache = self.cache_path();
        if not cache.exists() {
            return {"exists": False, "files": 0, "size_bytes": 0};
        }

        files = list(cache.rglob("*.jir"));
        total_size = sum(f.stat().st_size for f in files);

        return {
            "exists": True,
            "files": len(files),
            "size_bytes": total_size,
            "path": str(cache)
        };
    }

    """Print cache status to stdout."""
    def print_status() -> None {
        status = self.status();
        if not status["exists"] {
            print("Cache: Not initialized");
        } else {
            print(f"Cache: {status['path']}");
            print(f"Files: {status['files']}");
            size_mb = status['size_bytes'] / (1024 * 1024);
            print(f"Size: {size_mb:.2f} MB");
        }
    }
}
```

---

## Current State

### Current Settings (`jaclang/pycore/settings.py`) - TO BE DELETED

12 settings in a Python dataclass:

| Category | Settings |
|----------|----------|
| Debug | `filter_sym_builtins`, `ast_symbol_info_detailed`, `pass_timer`, `print_py_raised_ast`, `show_internal_stack_errs` |
| Compiler | `ignore_test_annex`, `pyfile_raise`, `pyfile_raise_full` |
| Formatter | `max_line_length` |
| LSP | `lsp_debug` |
| Alerts | `all_warnings` |

Loading precedence: `~/.jaclang/config.ini` < Environment Variables < CLI Arguments

**Replaced by:** `bootstrap_config.py` (Python, ~80 lines) + `config.jac` (Jac, full config)

### Current Plugin Configurations

| Plugin | Current Config | Format |
|--------|----------------|--------|
| jac-client | `config.json` | JSON with deep merge |
| jac-byllm | Constructor params | In-memory dict |
| jac-scale | `.env` file | Environment variables |
| jac-streamlit | CLI args only | None |

**Problem:** No unified configuration. Each plugin has its own approach.

---

## Proposed `jac.toml` Schema

### Minimal Complete Example

```toml
# jac.toml - Project Configuration

[project]
name = "my-jac-project"
version = "0.1.0"
description = "A Jac project"
entry_point = "main.jac"
jac_version = ">=0.9.3"

[environment]
python_version = "3.12"
env_dir = ".jac_env"

[dependencies]
jac-byllm = ">=0.4.8"
jac-client = ">=0.2.3"
requests = ">=2.28.0"
numpy = ">=1.24.0"

[dev_dependencies]
pytest = ">=8.2.1"

#-------------------------------------------------------------------------------
# Core Settings (replaces settings.py - NO CLI flags)
#-------------------------------------------------------------------------------

[settings]
max_line_length = 88

[settings.debug]
filter_sym_builtins = true
ast_symbol_info_detailed = false
pass_timer = false
print_py_raised_ast = false
show_internal_stack_errs = false

[settings.compiler]
ignore_test_annex = false
pyfile_raise = false
pyfile_raise_full = false

[settings.lsp]
lsp_debug = false

[settings.alerts]
all_warnings = false

#-------------------------------------------------------------------------------
# Cache Configuration
#-------------------------------------------------------------------------------

[cache]
enabled = true
auto_build = true       # Automatically cache on first run

#-------------------------------------------------------------------------------
# Plugin Configurations (plugins self-describe their schemas)
#-------------------------------------------------------------------------------

[plugins.byllm]
default_model = "gpt-4o"
temperature = 0.7
max_tokens = 4096
api_key_env = "OPENAI_API_KEY"

[plugins.client]
bundle_output_dir = "dist/client"
source_maps = true

[plugins.client.vite]
port = 5173

[plugins.client.vite.build]
outDir = "dist/client"
minify = "esbuild"

[plugins.scale]
jwt_secret = "${JWT_SECRET}"
jwt_algorithm = "HS256"
mongodb_uri = "${MONGODB_URI:-}"

[plugins.streamlit]
theme = "light"
server_port = 8501

#-------------------------------------------------------------------------------
# Environment Profiles
#-------------------------------------------------------------------------------

[environments.development]
[environments.development.settings.debug]
show_internal_stack_errs = true
pass_timer = true

[environments.development.plugins.byllm]
temperature = 0.9

[environments.production]
[environments.production.settings.debug]
show_internal_stack_errs = false

[environments.production.plugins.scale]
min_replicas = 3
```

---

## Environment Variable Interpolation

Support for secrets and environment-specific values:

| Syntax | Behavior |
|--------|----------|
| `${VAR}` | Required - fails if not set |
| `${VAR:-default}` | Optional with default value |
| `${VAR:?error msg}` | Required with custom error |

```toml
[plugins.scale]
jwt_secret = "${JWT_SECRET}"              # Required
mongodb_uri = "${MONGODB_URI:-}"          # Optional, empty default
debug_mode = "${DEBUG:-false}"            # Optional with default
```

---

## New CLI Commands

### Simplified CLI (No Settings Flags)

```bash
# Project initialization
jac init                          # Interactive project setup
jac init --quick                  # Quick setup with defaults

# Dependency management
jac install                       # Install all dependencies
jac install jac-byllm             # Add specific package
jac install --dev pytest          # Add dev dependency

# Environment management
jac env info                      # Show environment status
jac env create                    # Create .jac_env
jac env remove                    # Remove .jac_env

# Cache management
jac cache build                   # Build cache for entry_point
jac cache build --all             # Cache all .jac files
jac cache clear                   # Clear cached .jir files
jac cache status                  # Show cache info

# Configuration
jac config show                   # Display resolved config
jac config show plugins.byllm     # Show specific section
jac config validate               # Validate jac.toml

# Existing commands (unchanged interface)
jac run main.jac                  # Run with project config (uses cache)
jac run main.jac --no-cache       # Run without cache
jac run main.jac --env production # Run with environment profile
jac build main.jac
jac test
jac format .
jac serve main.jac
```

**Key Change:** All settings come from `jac.toml`, not CLI flags.

---

## Module Structure

```
jaclang/
├── pycore/
│   ├── bootstrap_config.py       # NEW: Minimal Python bootstrap (~80 lines)
│   ├── settings.py               # DELETED
│   └── ...
├── project/                      # NEW: Project management (Jac)
│   ├── __init__.jac              # Module exports
│   ├── config.jac                # JacConfig object (full config)
│   ├── cache.jac                 # JacProgram caching
│   ├── toml_loader.jac           # TOML parsing (delegates to Python)
│   ├── discovery.jac             # Project root discovery
│   ├── environment.jac           # Venv management
│   ├── interpolation.jac         # Env var interpolation
│   ├── plugin_config.jac         # Plugin config loading
│   └── impl/
│       ├── config.impl.jac
│       ├── cache.impl.jac
│       ├── toml_loader.impl.jac
│       ├── discovery.impl.jac
│       ├── environment.impl.jac
│       ├── interpolation.impl.jac
│       └── plugin_config.impl.jac
├── cli/
│   ├── cli.jac                   # MODIFIED: Remove settings flags
│   ├── impl/cli.impl.jac         # MODIFIED: Load config first, use cache
│   └── commands/                 # NEW: New CLI commands (Jac)
│       ├── init.jac
│       ├── install.jac
│       ├── env.jac
│       ├── cache.jac
│       └── config_cmd.jac
```

---

## Core Implementation (Jac)

### 1. Settings Object (`jaclang/project/config.jac`)

```jac
"""Jac project configuration - replaces settings.py."""
import from pathlib { Path }
import from typing { Any }

#-------------------------------------------------------------------------------
# Runtime Settings (loaded after bootstrap, in Jac)
#-------------------------------------------------------------------------------

"""Debug configuration settings (runtime portion)."""
obj DebugSettings {
    has filter_sym_builtins: bool = True,
        ast_symbol_info_detailed: bool = False,
        show_internal_stack_errs: bool = False;

    # Note: pass_timer and print_py_raised_ast are bootstrap-only
}

"""LSP configuration settings."""
obj LspSettings {
    has lsp_debug: bool = False;
}

"""Complete settings - merges bootstrap + runtime."""
obj JacSettings {
    has max_line_length: int = 88,
        debug: DebugSettings = DebugSettings(),
        lsp: LspSettings = LspSettings();

    # Bootstrap settings are accessed via bootstrap_config.bootstrap
}

#-------------------------------------------------------------------------------
# Project Configuration
#-------------------------------------------------------------------------------

"""Project metadata from [project] section."""
obj ProjectMetadata {
    has name: str = "",
        version: str = "0.1.0",
        description: str = "",
        entry_point: str = "main.jac",
        jac_version: str = "";
}

"""Environment configuration from [environment] section."""
obj EnvironmentConfig {
    has python_version: str = "3.10",
        env_dir: str = ".jac_env";
}

"""Cache configuration from [cache] section."""
obj CacheConfig {
    has enabled: bool = True,
        auto_build: bool = True;
}

"""Main configuration object for Jac projects."""
obj JacConfig {
    has project: ProjectMetadata = ProjectMetadata(),
        environment: EnvironmentConfig = EnvironmentConfig(),
        cache: CacheConfig = CacheConfig(),
        settings: JacSettings = JacSettings(),
        dependencies: dict[str, str] = {},
        dev_dependencies: dict[str, str] = {},
        plugins: dict[str, Any] = {},
        environments: dict[str, Any] = {};

    has project_root: (Path | None) = None,
        toml_path: (Path | None) = None;

    static def load(toml_path: Path) -> JacConfig;
    static def discover(start_path: (Path | None) = None) -> JacConfig;
    def apply_environment(env_name: str) -> None;
    def get_plugin_config(plugin_name: str) -> dict;
    def config_hash() -> str;  # For cache invalidation
}

#-------------------------------------------------------------------------------
# Global Access
#-------------------------------------------------------------------------------

glob _config: (JacConfig | None) = None;

"""Get or discover the global configuration."""
def get_config() -> JacConfig;

"""Get settings - combines bootstrap + runtime settings."""
def get_settings() -> JacSettings;
```

### 2. Config Implementation (`jaclang/project/impl/config.impl.jac`)

```jac
"""Implementation of JacConfig loading and discovery."""
import os;
import hashlib;
import json;
import from pathlib { Path }
import from typing { Any }
import from ..toml_loader { load_toml }
import from ..discovery { find_project_root }
import from ..interpolation { interpolate_value }
import from jaclang.pycore.bootstrap_config { bootstrap }

"""Get or discover the global configuration."""
impl get_config() -> JacConfig {
    glob _config;
    if _config is None {
        _config = JacConfig.discover();
    }
    return _config;
}

"""Get settings - combines bootstrap + runtime settings."""
impl get_settings() -> JacSettings {
    return get_config().settings;
}

"""Load configuration from a jac.toml file."""
impl JacConfig.load(toml_path: Path) -> JacConfig {
    raw = load_toml(toml_path);

    config = JacConfig();
    config.toml_path = toml_path;
    config.project_root = toml_path.parent;

    # Load project metadata
    if "project" in raw {
        proj = raw["project"];
        config.project = ProjectMetadata(
            name=proj.get("name", ""),
            version=proj.get("version", "0.1.0"),
            description=proj.get("description", ""),
            entry_point=proj.get("entry_point", "main.jac"),
            jac_version=proj.get("jac_version", "")
        );
    }

    # Load environment config
    if "environment" in raw {
        env = raw["environment"];
        config.environment = EnvironmentConfig(
            python_version=env.get("python_version", "3.10"),
            env_dir=env.get("env_dir", ".jac_env")
        );
    }

    # Load cache config
    if "cache" in raw {
        c = raw["cache"];
        config.cache = CacheConfig(
            enabled=c.get("enabled", True),
            auto_build=c.get("auto_build", True)
        );
    }

    # Load runtime settings (bootstrap settings come from bootstrap_config)
    if "settings" in raw {
        config.settings = _load_runtime_settings(raw["settings"]);
    }

    # Load dependencies
    config.dependencies = raw.get("dependencies", {});
    config.dev_dependencies = raw.get("dev_dependencies", {});

    # Load environments/profiles
    config.environments = raw.get("environments", {});

    # Load and interpolate plugin configs
    if "plugins" in raw {
        config.plugins = interpolate_value(raw["plugins"]);
    }

    return config;
}

"""Discover and load jac.toml from current or parent directories."""
impl JacConfig.discover(start_path: (Path | None) = None) -> JacConfig {
    if start_path is None {
        start_path = Path(os.getcwd());
    }

    result = find_project_root(start_path);
    if result is not None {
        (project_root, toml_path) = result;
        return JacConfig.load(toml_path);
    }

    # No jac.toml found - return defaults
    return JacConfig();
}

"""Apply environment-specific overrides."""
impl JacConfig.apply_environment(env_name: str) -> None {
    if env_name not in self.environments {
        raise ValueError(f"Unknown environment: {env_name}");
    }

    env_config = self.environments[env_name];

    # Deep merge environment overrides into current config
    if "settings" in env_config {
        _merge_settings(self, env_config["settings"]);
    }
    if "plugins" in env_config {
        _merge_plugins(self, env_config["plugins"]);
    }
}

"""Get configuration for a specific plugin."""
impl JacConfig.get_plugin_config(plugin_name: str) -> dict {
    return self.plugins.get(plugin_name, {});
}

"""Generate a hash of config for cache invalidation."""
impl JacConfig.config_hash() -> str {
    # Hash the settings and dependencies that affect compilation
    data = {
        "settings": {
            "max_line_length": self.settings.max_line_length,
            "ignore_test_annex": bootstrap.settings.ignore_test_annex,
            "pyfile_raise": bootstrap.settings.pyfile_raise,
            "all_warnings": bootstrap.settings.all_warnings
        },
        "dependencies": self.dependencies
    };
    content = json.dumps(data, sort_keys=True);
    return hashlib.sha256(content.encode()).hexdigest()[:16];
}

"""Parse runtime settings section into JacSettings object."""
def _load_runtime_settings(raw: dict) -> JacSettings {
    settings = JacSettings();
    settings.max_line_length = raw.get("max_line_length", 88);

    if "debug" in raw {
        d = raw["debug"];
        settings.debug = DebugSettings(
            filter_sym_builtins=d.get("filter_sym_builtins", True),
            ast_symbol_info_detailed=d.get("ast_symbol_info_detailed", False),
            show_internal_stack_errs=d.get("show_internal_stack_errs", False)
        );
    }

    if "lsp" in raw {
        settings.lsp = LspSettings(lsp_debug=raw["lsp"].get("lsp_debug", False));
    }

    return settings;
}

"""Merge environment settings overrides."""
def _merge_settings(config: JacConfig, overrides: dict) -> None {
    if "debug" in overrides {
        for (key, val) in overrides["debug"].items() {
            if hasattr(config.settings.debug, key) {
                setattr(config.settings.debug, key, val);
            }
        }
    }
    if "lsp" in overrides {
        for (key, val) in overrides["lsp"].items() {
            setattr(config.settings.lsp, key, val);
        }
    }
    if "max_line_length" in overrides {
        config.settings.max_line_length = overrides["max_line_length"];
    }
}

"""Merge environment plugin overrides."""
def _merge_plugins(config: JacConfig, overrides: dict) -> None {
    for (plugin_name, plugin_overrides) in overrides.items() {
        if plugin_name not in config.plugins {
            config.plugins[plugin_name] = {};
        }
        _deep_merge(config.plugins[plugin_name], plugin_overrides);
    }
}

"""Recursively merge override into base."""
def _deep_merge(base: dict, override: dict) -> None {
    for (key, val) in override.items() {
        if (key in base and isinstance(base[key], dict) and isinstance(val, dict)) {
            _deep_merge(base[key], val);
        } else {
            base[key] = val;
        }
    }
}
```

### 3. TOML Loader (`jaclang/project/toml_loader.jac`)

```jac
"""TOML file loading - delegates to Python stdlib."""
import from pathlib { Path }
import from typing { Any }

"""Load and parse a TOML file."""
def load_toml(file_path: Path) -> dict[str, Any];
```

### 4. TOML Loader Implementation (`jaclang/project/impl/toml_loader.impl.jac`)

```jac
"""TOML loader implementation using Python stdlib."""
import sys;
import from pathlib { Path }
import from typing { Any }

"""Load and parse a TOML file."""
impl load_toml(file_path: Path) -> dict[str, Any] {
    # Use Python's tomllib (3.11+) or tomli
    if sys.version_info >= (3, 11) {
        import tomllib;
        with open(file_path, "rb") as f {
            return tomllib.load(f);
        }
    } else {
        import tomli;
        with open(file_path, "rb") as f {
            return tomli.load(f);
        }
    }
}
```

### 5. Project Discovery (`jaclang/project/discovery.jac`)

```jac
"""Project root discovery by finding jac.toml."""
import from pathlib { Path }

glob JAC_TOML = "jac.toml";

"""Find project root by looking for jac.toml."""
def find_project_root(start: (Path | None) = None) -> (tuple[Path, Path] | None);

"""Check if currently in a Jac project."""
def is_in_project() -> bool;
```

### 6. Discovery Implementation (`jaclang/project/impl/discovery.impl.jac`)

```jac
"""Implementation of project root discovery."""
import os;
import from pathlib { Path }
import from jaclang.pycore.bootstrap_config { find_jac_toml }

"""Find project root by looking for jac.toml.

Returns:
    Tuple of (project_root, toml_path) or None if not found.
"""
impl find_project_root(start: (Path | None) = None) -> (tuple[Path, Path] | None) {
    # Delegate to Python bootstrap (already implemented there)
    toml_path = find_jac_toml(start);
    if toml_path is not None {
        return (toml_path.parent, toml_path);
    }
    return None;
}

"""Check if currently in a Jac project."""
impl is_in_project() -> bool {
    return find_project_root() is not None;
}
```

### 7. Environment Variable Interpolation (`jaclang/project/interpolation.jac`)

```jac
"""Environment variable interpolation for jac.toml values."""
import os;
import re;
import from typing { Any }

# Pattern: ${VAR}, ${VAR:-default}, ${VAR:?error message}
glob ENV_VAR_PATTERN = re.compile(
    r'\$\{(?P<name>[A-Z_][A-Z0-9_]*)'
    r'(?:(?P<op>:[-?])(?P<value>[^}]*))?\}'
);

"""Recursively interpolate environment variables in a value."""
def interpolate_value(value: Any) -> Any;

"""Interpolate environment variables in a string."""
def interpolate_string(text: str) -> str;

"""Validate that all required environment variables are set."""
def validate_env_vars(config: dict) -> list[str];
```

### 8. Interpolation Implementation (`jaclang/project/impl/interpolation.impl.jac`)

```jac
"""Implementation of environment variable interpolation."""
import os;
import re;
import from typing { Any }
import from ..interpolation { ENV_VAR_PATTERN }

"""Recursively interpolate environment variables in a value."""
impl interpolate_value(value: Any) -> Any {
    if isinstance(value, str) {
        return interpolate_string(value);
    } elif isinstance(value, dict) {
        return {k: interpolate_value(v) for (k, v) in value.items()};
    } elif isinstance(value, list) {
        return [interpolate_value(item) for item in value];
    }
    return value;
}

"""Interpolate environment variables in a string."""
impl interpolate_string(text: str) -> str {
    def replace_match(match: re.Match) -> str {
        name = match.group("name");
        op = match.group("op");
        default_or_msg = match.group("value");

        env_value = os.environ.get(name);

        if env_value is not None {
            return env_value;
        }

        if op == ":-" {
            # Optional with default
            return default_or_msg if default_or_msg else "";
        } elif op == ":?" {
            # Required with custom error
            msg = default_or_msg or f"Environment variable {name} is not set";
            raise ValueError(msg);
        } else {
            # Required (no operator)
            raise ValueError(f"Required environment variable {name} is not set");
        }
    }

    return ENV_VAR_PATTERN.sub(replace_match, text);
}

"""Validate that all required environment variables are set.

Returns list of error messages for missing required variables.
"""
impl validate_env_vars(config: dict) -> list[str] {
    errors: list[str] = [];

    def check_value(value: Any, path: str) -> None {
        if isinstance(value, str) {
            for match in ENV_VAR_PATTERN.finditer(value) {
                name = match.group("name");
                op = match.group("op");
                if (op != ":-" and name not in os.environ) {
                    errors.append(f"{path}: Missing required env var ${name}");
                }
            }
        } elif isinstance(value, dict) {
            for (k, v) in value.items() {
                check_value(v, f"{path}.{k}");
            }
        } elif isinstance(value, list) {
            for (i, item) in enumerate(value) {
                check_value(item, f"{path}[{i}]");
            }
        }
    }

    check_value(config, "jac.toml");
    return errors;
}
```

### 9. Virtual Environment Manager (`jaclang/project/environment.jac`)

```jac
"""Virtual environment management for .jac_env."""
import from pathlib { Path }

"""Manages the .jac_env virtual environment."""
obj JacEnvironment {
    has project_root: Path,
        env_dir: str = ".jac_env";

    def env_path() -> Path;
    def cache_path() -> Path;
    def exists() -> bool;
    def python() -> Path;
    def pip() -> Path;
    def create(python_version: (str | None) = None) -> None;
    def install_package(package: str, dev: bool = False) -> None;
    def install_requirements(requirements: dict[str, str]) -> None;
    def remove() -> None;
    def activate() -> None;
}

"""Ensure project environment exists and is activated."""
def ensure_project_env() -> (JacEnvironment | None);
```

### 10. Environment Implementation (`jaclang/project/impl/environment.impl.jac`)

```jac
"""Implementation of virtual environment management."""
import os;
import sys;
import venv;
import subprocess;
import shutil;
import from pathlib { Path }
import from .config { get_config }

"""Get the environment path."""
impl JacEnvironment.env_path() -> Path {
    return self.project_root / self.env_dir;
}

"""Get the cache path within the environment."""
impl JacEnvironment.cache_path() -> Path {
    return self.env_path() / "cache";
}

"""Check if environment exists."""
impl JacEnvironment.exists() -> bool {
    return (self.env_path() / "bin" / "python").exists();
}

"""Get Python executable path."""
impl JacEnvironment.python() -> Path {
    if sys.platform == "win32" {
        return self.env_path() / "Scripts" / "python.exe";
    }
    return self.env_path() / "bin" / "python";
}

"""Get pip executable path."""
impl JacEnvironment.pip() -> Path {
    if sys.platform == "win32" {
        return self.env_path() / "Scripts" / "pip.exe";
    }
    return self.env_path() / "bin" / "pip";
}

"""Create the virtual environment."""
impl JacEnvironment.create(python_version: (str | None) = None) -> None {
    print(f"Creating virtual environment at {self.env_path()}...");
    venv.create(self.env_path(), with_pip=True);

    # Create cache directory
    self.cache_path().mkdir(parents=True, exist_ok=True);

    # Install jaclang in the environment
    print("Installing jaclang...");
    self.install_package("jaclang");

    # Add to .gitignore if exists
    gitignore = self.project_root / ".gitignore";
    if gitignore.exists() {
        content = gitignore.read_text();
        if self.env_dir not in content {
            with open(gitignore, "a") as f {
                f.write(f"\n{self.env_dir}/\n");
            }
        }
    }
}

"""Install a package in the environment."""
impl JacEnvironment.install_package(package: str, dev: bool = False) -> None {
    subprocess.run(
        [str(self.pip()), "install", package],
        check=True,
        capture_output=True
    );
}

"""Install all requirements from dependencies dict."""
impl JacEnvironment.install_requirements(requirements: dict[str, str]) -> None {
    for (package, version) in requirements.items() {
        spec = f"{package}{version}" if version else package;
        print(f"Installing {spec}...");
        self.install_package(spec);
    }
}

"""Remove the virtual environment."""
impl JacEnvironment.remove() -> None {
    if self.exists() {
        print(f"Removing {self.env_path()}...");
        shutil.rmtree(self.env_path());
    }
}

"""Modify sys.path to use this environment's packages."""
impl JacEnvironment.activate() -> None {
    if sys.platform == "win32" {
        site_packages = self.env_path() / "Lib" / "site-packages";
    } else {
        # Find the python version directory
        lib_path = self.env_path() / "lib";
        python_dirs = list(lib_path.glob("python3.*"));
        if python_dirs {
            site_packages = python_dirs[0] / "site-packages";
        } else {
            return;
        }
    }

    if (site_packages.exists() and str(site_packages) not in sys.path) {
        sys.path.insert(0, str(site_packages));
    }
}

"""Ensure project environment exists and is activated."""
impl ensure_project_env() -> (JacEnvironment | None) {
    config = get_config();

    if config.project_root is None {
        return None;
    }

    env = JacEnvironment(
        project_root=config.project_root,
        env_dir=config.environment.env_dir
    );

    if not env.exists() {
        env.create(config.environment.python_version);
    }

    env.activate();
    return env;
}
```

---

## CLI Modifications

### Updated `cli.jac` (Remove Settings Flags, Add Cache)

```jac
"""Command line interface tool for the Jac language."""
import from jaclang.cli.cmdreg { cmd_registry }

# NEW: Import project config and cache
import from jaclang.project.config { get_config, get_settings }
import from jaclang.project.environment { ensure_project_env }
import from jaclang.project.cache { JacCache, get_or_compile }

glob _runtime_initialized = False;

# Existing commands - now use jac.toml config and cache
@cmd_registry.register
def run(
    filename: str,
    session: str = '',
    main: bool = True,
    cache: bool = True,          # NEW: Use cache by default
    env: str = ''                # NEW: Environment profile
) -> None;

@cmd_registry.register
def serve(
    filename: str,
    session: str = '',
    port: int = 8000,
    main: bool = True,
    faux: bool = False,
    cache: bool = True,          # NEW: Use cache
    env: str = ''                # NEW: Environment profile
) -> None;

# ... other commands unchanged ...

#-------------------------------------------------------------------------------
# NEW COMMANDS
#-------------------------------------------------------------------------------

@cmd_registry.register
def init(name: str = '', quick: bool = False) -> None;

@cmd_registry.register
def install(packages: list[str] = [], dev: bool = False) -> None;

@cmd_registry.register
def jac_env(action: str = 'info') -> None;  # info, create, remove

@cmd_registry.register
def jac_cache(action: str = 'status', all_files: bool = False) -> None;  # status, build, clear

@cmd_registry.register
def config(action: str = 'show', path: str = '') -> None;  # show, validate

def start_cli() -> None;
```

### Updated `cli.impl.jac` - Run with Cache

```jac
"""CLI implementation - loads config and uses cache."""
import argparse;
import pickle;
import sys;
import os;
import from pathlib { Path }
import from jaclang.project.config { get_config }
import from jaclang.project.environment { ensure_project_env, JacEnvironment }
import from jaclang.project.cache { CacheManager }
# Cache loading from Python for fastest startup
import from jaclang.pycore.bootstrap_config {
    bootstrap,
    load_cached_program,
    save_cached_program
}
import from jaclang.pycore.program { JacProgram }
import from jaclang { version as jac_version }

"""Run a Jac program - uses Python cache loading for fastest startup."""
impl run(
    filename: str,
    session: str = '',
    main: bool = True,
    cache: bool = True,
    env: str = ''
) -> None {
    config = get_config();

    # Apply environment profile if specified
    if env {
        config.apply_environment(env);
    }

    (base, mod) = os.path.split(filename);
    base = base if base else './';
    mod = mod[:-4] if mod.endswith('.jac') else mod[:-4] if mod.endswith('.jir') else mod;
    lng = 'jac' if filename.endswith('.jac') else 'jir' if filename.endswith('.jir') else 'py';

    if filename.endswith('.jac') {
        source = Path(filename).resolve();

        # Try Python cache loading first (fastest path)
        program: (JacProgram | None) = None;
        if cache and bootstrap.cache_enabled {
            program = load_cached_program(
                config=bootstrap,
                source=source,
                jac_version=jac_version()
            );
        }

        if program is not None {
            # Cache hit - skip compilation entirely!
            Jac.attach_program(program);
            Jac.jac_import(target=mod, base_path=base, lng=lng);
        } else {
            # Cache miss - compile and optionally cache
            program = JacProgram();
            program.compile(file_path=str(source));

            if program.errors_had {
                for error in program.errors_had {
                    print(f"{error}", file=sys.stderr);
                }
                <>exit(1);
            }

            # Save to cache for next time
            if cache and bootstrap.cache_enabled {
                sources = {"main": source};
                save_cached_program(
                    config=bootstrap,
                    source=source,
                    program=program,
                    sources=sources,
                    jac_version=jac_version()
                );
            }

            Jac.attach_program(program);
            Jac.jac_import(target=mod, base_path=base, lng=lng);
        }
    } elif filename.endswith('.jir') {
        with open(filename, 'rb') as f {
            Jac.attach_program(pickle.load(f));
            Jac.jac_import(target=mod, base_path=base, lng=lng);
        }
    }
}

"""Main entry point - now loads jac.toml first."""
impl start_cli() -> None {
    # 1. Bootstrap config is already loaded (Python bootstrap_config.py)
    # 2. Discover and load full jac.toml config
    config = get_config();

    # 3. Ensure project environment if in a project
    if config.project_root is not None {
        ensure_project_env();
    }

    # 4. Build parser (NO settings flags - all from jac.toml)
    parser = argparse.ArgumentParser(
        prog="jac",
        description="Jac Programming Language CLI"
    );

    # 5. Register commands
    cmd_registry.finalize();

    # 6. Parse and execute
    args = parser.parse_args();

    # 7. Apply environment profile if specified
    if (hasattr(args, 'env') and args.env) {
        config.apply_environment(args.env);
    }

    # 8. Execute command
    args.func(args);
}

#-------------------------------------------------------------------------------
# NEW COMMAND IMPLEMENTATIONS
#-------------------------------------------------------------------------------

"""Initialize a new Jac project."""
impl init(name: str = '', quick: bool = False) -> None {
    import os;
    import from pathlib { Path }
    import from jaclang.project.cache { JacCache }

    project_dir = Path(os.getcwd());

    if not name {
        name = project_dir.name;
    }

    # Create jac.toml
    toml_content = f'''# jac.toml - Jac Project Configuration

[project]
name = "{name}"
version = "0.1.0"
description = ""
entry_point = "main.jac"

[environment]
python_version = "3.10"
env_dir = ".jac_env"

[dependencies]

[cache]
enabled = true
auto_build = true

[settings]
max_line_length = 88

[settings.debug]
show_internal_stack_errs = false
''';

    toml_path = project_dir / "jac.toml";
    if (toml_path.exists() and not quick) {
        print("jac.toml already exists. Use --quick to overwrite.");
        return;
    }

    toml_path.write_text(toml_content);
    print(f"Created {toml_path}");

    # Create main.jac if it doesn't exist
    main_jac = project_dir / "main.jac";
    if not main_jac.exists() {
        main_jac.write_text('with entry {\n    print("Hello, Jac!");\n}\n');
        print(f"Created {main_jac}");
    }

    # Create .gitignore
    gitignore = project_dir / ".gitignore";
    if not gitignore.exists() {
        gitignore.write_text(".jac_env/\n__pycache__/\n*.pyc\n.jac_cache/\n");
        print(f"Created {gitignore}");
    }

    # Create virtual environment with cache directory
    import from jaclang.project.environment { JacEnvironment }
    env = JacEnvironment(project_root=project_dir);
    env.create();

    # Pre-build cache for entry point
    print("\nBuilding initial cache...");
    jac_cache = JacCache(project_root=project_dir);
    import from jaclang.project.config { JacConfig }
    config = JacConfig.load(toml_path);

    program = get_or_compile(
        source=main_jac,
        cache=jac_cache,
        config_hash=config.config_hash()
    );

    if program.errors_had {
        print("Warning: Initial compilation had errors, cache not built.");
    } else {
        print("Cache built successfully.");
    }

    print(f"\nProject '{name}' initialized successfully!");
    print("\nNext steps:");
    print("  jac run main.jac");
}

"""Cache management command."""
impl jac_cache(action: str = 'status', all_files: bool = False) -> None {
    config = get_config();

    if config.project_root is None {
        print("Error: Not in a Jac project.");
        return;
    }

    cache_mgr = CacheManager(
        project_root=config.project_root,
        env_dir=config.environment.env_dir
    );

    if action == 'status' {
        cache_mgr.print_status();
    } elif action == 'build' {
        print("Building cache...");
        if all_files {
            (success, errors) = cache_mgr.build_all();
            print(f"Cache build complete: {success} succeeded, {errors} failed.");
        } else {
            # Build cache for entry point only
            entry = config.project_root / config.project.entry_point;
            if entry.exists() {
                print(f"  Caching {config.project.entry_point}...");
                if cache_mgr.build_single(entry) {
                    print("Cache build complete.");
                } else {
                    print("Cache build failed (compilation errors).");
                }
            } else {
                print(f"Entry point not found: {config.project.entry_point}");
            }
        }
    } elif action == 'clear' {
        cache_mgr.clear();
    } else {
        print(f"Unknown action: {action}");
        print("Valid actions: status, build, clear");
    }
}

"""Install dependencies."""
impl install(packages: list[str] = [], dev: bool = False) -> None {
    config = get_config();

    if config.project_root is None {
        print("Error: Not in a Jac project. Run 'jac init' first.");
        return;
    }

    import from jaclang.project.environment { JacEnvironment }
    env = JacEnvironment(
        project_root=config.project_root,
        env_dir=config.environment.env_dir
    );

    if not env.exists() {
        env.create();
    }

    if packages {
        # Install specific packages
        for pkg in packages {
            print(f"Installing {pkg}...");
            env.install_package(pkg, dev=dev);
        }
    } else {
        # Install all from jac.toml
        print("Installing dependencies from jac.toml...");
        env.install_requirements(config.dependencies);
        if dev {
            env.install_requirements(config.dev_dependencies);
        }
    }

    print("Installation complete!");
}

"""Manage project environment."""
impl jac_env(action: str = 'info') -> None {
    config = get_config();

    if config.project_root is None {
        print("Error: Not in a Jac project.");
        return;
    }

    import from jaclang.project.environment { JacEnvironment }
    env = JacEnvironment(
        project_root=config.project_root,
        env_dir=config.environment.env_dir
    );

    if action == 'info' {
        print(f"Project: {config.project.name}");
        print(f"Root: {config.project_root}");
        print(f"Environment: {env.env_path()}");
        print(f"Exists: {env.exists()}");
        if env.exists() {
            print(f"Python: {env.python()}");
            print(f"Cache: {env.cache_path()}");
        }
    } elif action == 'create' {
        if env.exists() {
            print("Environment already exists.");
        } else {
            env.create();
            print("Environment created.");
        }
    } elif action == 'remove' {
        env.remove();
        print("Environment removed.");
    } else {
        print(f"Unknown action: {action}");
        print("Valid actions: info, create, remove");
    }
}

"""Show or validate configuration."""
impl config(action: str = 'show', path: str = '') -> None {
    import json;
    config = get_config();

    if action == 'show' {
        if path {
            # Show specific path
            parts = path.split('.');
            value = config;
            for part in parts {
                if hasattr(value, part) {
                    value = getattr(value, part);
                } elif (isinstance(value, dict) and part in value) {
                    value = value[part];
                } else {
                    print(f"Path not found: {path}");
                    return;
                }
            }
            if isinstance(value, dict) {
                print(json.dumps(value, indent=2));
            } else {
                print(value);
            }
        } else {
            # Show all
            print(f"Project: {config.project.name} v{config.project.version}");
            print(f"Root: {config.project_root}");
            print(f"\nCache:");
            print(f"  enabled: {config.cache.enabled}");
            print(f"  auto_build: {config.cache.auto_build}");
            print(f"\nSettings:");
            print(f"  max_line_length: {config.settings.max_line_length}");
            print(f"  debug.show_internal_stack_errs: {config.settings.debug.show_internal_stack_errs}");
            print(f"\nPlugins: {list(config.plugins.keys())}");
        }
    } elif action == 'validate' {
        import from jaclang.project.interpolation { validate_env_vars }

        errors = validate_env_vars(config.plugins);
        if errors {
            print("Validation errors:");
            for err in errors {
                print(f"  - {err}");
            }
        } else {
            print("Configuration is valid.");
        }
    }
}
```

---

## Plugin Hook Additions

Add these hooks to `jaclang/pycore/runtime.py` (in `JacRuntimeInterface`):

```python
# Add to JacRuntimeInterface class

@staticmethod
@hookspec
def get_config_spec() -> dict | None:
    """Return plugin's configuration specification.

    Returns:
        {
            "section": "byllm",  # [plugins.byllm] in jac.toml
            "schema": {
                "option_name": {
                    "type": "str" | "int" | "float" | "bool" | "list",
                    "default": <default_value>,
                    "description": "Human readable description",
                }
            }
        }
    """
    return None

@staticmethod
@hookspec
def configure(plugin_name: str, config: dict) -> None:
    """Called when plugin configuration is loaded from jac.toml.

    Args:
        plugin_name: The plugin section name
        config: The plugin's configuration from [plugins.<name>]
    """
    pass

@staticmethod
@hookspec
def validate_config(config: dict) -> list[str]:
    """Validate plugin configuration.

    Args:
        config: The plugin's configuration

    Returns:
        List of validation error messages (empty if valid)
    """
    return []
```

---

## Implementation Phases

### Phase 1: Python Bootstrap (3-4 days)

- [ ] Create `jaclang/pycore/bootstrap_config.py` (~80 lines)
- [ ] Update imports in `meta_importer.py`, `transform.py`, `annex_pass.py`
- [ ] Test that compiler still works with bootstrap settings

### Phase 2: Core Jac Infrastructure (1 week)

- [ ] Create `jaclang/project/` module structure
- [ ] Implement `config.jac` + `config.impl.jac`
- [ ] Implement `toml_loader.jac` + `toml_loader.impl.jac`
- [ ] Implement `discovery.jac` + `discovery.impl.jac`
- [ ] Implement `interpolation.jac` + `interpolation.impl.jac`

### Phase 3: Caching System (1 week)

- [ ] Implement `cache.jac` + `cache.impl.jac`
- [ ] Integrate caching into `jac run`
- [ ] Implement `jac cache` CLI commands
- [ ] Test cache invalidation scenarios

### Phase 4: Environment Management (3-4 days)

- [ ] Implement `environment.jac` + `environment.impl.jac`
- [ ] Update `jaclang/__init__.py` to call `ensure_project_env()`
- [ ] Test venv creation/activation

### Phase 5: Plugin Configuration (3-4 days)

- [ ] Add hooks to `runtime.py`: `get_config_spec()`, `configure()`, `validate_config()`
- [ ] Implement `plugin_config.jac` + `plugin_config.impl.jac`
- [ ] Update existing plugins with config specs

### Phase 6: CLI Updates (1 week)

- [ ] Remove settings flags from CLI
- [ ] Add `--env` and `--no-cache` flags
- [ ] Implement `jac init` (with cache pre-build)
- [ ] Implement `jac install`
- [ ] Implement `jac env`
- [ ] Implement `jac cache`
- [ ] Implement `jac config`

### Phase 7: Cleanup (2-3 days)

- [ ] Delete `jaclang/pycore/settings.py`
- [ ] Remove `~/.jaclang/config.ini` support
- [ ] Update all internal imports to use new config
- [ ] Write tests

---

## Files Summary

### New Files

| File | Language | Lines | Description |
|------|----------|-------|-------------|
| `jaclang/pycore/bootstrap_config.py` | Python | ~150 | Bootstrap settings + cache loading |
| `jaclang/project/__init__.jac` | Jac | ~20 | Module exports |
| `jaclang/project/config.jac` | Jac | ~80 | JacConfig, JacSettings objects |
| `jaclang/project/impl/config.impl.jac` | Jac | ~150 | Config implementation |
| `jaclang/project/cache.jac` | Jac | ~80 | Cache management (build/clear/status) |
| `jaclang/project/toml_loader.jac` | Jac | ~10 | TOML loading interface |
| `jaclang/project/impl/toml_loader.impl.jac` | Jac | ~20 | TOML implementation |
| `jaclang/project/discovery.jac` | Jac | ~15 | Project discovery interface |
| `jaclang/project/impl/discovery.impl.jac` | Jac | ~20 | Discovery implementation |
| `jaclang/project/interpolation.jac` | Jac | ~20 | Env var interpolation interface |
| `jaclang/project/impl/interpolation.impl.jac` | Jac | ~60 | Interpolation implementation |
| `jaclang/project/environment.jac` | Jac | ~30 | Venv management interface |
| `jaclang/project/impl/environment.impl.jac` | Jac | ~100 | Venv implementation |
| `jaclang/project/plugin_config.jac` | Jac | ~30 | Plugin config interface |
| `jaclang/project/impl/plugin_config.impl.jac` | Jac | ~100 | Plugin config implementation |

**Total new Jac code:** ~735 lines
**Total new Python code:** ~150 lines (includes cache loading for fastest startup)

### Modified Files

| File | Changes |
|------|---------|
| `jaclang/pycore/runtime.py` | Add `get_config_spec()`, `configure()`, `validate_config()` hooks |
| `jaclang/meta_importer.py` | Import from `bootstrap_config` instead of `settings` |
| `jaclang/pycore/passes/transform.py` | Import from `bootstrap_config` |
| `jaclang/pycore/passes/annex_pass.py` | Import from `bootstrap_config` |
| `jaclang/pycore/treeprinter.py` | Import runtime settings from Jac config |
| `jaclang/pycore/helpers.py` | Import runtime settings from Jac config |
| `jaclang/__init__.py` | Call `ensure_project_env()` before plugin loading |
| `jaclang/cli/cli.jac` | Remove settings flags, add `--env`, `--no-cache`, add new commands |
| `jaclang/cli/impl/cli.impl.jac` | Load config first, implement caching, implement new commands |

### Deleted Files

| File | Replacement |
|------|-------------|
| `jaclang/pycore/settings.py` | `bootstrap_config.py` (Python) + `config.jac` (Jac) |

---

## Success Criteria

1. **`jac init`** creates a working project with `jac.toml`, `.jac_env/`, and pre-built cache
2. **`jac run`** uses cached `.jir` files for fast startup (skips compilation entirely on cache hit)
3. **Cache loading in Python** - `load_cached_program()` runs before any Jac code loads
4. **`jac cache`** commands work (status, build, clear)
5. **`jac install`** installs dependencies into `.jac_env/`
6. **All settings** come from `jac.toml`, not CLI flags
7. **All plugins** can be configured via `[plugins.<name>]` sections
8. **`${VAR}`** interpolation works for secrets
9. **`--env`** flag applies environment-specific overrides
10. **`--no-cache`** flag forces recompilation
11. **`settings.py`** is deleted with no regressions
12. **~83% of code is Jac** (~735 lines), ~17% Python bootstrap (~150 lines)
