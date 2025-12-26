"""Tests for Node.js helper utilities."""

import os
import platform
import subprocess
import tempfile

import pytest


class TestSetupNodeIntegration:
    """Integration tests for --setup-node flag (requires actual environment)."""

    @staticmethod
    def _get_jac_executable() -> str | None:
        """Get the path to jac executable, or None if not found."""
        import shutil
        import sys

        # Try to find jac in the same venv as this Python
        venv_jac = os.path.join(os.path.dirname(sys.executable), "jac")
        if os.path.exists(venv_jac):
            return venv_jac

        # Fall back to PATH lookup
        return shutil.which("jac")

    @staticmethod
    def _is_jac_client_installed(jac_path: str) -> bool:
        """Check if jac-client plugin is installed by looking for --cl flag."""
        from subprocess import run

        result = run(
            [jac_path, "create", "--help"],
            capture_output=True,
            text=True,
        )
        return "--cl" in result.stdout or "cl" in result.stdout

    @pytest.mark.skipif(
        platform.system() == "Windows", reason="--setup-node not supported on Windows"
    )
    def test_setup_node_flag_exists(self) -> None:
        """Test that --setup-node flag is recognized by jac create."""
        from subprocess import run

        jac_path = self._get_jac_executable()
        if jac_path is None:
            pytest.skip("jac executable not found")
            return  # Unreachable, but helps type checker

        if not self._is_jac_client_installed(jac_path):
            pytest.skip("jac-client plugin not installed")

        result = run(
            [jac_path, "create", "--help"],
            capture_output=True,
            text=True,
        )

        assert "setup-node" in result.stdout or "setup_node" in result.stdout

    @pytest.mark.skipif(
        platform.system() == "Windows", reason="--setup-node not supported on Windows"
    )
    def test_setup_node_with_existing_node(self) -> None:
        """Test --setup-node when Node.js is already installed."""
        import shutil
        from subprocess import run

        jac_path = self._get_jac_executable()
        if jac_path is None:
            pytest.skip("jac executable not found")
            return  # Unreachable, but helps type checker

        if not self._is_jac_client_installed(jac_path):
            pytest.skip("jac-client plugin not installed")

        # Check if node is installed
        if shutil.which("node") is None:
            pytest.skip("Node.js not installed, skipping integration test")

        with tempfile.TemporaryDirectory() as temp_dir:
            original_cwd = os.getcwd()
            try:
                os.chdir(temp_dir)

                result = run(
                    [jac_path, "create", "--cl", "--setup-node", "test-app"],
                    capture_output=True,
                    text=True,
                )

                # Should succeed since Node.js is already available
                assert result.returncode == 0
                assert "Using Node.js" in result.stdout

            finally:
                os.chdir(original_cwd)

    @pytest.mark.skipif(
        platform.system() == "Windows",
        reason="nvm installation not supported on Windows",
    )
    def test_nvm_install_nodejs_real(self) -> None:
        """Test actual Node.js installation via nvm in an isolated environment.

        This test actually downloads and installs nvm and Node.js to a temporary
        directory, verifies they work, then cleans up. It requires network access
        and takes some time to run.

        Run with: pytest -k test_nvm_install_nodejs_real -v
        """
        import shutil

        # Create a temporary directory for the nvm installation
        temp_home = tempfile.mkdtemp(prefix="jac_nvm_test_")
        nvm_dir = os.path.join(temp_home, ".nvm")

        try:
            # Set up environment for isolated nvm installation
            env = os.environ.copy()
            env["HOME"] = temp_home
            env["NVM_DIR"] = nvm_dir

            # Step 1: Download and run the nvm install script
            print(f"\n[Test] Installing nvm to {nvm_dir}...")
            nvm_install_result = subprocess.run(
                [
                    "bash",
                    "-c",
                    "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash",
                ],
                env=env,
                capture_output=True,
                text=True,
                timeout=120,
            )

            assert nvm_install_result.returncode == 0, (
                f"nvm install failed: {nvm_install_result.stderr}"
            )
            assert os.path.exists(os.path.join(nvm_dir, "nvm.sh")), (
                "nvm.sh not found after installation"
            )
            print("[Test] nvm installed successfully")

            # Step 2: Install Node.js LTS using nvm
            print("[Test] Installing Node.js LTS via nvm...")
            node_install_script = f"""
                export NVM_DIR="{nvm_dir}"
                source "$NVM_DIR/nvm.sh"
                nvm install --lts
                nvm use --lts
                node --version
                npm --version
            """
            node_install_result = subprocess.run(
                ["bash", "-c", node_install_script],
                env=env,
                capture_output=True,
                text=True,
                timeout=300,  # Node.js download can take a while
            )

            assert node_install_result.returncode == 0, (
                f"Node.js install failed: {node_install_result.stderr}"
            )
            print(f"[Test] Node.js installed: {node_install_result.stdout.strip()}")

            # Step 3: Verify node and npm are working
            verify_script = f"""
                export NVM_DIR="{nvm_dir}"
                source "$NVM_DIR/nvm.sh"
                node -e "console.log('Node.js is working!')"
                npm --version
            """
            verify_result = subprocess.run(
                ["bash", "-c", verify_script],
                env=env,
                capture_output=True,
                text=True,
                timeout=30,
            )

            assert verify_result.returncode == 0, (
                f"Verification failed: {verify_result.stderr}"
            )
            assert "Node.js is working!" in verify_result.stdout
            print("[Test] Node.js and npm verified working")

            # Step 4: Verify nvm installed node to the correct location
            versions_dir = os.path.join(nvm_dir, "versions", "node")
            assert os.path.exists(versions_dir), "Node versions directory not found"

            installed_versions = os.listdir(versions_dir)
            assert len(installed_versions) > 0, "No Node.js versions installed"
            print(f"[Test] Installed Node.js versions: {installed_versions}")

        finally:
            # Cleanup: Remove the temporary nvm installation
            print(f"[Test] Cleaning up {temp_home}...")
            if os.path.exists(temp_home):
                shutil.rmtree(temp_home, ignore_errors=True)
            print("[Test] Cleanup complete")
