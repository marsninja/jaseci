"""Package manager abstraction for npm/bun support."""

import os;
import subprocess;
import from pathlib { Path }

"""Handles package manager detection and command abstraction.

Supports both npm and bun with automatic detection and fallback.
Can be overridden via JAC_CLIENT_PACKAGE_MANAGER environment variable.
"""
obj PackageManager {
    static has ENV_VAR: str = "JAC_CLIENT_PACKAGE_MANAGER";

    """Check if bun is installed and accessible."""
    static def is_bun_installed -> bool;

    """Check if npm is installed and accessible."""
    static def is_npm_installed -> bool;

    """Get the currently installed bun version."""
    static def get_bun_version -> (str | None);

    """Get the currently installed npm version."""
    static def get_npm_version -> (str | None);

    """Get the preferred package manager.

    Priority:
    1. JAC_CLIENT_PACKAGE_MANAGER env var if set
    2. bun if installed
    3. npm as fallback

    Returns "bun" or "npm".
    """
    static def get_preferred -> str;

    """Get the install command for the preferred package manager.

    Returns ["bun", "install"] or ["npm", "install"].
    """
    static def get_install_cmd -> list[str];

    """Get the run command for a script.

    Returns ["bun", "run", script] or ["npm", "run", script].
    """
    static def get_run_cmd(script: str) -> list[str];

    """Get the exec command (npx/bunx).

    Returns "bunx" or "npx".
    """
    static def get_exec_cmd -> str;

    """Get the global add command for a package.

    Returns ["bun", "add", "-g", pkg] or ["npm", "install", "-g", pkg].
    """
    static def get_global_add_cmd(pkg: str) -> list[str];

    """Get the global list command.

    Returns appropriate command to list global packages.
    """
    static def get_global_list_cmd -> list[str];

    """Get the version check command.

    Returns ["bun", "--version"] or ["npm", "--version"].
    """
    static def get_version_cmd -> list[str];

    """Run a package manager command with proper environment.

    Handles NVM sourcing for npm if needed.
    """
    static def run_cmd(
        args: list,
        cwd: Path,
        timeout: int = 300,
        check: bool = True,
        capture_output: bool = True
    ) -> object;

    """Get the build script content for package.json.

    Returns the appropriate build script based on package manager.
    """
    static def get_build_script(config_path: str) -> str;
}
