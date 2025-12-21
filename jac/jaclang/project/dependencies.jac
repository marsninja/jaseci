"""Dependency management for Jac projects.

This module handles installation, removal, and resolution of dependencies
for Jac projects, including Python/Jac packages, git dependencies, and
plugin-provided dependency types (npm, etc.).
"""

import subprocess;
import sys;
import from pathlib { Path }
import from jaclang.project.config { JacConfig }

# ===============================================================================
# Dependency Data Classes
# ===============================================================================
"""Represents a resolved dependency with version info."""
obj ResolvedDependency {
    has name: str,
        version: str,
        source: str = "pypi",
        extras: list[str] = [],
        dependencies: list[str] = [];
}

# ===============================================================================
# Dependency Installer
# ===============================================================================
"""Manages installation of dependencies for Jac projects."""
obj DependencyInstaller {
    has config: JacConfig | None = None,
        packages_dir: Path | None = None,
        verbose: bool = False;

    # Initialize the dependency installer
    def postinit -> None;
    # Ensure the packages directory exists and is in sys.path
    def ensure_packages_dir -> None;
    # Run pip command with packages directory as target
    def _run_pip(args: list[str]) -> tuple[int, str, str];
    # Install all dependencies from jac.toml
    def install_all(include_dev: bool = False) -> bool;
    # Install a single Python/Jac package
    def install_package(name: str, version: str = "") -> bool;
    # Install a git-based dependency
    def install_git_package(name: str, git_url: str, branch: str = "") -> bool;
    # Uninstall a package from the packages directory
    def uninstall_package(name: str) -> bool;
    # Check if a package is installed
    def is_installed(name: str) -> bool;
    # Get the list of installed packages
    def list_installed -> list[str];
}

# ===============================================================================
# Dependency Resolution
# ===============================================================================
"""Resolves dependencies and their transitive dependencies."""
obj DependencyResolver {
    has config: JacConfig | None = None;

    # Initialize the resolver
    def postinit -> None;
    # Parse a dependency specification (e.g., 'requests>=2.28.0')
    def parse_spec(spec: str) -> tuple[str, str];
    # Resolve all dependencies from configuration
    def resolve(include_dev: bool = False) -> list[ResolvedDependency];
}

# ===============================================================================
# Package Search Path Management
# ===============================================================================

# Add the project's packages directory to sys.path
def add_packages_to_path(
    config: JacConfig | None = None
) -> None;

# Remove the project's packages directory from sys.path
def remove_packages_from_path(
    config: JacConfig | None = None
) -> None;

# Check if packages directory is in sys.path
def is_packages_in_path(
    config: JacConfig | None = None
) -> bool;
