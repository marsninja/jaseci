"""Test that stale JWT tokens are auto-cleared on 401 from priv walker endpoints.

This is a standalone integration test for the auto-logout fix in
client_runtime.impl.jac. It tests both:
  1. Server returns 401 for stale tokens on walker:priv endpoints (HTTP-level)
  2. Client runtime auto-clears stale tokens and shows login screen (browser-level)

Run with:
    python -m pytest jac-client/jac_client/tests/test_401_auto_logout.py -x -v

Requires: playwright, jac, jac-client, jac-scale
"""

import gc
import json
import os
import shutil

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
import socket
import tempfile
import time
from pathlib import Path
from subprocess import Popen, run
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

import pytest


def _get_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("", 0))
        s.listen(1)
        return s.getsockname()[1]


def _get_jac_command() -> list[str]:
    jac_path = shutil.which("jac")
    if jac_path:
        return [jac_path]
    import sys

    return [sys.executable, "-m", "jaclang"]


def _wait_for_port(host: str, port: int, timeout: float = 60.0) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.5)
            try:
                sock.connect((host, port))
                return
            except OSError:
                time.sleep(0.5)
    raise TimeoutError(f"Timed out waiting for {host}:{port}")


def _wait_for_endpoint(url: str, timeout: float = 120.0) -> bytes:
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with urlopen(url, timeout=30) as resp:
                return resp.read()
        except (URLError, HTTPError, ConnectionError) as exc:
            if isinstance(exc, HTTPError) and exc.code not in (503,):
                raise
            time.sleep(2)
    raise TimeoutError(f"Timed out waiting for {url}")


def _get_env_with_bun() -> dict[str, str]:
    env = os.environ.copy()
    bun_path = shutil.which("bun")
    if bun_path:
        bun_dir = str(Path(bun_path).parent)
        current_path = env.get("PATH", "")
        if bun_dir not in current_path:
            env["PATH"] = f"{bun_dir}:{current_path}"
    return env


# ---------------------------------------------------------------------------
# Fixture: start/stop server with priv_walker_auth app
# ---------------------------------------------------------------------------

FIXTURE_PATH = Path(__file__).parent / "fixtures" / "priv_walker_auth"


@pytest.fixture(scope="module")
def priv_walker_server():
    """Start a jac server with walker:priv endpoints for testing."""
    if not FIXTURE_PATH.is_dir():
        pytest.skip("priv_walker_auth fixture not found")

    jac_cmd = _get_jac_command()
    env = _get_env_with_bun()
    temp_dir = tempfile.mkdtemp()
    original_cwd = os.getcwd()
    os.chdir(temp_dir)

    try:
        app_name = "test-401-app"

        # Create project
        result = run(
            [*jac_cmd, "create", "--use", "client", app_name],
            capture_output=True,
            text=True,
            env=env,
        )
        if result.returncode != 0:
            pytest.skip(f"jac create --use client failed: {result.stderr}")

        project_path = os.path.join(temp_dir, app_name)

        # Copy fixture files
        for entry in os.listdir(FIXTURE_PATH):
            src = os.path.join(FIXTURE_PATH, entry)
            dst = os.path.join(project_path, entry)
            if os.path.isdir(src):
                shutil.copytree(src, dst, dirs_exist_ok=True)
            else:
                shutil.copy2(src, dst)

        # Install npm packages
        add_result = run(
            [*jac_cmd, "add", "--npm"],
            cwd=project_path,
            capture_output=True,
            text=True,
            env=env,
        )
        if add_result.returncode != 0:
            pytest.skip(f"jac add --npm failed: {add_result.stderr}")

        # Start server
        port = _get_free_port()
        server = Popen(
            [*jac_cmd, "start", "-p", str(port)],
            cwd=project_path,
            env=env,
        )

        _wait_for_port("127.0.0.1", port, timeout=90)
        _wait_for_endpoint(f"http://127.0.0.1:{port}", timeout=120)
        time.sleep(3)

        yield {
            "server": server,
            "port": port,
            "url": f"http://127.0.0.1:{port}",
        }
    finally:
        # Cleanup
        try:
            server.terminate()
            server.wait(timeout=15)
        except Exception:
            try:
                server.kill()
                server.wait(timeout=5)
            except Exception:
                pass
        time.sleep(1)
        gc.collect()
        os.chdir(original_cwd)
        gc.collect()


# ---------------------------------------------------------------------------
# HTTP-level tests
# ---------------------------------------------------------------------------


class TestPrivWalker401:
    """Server-side: walker:priv returns 401 for invalid tokens."""

    def test_valid_token_succeeds(self, priv_walker_server: dict) -> None:
        """A valid JWT should get 200 from a priv walker."""
        url = priv_walker_server["url"]

        # Register a user
        req = Request(
            f"{url}/user/register",
            data=json.dumps({"username": "valid_user", "password": "test123"}).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urlopen(req, timeout=20) as resp:
            data = json.loads(resp.read())
            token = data["data"]["token"]

        # Call priv walker with valid token
        req = Request(
            f"{url}/walker/get_notes",
            data=b"{}",
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {token}",
            },
            method="POST",
        )
        with urlopen(req, timeout=20) as resp:
            assert resp.status == 200

    def test_stale_token_returns_401(self, priv_walker_server: dict) -> None:
        """A stale/invalid JWT should get 401 from a priv walker."""
        url = priv_walker_server["url"]
        stale_token = (
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VybmFtZSI6Im5vYm9keSJ9.invalid"
        )

        req = Request(
            f"{url}/walker/get_notes",
            data=b"{}",
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {stale_token}",
            },
            method="POST",
        )
        with pytest.raises(HTTPError) as exc_info:
            urlopen(req, timeout=20)
        assert exc_info.value.code == 401

    def test_no_token_returns_401(self, priv_walker_server: dict) -> None:
        """No token at all should get 401 from a priv walker."""
        url = priv_walker_server["url"]

        req = Request(
            f"{url}/walker/get_notes",
            data=b"{}",
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with pytest.raises(HTTPError) as exc_info:
            urlopen(req, timeout=20)
        assert exc_info.value.code == 401


# ---------------------------------------------------------------------------
# Browser-level test
# ---------------------------------------------------------------------------


class TestAutoLogoutOn401:
    """Client-side: stale token is auto-cleared on 401, showing login."""

    def test_stale_token_auto_clears_and_shows_login(
        self, priv_walker_server: dict
    ) -> None:
        """Inject stale token -> reload -> runtime detects 401 ->
        clears token -> shows login screen (not stuck on loading)."""
        try:
            from playwright.sync_api import sync_playwright
        except ImportError:
            pytest.skip("playwright not installed")

        url = priv_walker_server["url"]
        stale = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VybmFtZSI6Im5vYm9keSJ9.totally_invalid"

        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            context = browser.new_context()
            page = context.new_page()
            try:
                # Fresh load -> login screen
                page.goto(url, wait_until="networkidle", timeout=60000)
                page.wait_for_timeout(3000)
                assert page.locator('#login-title:has-text("Sign In")').count() > 0, (
                    "Fresh load should show login"
                )

                # Inject stale token
                page.evaluate(f'window.localStorage.setItem("jac_token", "{stale}")')

                # Reload - triggers priv walker call -> 401 -> auto-clear -> reload
                page.reload(wait_until="networkidle", timeout=60000)
                page.wait_for_timeout(5000)

                # Token should be cleared
                token = page.evaluate('window.localStorage.getItem("jac_token")')
                assert token is None or token == "", (
                    f"Token should be cleared after 401, got: {token}"
                )

                # Should show login, not stuck loading
                assert page.locator('#login-title:has-text("Sign In")').count() > 0, (
                    "Should show login after auto-logout"
                )
                assert page.locator("#notes-loading").count() == 0, (
                    "Should NOT be stuck on loading"
                )
            finally:
                context.close()
                browser.close()

    def test_normal_auth_flow_still_works(self, priv_walker_server: dict) -> None:
        """Signup -> see app -> logout -> login works normally."""
        try:
            from playwright.sync_api import sync_playwright
        except ImportError:
            pytest.skip("playwright not installed")

        url = priv_walker_server["url"]

        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            context = browser.new_context()
            page = context.new_page()
            try:
                # Go to app
                page.goto(url, wait_until="networkidle", timeout=60000)
                page.wait_for_timeout(3000)

                # Switch to signup
                page.locator("#toggle-auth").click()
                page.wait_for_timeout(500)

                # Create account
                username = f"e2e_normal_{int(time.time())}"
                page.locator("#username-input").fill(username)
                page.locator("#password-input").fill("test_pass_123")
                page.locator("#submit-btn").click()
                page.wait_for_timeout(3000)

                # Should be in main app
                assert page.locator('h1:has-text("Private Notes")').count() > 0

                # Logout
                page.locator("#logout-btn").click()
                page.wait_for_timeout(2000)
                login_visible = (
                    page.locator('#login-title:has-text("Sign In")').count() > 0
                    or page.locator('#login-title:has-text("Create Account")').count()
                    > 0
                )
                assert login_visible, "Should show auth form after logout"

                # Login again
                # Ensure we're on the Sign In form
                if page.locator('#login-title:has-text("Create Account")').count() > 0:
                    page.locator("#toggle-auth").click()
                    page.wait_for_timeout(500)
                page.locator("#username-input").fill(username)
                page.locator("#password-input").fill("test_pass_123")
                page.locator("#submit-btn").click()
                page.wait_for_timeout(3000)

                assert page.locator('h1:has-text("Private Notes")').count() > 0
            finally:
                context.close()
                browser.close()
