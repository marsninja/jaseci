"""Jac Package Manager (JacPM) — native npm package installer.

Downloads and installs npm packages to node_modules/ without
requiring Bun or npm CLI tools. Uses the npm registry API directly.
"""

"""Install packages from a package.json file into a target directory.

Reads dependencies from package_json_path, resolves versions,
downloads tarballs, and extracts them to node_modules/ under target_dir.
Uses a lock file (jac-lock.json) for reproducible installs.

If npmrc_path is provided, reads registry/auth config from it.
"""
def install(
    package_json_path: object, target_dir: object, npmrc_path: (object | None) = None
) -> None;

"""Install a single package globally to ~/.jac/node_modules/."""
def install_global(package_name: str, version: (str | None) = None) -> None;

"""List globally installed packages."""
def list_global -> dict[str, str];

"""Check if a specific global package is installed."""
def is_global_installed(package_name: str) -> bool;
