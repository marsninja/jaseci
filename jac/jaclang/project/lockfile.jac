"""Lock file management for Jac projects.

This module handles creation, reading, and updating of jac.lock files
for reproducible dependency resolution.
"""

import hashlib;
import json;
import platform;
import sys;
import tomllib;
import from datetime { datetime }
import from pathlib { Path }
import from typing { Any }
import from jaclang.project.config { JacConfig }

# ===============================================================================
# Lock File Data Classes
# ===============================================================================
"""Represents metadata in a lock file."""
obj LockfileMetadata {
    has generated_at: str = "",
        jac_version: str = "",
        python_version: str = "",
        platform_name: str = "",
        config_hash: str = "";
}

"""Represents a locked package entry."""
obj LockedPackage {
    has name: str,
        version: str,
        hash: str = "",
        source: str = "pypi",
        dependencies: list[str] = [];
}

# ===============================================================================
# Lockfile Class
# ===============================================================================
"""Manages the jac.lock file for a project."""
obj Lockfile {
    has metadata: LockfileMetadata = LockfileMetadata(),
        packages: list[LockedPackage] = [],
        lockfile_path: Path | None = None;

    static def load(lockfile_path: Path) -> Lockfile | None;
    static def create(config: JacConfig, packages: list[LockedPackage]) -> Lockfile;
    def save -> None;
    def is_current(config: JacConfig) -> bool;
    def get_package(name: str) -> LockedPackage | None;
    static def hash_config(config: JacConfig) -> str;
}

# ===============================================================================
# Lock File Utilities
# ===============================================================================

# Get the lock file path for a project
def get_lockfile_path(
    config: JacConfig | None = None
) -> Path | None;

# Check if a lock file exists for the project
def lockfile_exists(
    config: JacConfig | None = None
) -> bool;
