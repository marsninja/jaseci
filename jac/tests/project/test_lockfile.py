"""Tests for jaclang.project.lockfile module."""

from __future__ import annotations

from pathlib import Path

import pytest

from jaclang.project.config import JacConfig
from jaclang.project.lockfile import (
    LockedPackage,
    Lockfile,
    LockfileMetadata,
    get_lockfile_path,
    lockfile_exists,
)


class TestLockedPackage:
    """Tests for LockedPackage dataclass."""

    def test_create_locked_package(self) -> None:
        """Test creating a LockedPackage."""
        pkg = LockedPackage(
            name="requests",
            version="2.28.0",
            hash="sha256:abc123",
            source="pypi",
            dependencies=["urllib3", "certifi"],
        )

        assert pkg.name == "requests"
        assert pkg.version == "2.28.0"
        assert pkg.hash == "sha256:abc123"
        assert pkg.source == "pypi"
        assert pkg.dependencies == ["urllib3", "certifi"]

    def test_locked_package_defaults(self) -> None:
        """Test LockedPackage default values."""
        pkg = LockedPackage(name="minimal", version="1.0.0")

        assert pkg.hash == ""
        assert pkg.source == "pypi"
        assert pkg.dependencies == []


class TestLockfileMetadata:
    """Tests for LockfileMetadata dataclass."""

    def test_create_metadata(self) -> None:
        """Test creating LockfileMetadata."""
        meta = LockfileMetadata(
            generated_at="2024-01-15T10:30:00Z",
            jac_version="0.9.3",
            python_version="3.11.5",
            platform_name="linux",
            config_hash="abc123def456",
        )

        assert meta.generated_at == "2024-01-15T10:30:00Z"
        assert meta.jac_version == "0.9.3"
        assert meta.python_version == "3.11.5"
        assert meta.platform_name == "linux"
        assert meta.config_hash == "abc123def456"

    def test_metadata_defaults(self) -> None:
        """Test LockfileMetadata default values."""
        meta = LockfileMetadata()

        assert meta.generated_at == ""
        assert meta.jac_version == ""
        assert meta.python_version == ""
        assert meta.platform_name == ""
        assert meta.config_hash == ""


class TestLockfileCreate:
    """Tests for creating lockfiles."""

    def test_create_lockfile(self, temp_project: Path) -> None:
        """Test creating a new lockfile."""
        config = JacConfig.load(temp_project / "jac.toml")

        packages = [
            LockedPackage(name="requests", version="2.28.0", source="pypi"),
            LockedPackage(name="urllib3", version="1.26.0", source="pypi"),
        ]

        lockfile = Lockfile.create(config, packages)

        assert lockfile.metadata.jac_version != ""
        assert lockfile.metadata.python_version != ""
        assert lockfile.metadata.platform_name != ""
        assert lockfile.metadata.config_hash != ""
        assert len(lockfile.packages) == 2
        assert lockfile.lockfile_path == temp_project / "jac.lock"

    def test_create_lockfile_sets_timestamp(self, temp_project: Path) -> None:
        """Test that create sets generated_at timestamp."""
        config = JacConfig.load(temp_project / "jac.toml")

        lockfile = Lockfile.create(config, [])

        assert lockfile.metadata.generated_at != ""
        assert lockfile.metadata.generated_at.endswith("Z")


class TestLockfileHashConfig:
    """Tests for config hashing."""

    def test_hash_config_deterministic(self, temp_project: Path) -> None:
        """Test that hash_config is deterministic."""
        config = JacConfig.load(temp_project / "jac.toml")

        hash1 = Lockfile.hash_config(config)
        hash2 = Lockfile.hash_config(config)

        assert hash1 == hash2
        assert len(hash1) == 16  # SHA256 truncated to 16 chars

    def test_hash_config_changes_with_deps(self) -> None:
        """Test that hash changes when dependencies change."""
        config1 = JacConfig()
        config1.dependencies = {"requests": ">=2.28.0"}

        config2 = JacConfig()
        config2.dependencies = {"requests": ">=2.29.0"}

        hash1 = Lockfile.hash_config(config1)
        hash2 = Lockfile.hash_config(config2)

        assert hash1 != hash2

    def test_hash_config_changes_with_new_dep(self) -> None:
        """Test that hash changes when new dependency is added."""
        config1 = JacConfig()
        config1.dependencies = {"requests": ">=2.28.0"}

        config2 = JacConfig()
        config2.dependencies = {"requests": ">=2.28.0", "numpy": ">=1.24.0"}

        hash1 = Lockfile.hash_config(config1)
        hash2 = Lockfile.hash_config(config2)

        assert hash1 != hash2


class TestLockfileSaveLoad:
    """Tests for saving and loading lockfiles."""

    def test_save_and_load(self, temp_project: Path) -> None:
        """Test saving and loading a lockfile."""
        config = JacConfig.load(temp_project / "jac.toml")

        packages = [
            LockedPackage(
                name="requests",
                version="2.28.0",
                hash="sha256:abc123",
                source="pypi",
                dependencies=["urllib3"],
            ),
        ]

        lockfile = Lockfile.create(config, packages)
        lockfile.save()

        # Verify file was created
        assert lockfile.lockfile_path is not None
        assert lockfile.lockfile_path.exists()

        # Load and verify
        loaded = Lockfile.load(lockfile.lockfile_path)

        assert loaded is not None
        assert loaded.metadata.jac_version == lockfile.metadata.jac_version
        assert loaded.metadata.config_hash == lockfile.metadata.config_hash
        assert len(loaded.packages) == 1
        assert loaded.packages[0].name == "requests"
        assert loaded.packages[0].version == "2.28.0"
        assert loaded.packages[0].hash == "sha256:abc123"
        assert loaded.packages[0].dependencies == ["urllib3"]

    def test_load_nonexistent_returns_none(self, temp_dir: Path) -> None:
        """Test loading nonexistent lockfile returns None."""
        result = Lockfile.load(temp_dir / "nonexistent.lock")
        assert result is None

    def test_save_without_path_raises(self) -> None:
        """Test saving without path raises error."""
        lockfile = Lockfile()
        lockfile.lockfile_path = None

        with pytest.raises(ValueError, match="No lockfile_path set"):
            lockfile.save()

    def test_lockfile_has_header_comment(self, temp_project: Path) -> None:
        """Test that saved lockfile has header comment."""
        config = JacConfig.load(temp_project / "jac.toml")
        lockfile = Lockfile.create(config, [])
        lockfile.save()

        assert lockfile.lockfile_path is not None
        content = lockfile.lockfile_path.read_text()

        assert "# jac.lock - Auto-generated" in content


class TestLockfileIsCurrent:
    """Tests for checking if lockfile is current."""

    def test_is_current_true(self, temp_project: Path) -> None:
        """Test lockfile is current when config hasn't changed."""
        config = JacConfig.load(temp_project / "jac.toml")

        lockfile = Lockfile.create(config, [])

        assert lockfile.is_current(config) is True

    def test_is_current_false_after_change(self, temp_project: Path) -> None:
        """Test lockfile is not current after config change."""
        config = JacConfig.load(temp_project / "jac.toml")

        lockfile = Lockfile.create(config, [])

        # Modify config
        config.dependencies["numpy"] = ">=1.24.0"

        assert lockfile.is_current(config) is False


class TestLockfileGetPackage:
    """Tests for getting packages from lockfile."""

    def test_get_package_exists(self) -> None:
        """Test getting a package that exists."""
        lockfile = Lockfile()
        lockfile.packages = [
            LockedPackage(name="requests", version="2.28.0"),
            LockedPackage(name="numpy", version="1.24.0"),
        ]

        pkg = lockfile.get_package("requests")

        assert pkg is not None
        assert pkg.name == "requests"
        assert pkg.version == "2.28.0"

    def test_get_package_not_exists(self) -> None:
        """Test getting a package that doesn't exist."""
        lockfile = Lockfile()
        lockfile.packages = [
            LockedPackage(name="requests", version="2.28.0"),
        ]

        pkg = lockfile.get_package("nonexistent")

        assert pkg is None

    def test_get_package_case_insensitive(self) -> None:
        """Test that package lookup is case-insensitive."""
        lockfile = Lockfile()
        lockfile.packages = [
            LockedPackage(name="Requests", version="2.28.0"),
        ]

        pkg = lockfile.get_package("requests")

        assert pkg is not None
        assert pkg.name == "Requests"

    def test_get_package_normalizes_dashes(self) -> None:
        """Test that package lookup normalizes dashes to underscores."""
        lockfile = Lockfile()
        lockfile.packages = [
            LockedPackage(name="jac-byllm", version="0.4.8"),
        ]

        pkg = lockfile.get_package("jac_byllm")

        assert pkg is not None
        assert pkg.name == "jac-byllm"


class TestLockfileUtilities:
    """Tests for lockfile utility functions."""

    def test_get_lockfile_path(self, temp_project: Path) -> None:
        """Test getting lockfile path from config."""
        config = JacConfig.load(temp_project / "jac.toml")

        path = get_lockfile_path(config)

        assert path == temp_project / "jac.lock"

    def test_get_lockfile_path_no_config(self) -> None:
        """Test getting lockfile path with no config."""
        path = get_lockfile_path(None)
        assert path is None

    def test_lockfile_exists_true(self, temp_project: Path) -> None:
        """Test lockfile_exists when file exists."""
        config = JacConfig.load(temp_project / "jac.toml")

        # Create a lockfile
        lockfile_path = temp_project / "jac.lock"
        lockfile_path.write_text("# jac.lock\n")

        assert lockfile_exists(config) is True

    def test_lockfile_exists_false(self, temp_project: Path) -> None:
        """Test lockfile_exists when file doesn't exist."""
        config = JacConfig.load(temp_project / "jac.toml")

        # Ensure no lockfile
        lockfile_path = temp_project / "jac.lock"
        if lockfile_path.exists():
            lockfile_path.unlink()

        assert lockfile_exists(config) is False

    def test_lockfile_exists_no_config(self) -> None:
        """Test lockfile_exists with no config."""
        assert lockfile_exists(None) is False


class TestLockfileParseEdgeCases:
    """Tests for parsing edge cases in lockfiles."""

    def test_load_empty_packages(self, temp_dir: Path) -> None:
        """Test loading lockfile with no packages."""
        lockfile_path = temp_dir / "jac.lock"
        lockfile_path.write_text("""
[metadata]
generated_at = "2024-01-15T10:30:00Z"
jac_version = "0.9.3"
python_version = "3.11.5"
platform = "linux"
config_hash = "abc123"
""")

        lockfile = Lockfile.load(lockfile_path)

        assert lockfile is not None
        assert len(lockfile.packages) == 0
        assert lockfile.metadata.jac_version == "0.9.3"

    def test_load_multiple_packages(self, temp_dir: Path) -> None:
        """Test loading lockfile with multiple packages."""
        lockfile_path = temp_dir / "jac.lock"
        lockfile_path.write_text("""
[metadata]
generated_at = "2024-01-15T10:30:00Z"
jac_version = "0.9.3"
python_version = "3.11.5"
platform = "linux"
config_hash = "abc123"

[[package]]
name = "requests"
version = "2.28.0"
source = "pypi"

[[package]]
name = "numpy"
version = "1.24.0"
source = "pypi"
dependencies = ["openblas"]

[[package]]
name = "my-plugin"
version = "1.0.0"
source = "git"
""")

        lockfile = Lockfile.load(lockfile_path)

        assert lockfile is not None
        assert len(lockfile.packages) == 3

        # Verify each package
        requests_pkg = lockfile.get_package("requests")
        assert requests_pkg is not None
        assert requests_pkg.version == "2.28.0"

        numpy_pkg = lockfile.get_package("numpy")
        assert numpy_pkg is not None
        assert numpy_pkg.dependencies == ["openblas"]

        plugin_pkg = lockfile.get_package("my-plugin")
        assert plugin_pkg is not None
        assert plugin_pkg.source == "git"
