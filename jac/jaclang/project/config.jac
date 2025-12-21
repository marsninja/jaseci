"""Jac project configuration module.

This module provides the JacConfig class and related types for managing
project configuration from jac.toml files.
"""

import os;
import re;
import sys;
import tomllib;
import from pathlib { Path }
import from typing { Any }

# ===============================================================================
# Configuration Data Classes
# ===============================================================================
"""Project metadata from [project] section."""
obj ProjectConfig {
    has name: str = "",
        version: str = "0.1.0",
        description: str = "",
        authors: list[str] = [],
        license: str = "",
        readme: str = "README.md",
        jac_version: str = "",
        entry_point: str = "main.jac",
        urls: dict[str, str] = {};
}

"""Run command defaults from [run] section."""
obj RunConfig {
    has session: str = "",
        main: bool = True,
        cache: bool = True;
}

"""Build command defaults from [build] section."""
obj BuildConfig {
    has typecheck: bool = False;
}

"""Test command defaults from [test] section."""
obj TestConfig {
    has directory: str = "",
        filter: str = "",
        verbose: bool = False,
        fail_fast: bool = False,
        max_failures: int = 0;
}

"""Serve command defaults from [serve] section."""
obj ServeConfig {
    has port: int = 8000,
        session: str = "",
        main: bool = True;
}

"""Format command defaults from [format] section."""
obj FormatConfig {
    has outfile: str = "",
        fix: bool = False;
}

"""Check command defaults from [check] section."""
obj CheckConfig {
    has print_errs: bool = True,
        warnonly: bool = False;
}

"""Dot/graph visualization defaults from [dot] section."""
obj DotConfig {
    has depth: int = -1,
        traverse: bool = False,
        bfs: bool = False,
        edge_limit: int = 512,
        node_limit: int = 512,
        format: str = "dot";
}

"""Cache settings from [cache] section."""
obj CacheConfig {
    has enabled: bool = True,
        dir: str = ".jac_cache";
}

"""Plugin settings from [plugins] section."""
obj PluginsConfig {
    has discovery: str = "auto",
        enabled: list[str] = [],
        disabled: list[str] = [];
}

"""Environment configuration from [environment] section."""
obj EnvironmentConfig {
    has default_profile: str = "";
}

# ===============================================================================
# Environment Variable Interpolation
# ===============================================================================

# Interpolate environment variables in a string value.
# Supports ${VAR_NAME}, ${VAR_NAME:-default}, ${VAR_NAME:?error message}
def interpolate_env_vars(
    value: str
) -> str;

# ===============================================================================
# Project Discovery
# ===============================================================================

# Find project root by looking for jac.toml.
def find_project_root(
    start: Path | None = None
) -> tuple[Path, Path] | None;

# Check if currently in a Jac project.
def is_in_project -> bool;

# ===============================================================================
# Main Configuration Class
# ===============================================================================
"""Central configuration class for Jac projects.

This class manages all configuration from jac.toml files, including:
- Project metadata
- Dependencies (Python/Jac, git, npm)
- Command defaults (run, build, test, etc.)
- Plugin configuration
- Environment profiles
"""
obj JacConfig {
    has project: ProjectConfig = ProjectConfig(),
        run: RunConfig = RunConfig(),
        build: BuildConfig = BuildConfig(),
        test: TestConfig = TestConfig(),
        serve: ServeConfig = ServeConfig(),
        format: FormatConfig = FormatConfig(),
        check: CheckConfig = CheckConfig(),
        dot: DotConfig = DotConfig(),
        cache: CacheConfig = CacheConfig(),
        plugins_config: PluginsConfig = PluginsConfig(),
        environment: EnvironmentConfig = EnvironmentConfig(),
        # Dependencies
        dependencies: dict[str, str] = {},
        dev_dependencies: dict[str, str] = {},
        git_dependencies: dict[str, dict[str, str]] = {},
        # Plugin-provided dependency types (e.g., npm, go)
        plugin_dependencies: dict[str, dict[str, Any]] = {},
        # Scripts
        scripts: dict[str, str] = {},
        # Plugin configurations
        plugins: dict[str, dict[str, Any]] = {},
        # Environments/profiles
        environments: dict[str, dict[str, Any]] = {},
        # Runtime state
        project_root: Path | None = None,
        toml_path: Path | None = None,
        # Raw TOML data for reference
        _raw_data: dict[str, Any] = {};

    # Discover and load jac.toml from current or parent directories
    static def discover(start_path: Path | None = None) -> JacConfig | None;
    # Load configuration from a specific jac.toml file
    static def load(toml_path: Path) -> JacConfig;
    # Parse a TOML string into JacConfig
    static def from_toml_str(toml_str: str, toml_path: Path | None = None) -> JacConfig;
    # Apply environment variable interpolation to config values
    def apply_env_interpolation -> None;
    # Apply CLI argument overrides to configuration
    def apply_cli_overrides(args: dict[str, Any]) -> None;
    # Apply an environment profile to the configuration
    def apply_profile(profile_name: str) -> None;
    # Get plugin-specific dependencies (e.g., npm, go modules)
    def get_plugin_deps(dep_type: str) -> dict[str, Any];
    # Get plugin configuration by name
    def get_plugin_config(plugin_name: str) -> dict[str, Any];
    # Get the packages directory path
    def get_packages_dir -> Path;
    # Check if we are in a valid Jac project
    def is_valid -> bool;
    # Create a minimal jac.toml content for project initialization
    static def create_default_toml(project_name: str) -> str;
    # Save configuration to jac.toml file
    def save -> None;
    # Add a dependency to the configuration
    def add_dependency(
        name: str, version: str, dev: bool = False, dep_type: str = "python"
    ) -> None;
    # Remove a dependency from the configuration
    def remove_dependency(
        name: str, dev: bool = False, dep_type: str = "python"
    ) -> bool;
}

# ===============================================================================
# Helper Functions (internal)
# ===============================================================================

# Parse TOML data into JacConfig object
def _parse_toml_data(
    data: dict[str, Any], toml_path: Path | None = None
) -> JacConfig;

# Recursively apply environment variable interpolation
def _interpolate_recursive(
    obj: Any
) -> Any;

# ===============================================================================
# Global Configuration Singleton
# ===============================================================================
glob _config:
         JacConfig | None = None;

# Get the global configuration, discovering it if necessary
def get_config(
    force_discover: bool = False
) -> JacConfig | None;

# Set the global configuration
def set_config(config: JacConfig) -> None;
