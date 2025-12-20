# Jac Project Configuration - Simplified Architecture

## Overview

This document outlines a streamlined approach to introduce `jac.toml` as the central project configuration file. This is a **clean break** from the legacy `settings.py` and `~/.jaclang/config.ini` system.

**Key Priorities:**

1. Virtual environment management (`.jac_env/`)
2. Unified plugin configuration (all plugins configured via `jac.toml`)
3. Complete replacement of `settings.py`
4. Removal of CLI flags for settings (too many to expose)

**Implementation Language:** All new infrastructure will be written in **Jac**, not Python.

---

## Current State

### Current Settings (`jaclang/pycore/settings.py`)

12 settings in a Python dataclass:

| Category | Settings |
|----------|----------|
| Debug | `filter_sym_builtins`, `ast_symbol_info_detailed`, `pass_timer`, `print_py_raised_ast`, `show_internal_stack_errs` |
| Compiler | `ignore_test_annex`, `pyfile_raise`, `pyfile_raise_full` |
| Formatter | `max_line_length` |
| LSP | `lsp_debug` |
| Alerts | `all_warnings` |

Loading precedence: `~/.jaclang/config.ini` < Environment Variables < CLI Arguments

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
python_version = "3.10"
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

# Configuration
jac config show                   # Display resolved config
jac config show plugins.byllm     # Show specific section
jac config validate               # Validate jac.toml

# Existing commands (unchanged interface)
jac run main.jac                  # Run with project config
jac run main.jac --env production # Run with environment profile
jac build main.jac
jac test
jac format .
jac serve main.jac
```

**Key Change:** All settings come from `jac.toml`, not CLI flags.

---

## Module Structure (Jac Implementation)

```
jaclang/
├── project/                          # NEW: Project management (Jac)
│   ├── __init__.jac                  # Module exports
│   ├── config.jac                    # JacConfig object
│   ├── impl/
│   │   ├── config.impl.jac           # Config implementation
│   │   ├── toml_loader.impl.jac      # TOML parsing
│   │   ├── discovery.impl.jac        # Project root discovery
│   │   ├── environment.impl.jac      # Venv management
│   │   ├── interpolation.impl.jac    # Env var interpolation
│   │   └── plugin_config.impl.jac    # Plugin config loading
│   ├── toml_loader.jac
│   ├── discovery.jac
│   ├── environment.jac
│   ├── interpolation.jac
│   └── plugin_config.jac
├── cli/
│   ├── cli.jac                       # MODIFIED: Remove settings flags
│   ├── impl/cli.impl.jac             # MODIFIED: Load config first
│   └── commands/                     # NEW: New CLI commands (Jac)
│       ├── init.jac
│       ├── install.jac
│       ├── env.jac
│       └── config_cmd.jac
└── pycore/
    └── settings.py                   # DELETED (Phase 5)
```

---

## Core Implementation (Jac)

### 1. Settings Object (`jaclang/project/config.jac`)

```jac
"""Jac project configuration - replaces settings.py."""
import from pathlib { Path }
import from typing { Any }

#-------------------------------------------------------------------------------
# Core Settings (exact mirror of settings.py)
#-------------------------------------------------------------------------------

"""Debug configuration settings."""
obj DebugSettings {
    has filter_sym_builtins: bool = True,
        ast_symbol_info_detailed: bool = False,
        pass_timer: bool = False,
        print_py_raised_ast: bool = False,
        show_internal_stack_errs: bool = False;
}

"""Compiler configuration settings."""
obj CompilerSettings {
    has ignore_test_annex: bool = False,
        pyfile_raise: bool = False,
        pyfile_raise_full: bool = False;
}

"""LSP configuration settings."""
obj LspSettings {
    has lsp_debug: bool = False;
}

"""Alert configuration settings."""
obj AlertSettings {
    has all_warnings: bool = False;
}

"""Core settings - complete replacement for settings.py."""
obj JacSettings {
    has max_line_length: int = 88,
        debug: DebugSettings = DebugSettings(),
        compiler: CompilerSettings = CompilerSettings(),
        lsp: LspSettings = LspSettings(),
        alerts: AlertSettings = AlertSettings();
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

"""Main configuration object for Jac projects."""
obj JacConfig {
    has project: ProjectMetadata = ProjectMetadata(),
        environment: EnvironmentConfig = EnvironmentConfig(),
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
}

#-------------------------------------------------------------------------------
# Global Access (drop-in replacement for settings.settings)
#-------------------------------------------------------------------------------

glob _config: (JacConfig | None) = None;

"""Get or discover the global configuration."""
def get_config() -> JacConfig;

"""Get settings - replaces `from jaclang.pycore.settings import settings`."""
def get_settings() -> JacSettings;
```

### 2. Config Implementation (`jaclang/project/impl/config.impl.jac`)

```jac
"""Implementation of JacConfig loading and discovery."""
import os;
import from pathlib { Path }
import from typing { Any }
import from ..toml_loader { load_toml }
import from ..discovery { find_project_root }
import from ..interpolation { interpolate_value }

"""Get or discover the global configuration."""
impl get_config() -> JacConfig {
    glob _config;
    if _config is None {
        _config = JacConfig.discover();
    }
    return _config;
}

"""Get settings - replaces `from jaclang.pycore.settings import settings`."""
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

    # Load settings (replaces settings.py)
    if "settings" in raw {
        config.settings = _load_settings(raw["settings"]);
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

"""Parse settings section into JacSettings object."""
def _load_settings(raw: dict) -> JacSettings {
    settings = JacSettings();
    settings.max_line_length = raw.get("max_line_length", 88);

    if "debug" in raw {
        d = raw["debug"];
        settings.debug = DebugSettings(
            filter_sym_builtins=d.get("filter_sym_builtins", True),
            ast_symbol_info_detailed=d.get("ast_symbol_info_detailed", False),
            pass_timer=d.get("pass_timer", False),
            print_py_raised_ast=d.get("print_py_raised_ast", False),
            show_internal_stack_errs=d.get("show_internal_stack_errs", False)
        );
    }

    if "compiler" in raw {
        c = raw["compiler"];
        settings.compiler = CompilerSettings(
            ignore_test_annex=c.get("ignore_test_annex", False),
            pyfile_raise=c.get("pyfile_raise", False),
            pyfile_raise_full=c.get("pyfile_raise_full", False)
        );
    }

    if "lsp" in raw {
        settings.lsp = LspSettings(lsp_debug=raw["lsp"].get("lsp_debug", False));
    }

    if "alerts" in raw {
        settings.alerts = AlertSettings(all_warnings=raw["alerts"].get("all_warnings", False));
    }

    return settings;
}

"""Merge environment settings overrides."""
def _merge_settings(config: JacConfig, overrides: dict) -> None {
    if "debug" in overrides {
        for (key, val) in overrides["debug"].items() {
            setattr(config.settings.debug, key, val);
        }
    }
    if "compiler" in overrides {
        for (key, val) in overrides["compiler"].items() {
            setattr(config.settings.compiler, key, val);
        }
    }
    if "lsp" in overrides {
        for (key, val) in overrides["lsp"].items() {
            setattr(config.settings.lsp, key, val);
        }
    }
    if "alerts" in overrides {
        for (key, val) in overrides["alerts"].items() {
            setattr(config.settings.alerts, key, val);
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
"""TOML file loading with Python 3.10+ compatibility."""
import from pathlib { Path }
import from typing { Any }

"""Load and parse a TOML file."""
def load_toml(file_path: Path) -> dict[str, Any];
```

### 4. TOML Loader Implementation (`jaclang/project/impl/toml_loader.impl.jac`)

```jac
"""TOML loader implementation with fallback for Python < 3.11."""
import sys;
import from pathlib { Path }
import from types { ModuleType }
import from typing { Any }

# Python 3.11+ has tomllib in stdlib, older versions need tomli
glob _tomllib: (ModuleType | None) = None;

"""Get the appropriate TOML parser for this Python version."""
def _get_toml_parser() -> ModuleType {
    glob _tomllib;

    if _tomllib is None {
        if sys.version_info >= (3, 11) {
            import tomllib;
            _tomllib = tomllib;
        } else {
            try {
                import tomli as tomllib;
                _tomllib = tomllib;
            } except ImportError {
                raise ImportError(
                    "Python < 3.11 requires 'tomli' package. "
                    "Install with: pip install tomli"
                );
            }
        }
    }
    return _tomllib;
}

"""Load and parse a TOML file."""
impl load_toml(file_path: Path) -> dict[str, Any] {
    parser = _get_toml_parser();
    with open(file_path, "rb") as f {
        return parser.load(f);
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

"""Find project root by looking for jac.toml.

Returns:
    Tuple of (project_root, toml_path) or None if not found.
"""
impl find_project_root(start: (Path | None) = None) -> (tuple[Path, Path] | None) {
    if start is None {
        start = Path(os.getcwd());
    }

    current = start.resolve();

    while current != current.parent {
        toml_path = current / "jac.toml";
        if toml_path.exists() {
            return (current, toml_path);
        }
        current = current.parent;
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

### 11. Plugin Configuration System (`jaclang/project/plugin_config.jac`)

```jac
"""Plugin configuration loading and validation."""
import from typing { Any }

"""Manages plugin configuration loading and validation."""
obj PluginConfigManager {
    has schemas: dict[str, dict] = {},
        configs: dict[str, dict] = {};

    def collect_schemas() -> None;
    def load_from_toml(plugins_section: dict) -> None;
    def validate_all() -> list[str];
    def notify_plugins() -> None;
    def get_plugin_config(section_name: str) -> dict;
}

"""Convenience function to load all plugin configs."""
def load_plugin_configs(plugins_section: dict) -> dict[str, dict];
```

### 12. Plugin Config Implementation (`jaclang/project/impl/plugin_config.impl.jac`)

```jac
"""Implementation of plugin configuration system."""
import sys;
import from typing { Any }
import from jaclang.pycore.runtime { plugin_manager }

"""Collect configuration schemas from all registered plugins."""
impl PluginConfigManager.collect_schemas() -> None {
    # Call the hook on all plugins
    results = plugin_manager.hook.get_config_spec();

    for schema in results {
        if schema is not None {
            section = schema.get("section");
            if section {
                self.schemas[section] = schema;
            }
        }
    }
}

"""Load plugin configurations from jac.toml [plugins] section."""
impl PluginConfigManager.load_from_toml(plugins_section: dict) -> None {
    for (section_name, schema) in self.schemas.items() {
        raw_config = plugins_section.get(section_name, {});

        # Apply defaults from schema
        config: dict = {};
        options = schema.get("schema", {});

        for (opt_name, opt_spec) in options.items() {
            if opt_name in raw_config {
                config[opt_name] = _coerce_type(
                    raw_config[opt_name],
                    opt_spec.get("type", "str")
                );
            } else {
                config[opt_name] = opt_spec.get("default");
            }
        }

        # Include any extra config not in schema (passthrough)
        for (key, val) in raw_config.items() {
            if key not in config {
                config[key] = val;
            }
        }

        self.configs[section_name] = config;
    }

    # Also store configs for plugins without schemas (passthrough)
    for (section_name, config) in plugins_section.items() {
        if section_name not in self.configs {
            self.configs[section_name] = config;
        }
    }
}

"""Validate all plugin configurations."""
impl PluginConfigManager.validate_all() -> list[str] {
    all_errors: list[str] = [];

    for (section_name, config) in self.configs.items() {
        # Call plugin's validate_config hook if it exists
        errors = plugin_manager.hook.validate_config(config=config);
        for error_list in errors {
            if error_list {
                for err in error_list {
                    all_errors.append(f"[plugins.{section_name}] {err}");
                }
            }
        }
    }

    return all_errors;
}

"""Notify plugins that configuration has been loaded."""
impl PluginConfigManager.notify_plugins() -> None {
    for (section_name, config) in self.configs.items() {
        plugin_manager.hook.configure(plugin_name=section_name, config=config);
    }
}

"""Get configuration for a specific plugin."""
impl PluginConfigManager.get_plugin_config(section_name: str) -> dict {
    return self.configs.get(section_name, {});
}

"""Coerce a value to the specified type."""
def _coerce_type(value: Any, type_name: str) -> Any {
    if type_name == "int" {
        return int(value);
    } elif type_name == "float" {
        return float(value);
    } elif type_name == "bool" {
        if isinstance(value, str) {
            return value.lower() in ("true", "yes", "1", "t", "y");
        }
        return bool(value);
    } elif type_name == "list" {
        if isinstance(value, str) {
            return [v.strip() for v in value.split(",")];
        }
        return list(value);
    }
    return value;
}

"""Convenience function to load all plugin configs."""
impl load_plugin_configs(plugins_section: dict) -> dict[str, dict] {
    manager = PluginConfigManager();
    manager.collect_schemas();
    manager.load_from_toml(plugins_section);

    errors = manager.validate_all();
    if errors {
        for err in errors {
            print(f"Warning: {err}", file=sys.stderr);
        }
    }

    manager.notify_plugins();
    return manager.configs;
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

## CLI Modifications

### Updated `cli.jac` (Remove Settings Flags)

```jac
"""Command line interface tool for the Jac language."""
import from jaclang.cli.cmdreg { cmd_registry }

# NEW: Import project config
import from jaclang.project.config { get_config, get_settings }
import from jaclang.project.environment { ensure_project_env }

glob _runtime_initialized = False;

# Existing commands - unchanged signatures but now use jac.toml config
@cmd_registry.register
def run(
    filename: str,
    session: str = '',
    main: bool = True,
    cache: bool = True,
    env: str = ''          # NEW: Only CLI arg for settings
) -> None;

@cmd_registry.register
def serve(
    filename: str,
    session: str = '',
    port: int = 8000,      # Can still override via CLI
    main: bool = True,
    faux: bool = False,
    env: str = ''          # NEW: Environment profile
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
def config(action: str = 'show', path: str = '') -> None;  # show, validate

def start_cli() -> None;
```

### Updated `cli.impl.jac` Start Function

```jac
"""CLI implementation - loads config before executing commands."""
import argparse;
import from jaclang.project.config { get_config }
import from jaclang.project.environment { ensure_project_env }

"""Main entry point - now loads jac.toml first."""
impl start_cli() -> None {
    # 1. Discover and load jac.toml BEFORE anything else
    config = get_config();

    # 2. Ensure project environment if in a project
    if config.project_root is not None {
        ensure_project_env();
    }

    # 3. Build parser (NO settings flags - all from jac.toml)
    parser = argparse.ArgumentParser(
        prog="jac",
        description="Jac Programming Language CLI"
    );

    # 4. Register commands
    cmd_registry.finalize();

    # 5. Parse and execute
    args = parser.parse_args();

    # 6. Apply environment profile if specified
    if (hasattr(args, 'env') and args.env) {
        config.apply_environment(args.env);
    }

    # 7. Execute command (settings come from config, not CLI)
    args.func(args);
}

#-------------------------------------------------------------------------------
# NEW COMMAND IMPLEMENTATIONS
#-------------------------------------------------------------------------------

"""Initialize a new Jac project."""
impl init(name: str = '', quick: bool = False) -> None {
    import os;
    import from pathlib { Path }

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

    # Create virtual environment
    import from jaclang.project.environment { JacEnvironment }
    env = JacEnvironment(project_root=project_dir);
    env.create();

    print(f"\nProject '{name}' initialized successfully!");
    print("\nNext steps:");
    print("  jac run main.jac");
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

## Implementation Phases

### Phase 1: Core Infrastructure (Week 1)

- [ ] Create `jaclang/project/` module structure
- [ ] Implement `config.jac` + `config.impl.jac`
- [ ] Implement `toml_loader.jac` + `toml_loader.impl.jac`
- [ ] Implement `discovery.jac` + `discovery.impl.jac`
- [ ] Implement `interpolation.jac` + `interpolation.impl.jac`

### Phase 2: Environment Management (Week 2)

- [ ] Implement `environment.jac` + `environment.impl.jac`
- [ ] Update `jaclang/__init__.py` to call `ensure_project_env()`
- [ ] Test venv creation/activation

### Phase 3: Plugin Configuration (Week 3)

- [ ] Add hooks to `runtime.py`: `get_config_spec()`, `configure()`, `validate_config()`
- [ ] Implement `plugin_config.jac` + `plugin_config.impl.jac`
- [ ] Update existing plugins with config specs

### Phase 4: CLI Updates (Week 4)

- [ ] Remove settings flags from CLI
- [ ] Add `--env` flag for environment profiles
- [ ] Implement `jac init`
- [ ] Implement `jac install`
- [ ] Implement `jac env`
- [ ] Implement `jac config`

### Phase 5: Cleanup (Week 5)

- [ ] Delete `jaclang/pycore/settings.py`
- [ ] Remove `~/.jaclang/config.ini` support
- [ ] Update all internal imports to use new config
- [ ] Write tests

---

## Plugin Update Examples

### jac-byllm Plugin Update

```jac
"""jac-byllm plugin with jac.toml configuration."""
import from jaclang.pycore.runtime { hookimpl }

glob _plugin_config: dict = {};

@hookimpl
def get_config_spec() -> dict {
    return {
        "section": "byllm",
        "schema": {
            "default_model": {"type": "str", "default": "gpt-4o"},
            "temperature": {"type": "float", "default": 0.7},
            "max_tokens": {"type": "int", "default": 4096},
            "api_key_env": {"type": "str", "default": "OPENAI_API_KEY"},
            "cache_enabled": {"type": "bool", "default": True}
        }
    };
}

@hookimpl
def configure(plugin_name: str, config: dict) -> None {
    if plugin_name == "byllm" {
        glob _plugin_config;
        _plugin_config = config;
        # Initialize LLM client with config
        _init_llm_client();
    }
}

@hookimpl
def validate_config(config: dict) -> list[str] {
    errors: list[str] = [];

    temp = config.get("temperature", 0.7);
    if (temp < 0 or temp > 2) {
        errors.append("temperature must be between 0 and 2");
    }

    max_tokens = config.get("max_tokens", 4096);
    if max_tokens < 1 {
        errors.append("max_tokens must be positive");
    }

    return errors;
}
```

### jac-client Plugin Update

```jac
"""jac-client plugin with jac.toml configuration."""
import from jaclang.pycore.runtime { hookimpl }

glob _plugin_config: dict = {};

@hookimpl
def get_config_spec() -> dict {
    return {
        "section": "client",
        "schema": {
            "bundle_output_dir": {"type": "str", "default": "dist/client"},
            "source_maps": {"type": "bool", "default": True},
            "minify": {"type": "bool", "default": False}
        }
    };
}

@hookimpl
def configure(plugin_name: str, config: dict) -> None {
    if plugin_name == "client" {
        glob _plugin_config;
        _plugin_config = config;
    }
}

# Nested config (vite, typescript) is passed through as-is
# Access via: _plugin_config.get("vite", {}).get("build", {})
```

### jac-scale Plugin Update

```jac
"""jac-scale plugin with jac.toml configuration."""
import from jaclang.pycore.runtime { hookimpl }

glob _plugin_config: dict = {};

@hookimpl
def get_config_spec() -> dict {
    return {
        "section": "scale",
        "schema": {
            "jwt_secret": {"type": "str", "default": ""},
            "jwt_algorithm": {"type": "str", "default": "HS256"},
            "mongodb_uri": {"type": "str", "default": ""},
            "min_replicas": {"type": "int", "default": 1},
            "max_replicas": {"type": "int", "default": 5}
        }
    };
}

@hookimpl
def configure(plugin_name: str, config: dict) -> None {
    if plugin_name == "scale" {
        glob _plugin_config;
        _plugin_config = config;
    }
}

@hookimpl
def validate_config(config: dict) -> list[str] {
    errors: list[str] = [];

    min_r = config.get("min_replicas", 1);
    max_r = config.get("max_replicas", 5);
    if min_r > max_r {
        errors.append("min_replicas cannot be greater than max_replicas");
    }

    return errors;
}
```

---

## Files to Create/Modify

### New Files (Jac)

| File | Description |
|------|-------------|
| `jaclang/project/__init__.jac` | Module exports |
| `jaclang/project/config.jac` | JacConfig, JacSettings objects |
| `jaclang/project/impl/config.impl.jac` | Config implementation |
| `jaclang/project/toml_loader.jac` | TOML loading interface |
| `jaclang/project/impl/toml_loader.impl.jac` | TOML implementation |
| `jaclang/project/discovery.jac` | Project discovery interface |
| `jaclang/project/impl/discovery.impl.jac` | Discovery implementation |
| `jaclang/project/interpolation.jac` | Env var interpolation interface |
| `jaclang/project/impl/interpolation.impl.jac` | Interpolation implementation |
| `jaclang/project/environment.jac` | Venv management interface |
| `jaclang/project/impl/environment.impl.jac` | Venv implementation |
| `jaclang/project/plugin_config.jac` | Plugin config interface |
| `jaclang/project/impl/plugin_config.impl.jac` | Plugin config implementation |

### Modified Files

| File | Changes |
|------|---------|
| `jaclang/pycore/runtime.py` | Add `get_config_spec()`, `configure()`, `validate_config()` hooks |
| `jaclang/__init__.py` | Call `ensure_project_env()` before plugin loading |
| `jaclang/cli/cli.jac` | Remove settings flags, add `--env`, add new commands |
| `jaclang/cli/impl/cli.impl.jac` | Load config first, implement new commands |

### Deleted Files (Phase 5)

| File | Replacement |
|------|-------------|
| `jaclang/pycore/settings.py` | `jaclang/project/config.jac` |

---

## Success Criteria

1. **`jac init`** creates a working project with `jac.toml` and `.jac_env/`
2. **`jac install`** installs dependencies into `.jac_env/`
3. **All settings** come from `jac.toml`, not CLI flags
4. **All plugins** can be configured via `[plugins.<name>]` sections
5. **`${VAR}`** interpolation works for secrets
6. **`--env`** flag applies environment-specific overrides
7. **`settings.py`** is deleted with no regressions
