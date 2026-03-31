"""Tests for the bun auto-installer (get_bun / ensure_bun_available)."""

import os;
import shutil;
import tempfile;

import from pathlib { Path }
import from unittest.mock { patch }
import from jac_client.plugin.utils.bun_installer {
    get_bun,
    ensure_bun_available,
    _get_jac_bin_dir,
    _get_platform_asset,
    BUN_VERSION
}


"""Platform asset name should be non-None on supported platforms."""
test "platform asset resolves" {
    asset = _get_platform_asset();
    assert asset is not None, "Unsupported platform for bun";
    assert "bun-" in asset, f"Unexpected asset name: {asset}";
}


"""get_bun should return system bun when available on PATH."""
test "get bun prefers system path" {
    system_bun = shutil.which("bun");
    if system_bun {
        result = get_bun();
        assert result == system_bun, (
            f"Expected system bun ({system_bun}), got: {result}"
        );
    }
}


"""get_bun should return a valid path to a bun binary."""
test "get bun returns valid path" {
    result = get_bun();
    assert result is not None, "get_bun() returned None";
    assert os.path.isabs(result), f"Expected absolute path, got: {result}";
    assert os.path.exists(result), f"Binary does not exist: {result}";
}


"""get_bun should auto-download when bun is not on PATH."""
test "get bun auto downloads when not on path" {
    # Hide system bun from PATH
    original_path = os.environ.get("PATH", "");
    # Remove any directory containing bun from PATH
    filtered = os.pathsep.join(
        d for d in original_path.split(os.pathsep)
        if not os.path.exists(os.path.join(d, "bun"))
    );
    with tempfile.TemporaryDirectory() as tmp {
        # Create a minimal jac project so get_config() finds a project root
        jac_toml = os.path.join(tmp, "jac.toml");
        with open(jac_toml, "w") as f {
            f.write('[project]\nname = "bun-test"\n');
        }
        original_cwd = os.getcwd();
        try {
            os.chdir(tmp);
            with patch.dict(os.environ, {"PATH": filtered}) {
                # Clear any cached config
                import from jaclang.project.config { set_config }
                set_config(None);
                result = get_bun();
                assert result is not None, "get_bun() returned None without system bun";
                assert ".jac" in result, f"Expected .jac in path, got: {result}";
                assert os.path.exists(result), f"Downloaded binary not found: {result}";

                # Verify the version file was written
                bin_dir = Path(result).parent;
                version_file = bin_dir / ".bun-version";
                assert version_file.exists(), "Version file not written";
                assert version_file.read_text().strip() == BUN_VERSION;
            }
        } finally {
            os.chdir(original_cwd);
            # Reset config
            import from jaclang.project.config { set_config }
            set_config(None);
        }
    }
}


"""ensure_bun_available should return True and add bun dir to PATH."""
test "ensure bun available adds to path" {
    result = ensure_bun_available();
    assert result is True, "ensure_bun_available() returned False";
    # After ensure_bun_available, bun should be findable via which
    bun = shutil.which("bun");
    assert bun is not None, "bun not on PATH after ensure_bun_available()";
}
