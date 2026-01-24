"""Automatic Node.js and bun installation utilities."""

import os;
import platform;
import subprocess;
import from pathlib { Path }

"""Handles Node.js and bun installation and detection."""
obj NodeInstaller {
    static has DEFAULT_NODE_VERSION: str = "20",
        NVM_INSTALL_URL: str = "https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh",
        BUN_INSTALL_URL: str = "https://bun.sh/install";

    """Check if Node.js is installed and accessible."""
    static def is_node_installed -> bool;

    """Check if npm is installed and accessible."""
    static def is_npm_installed -> bool;

    """Check if bun is installed and accessible."""
    static def is_bun_installed -> bool;

    """Check if NVM is installed."""
    static def is_nvm_installed -> bool;

    """Get the currently installed Node.js version."""
    static def get_node_version -> (str | None);

    """Get the currently installed bun version."""
    static def get_bun_version -> (str | None);

    """Install NVM (Node Version Manager)."""
    static def install_nvm -> tuple[bool, str];

    """Install bun using the official install script."""
    static def install_bun -> tuple[bool, str];

    """Install Node.js using NVM."""
    static def install_node_via_nvm(version: str = "20") -> tuple[bool, str];

    """Ensure Node.js is installed, installing automatically if needed.

    Returns tuple of (success: bool, message: str, was_just_installed: bool)
    """
    static def ensure_node_installed(
        interactive: bool = True
    ) -> tuple[bool, str, bool];

    """Ensure bun is installed, installing automatically if needed.

    Returns tuple of (success: bool, message: str, was_just_installed: bool)
    """
    static def ensure_bun_installed(interactive: bool = True) -> tuple[bool, str, bool];

    """Ensure a package manager (bun or npm) is available.

    Prefers bun, falls back to npm/Node.js if bun installation fails.
    Returns tuple of (success: bool, message: str, package_manager: str)
    """
    static def ensure_package_manager_installed(
        interactive: bool = True
    ) -> tuple[bool, str, str];

    """Run npm command with NVM environment properly sourced."""
    static def run_npm_with_nvm(args: list, cwd: Path, timeout: int = 300) -> object;

    """Run bun command with proper PATH (handles ~/.bun/bin)."""
    static def run_bun_with_path(args: list, cwd: Path, timeout: int = 300) -> object;
}
