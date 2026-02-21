"""Browser-level E2E tests for jac-client authentication flows."""

import gc;
import os;
import tempfile;
import time;
import pytest;
import from subprocess { Popen, run }

import from playwright.sync_api { Browser, Page, sync_playwright }

import from .test_helpers {
    get_env_with_npm,
    get_free_port,
    get_jac_command,
    wait_for_port
}

# ---- Helper functions (replacing fixtures) ----
def _fill_auth_form(
    page: Page, username: str, password: str
) -> None {
    """Fill username and password fields."""
    page.locator('input[type="text"], input[placeholder="Username" i]').first.fill(
        username
    );
    page.locator('input[type="password"]').first.fill(password);
}

def _submit_form(page: Page) -> None {
    """Click submit button and wait for navigation."""
    page.locator('button[type="submit"]').first.click();
    page.wait_for_timeout(2000);
}

def _signup(page: Page, base_url: str, username: str, password: str) -> None {
    """Navigate to signup, fill form, and submit."""
    page.goto(f"{base_url}/signup", wait_until="networkidle", timeout=60000);
    page.wait_for_selector('input[type="text"]', timeout=30000);
    _fill_auth_form(page, username, password);
    _submit_form(page);
}

def _login(page: Page, base_url: str, username: str, password: str) -> None {
    """Navigate to login, fill form, and submit."""
    page.goto(f"{base_url}/login", wait_until="networkidle", timeout=30000);
    page.wait_for_selector('input[type="text"]', timeout=30000);
    _fill_auth_form(page, username, password);
    _submit_form(page);
}

def _logout(page: Page) -> None {
    """Click logout button if visible."""
    logout_btn = page.locator('button:has-text("Logout")').first;
    if logout_btn.is_visible() {
        logout_btn.click();
        page.wait_for_timeout(1000);
    }
}

def _start_running_server -> tuple {
    """Start the all-in-one jac server and return (process, port, url, temp_dir, original_cwd)."""
    tests_dir = os.path.dirname(__file__);
    jac_client_root = os.path.dirname(tests_dir);
    all_in_one_path = os.path.join(jac_client_root, "examples", "all-in-one");

    if not os.path.isdir(all_in_one_path) {
        pytest.skip("all-in-one example directory not found");
    }

    app_name = "e2e-browser-test-app";
    jac_cmd = get_jac_command();
    env = get_env_with_npm();

    temp_dir = tempfile.mkdtemp();
    original_cwd = os.getcwd();
    os.chdir(temp_dir);

    # Create jacpack file from all-in-one example
    jacpack_path = os.path.join(temp_dir, "all-in-one.jacpack");
    pack_result = run(
        [*jac_cmd, "jacpack", "pack", all_in_one_path, "-o", jacpack_path],
        capture_output=True,
        text=True,
        env=env,
    );
    if pack_result.returncode != 0 {
        pytest.fail(f"jac jacpack pack failed: {pack_result.stderr}");
    }

    # Create project from jacpack file
    create_result = run(
        [*jac_cmd, "create", app_name, "--use", jacpack_path],
        capture_output=True,
        text=True,
        env=env,
    );
    if create_result.returncode != 0 {
        pytest.fail(f"jac create --use jacpack failed: {create_result.stderr}");
    }

    project_path = os.path.join(temp_dir, app_name);

    server_port = get_free_port();
    server = Popen(
        [*jac_cmd, "start", "-p", str(server_port)], cwd=project_path, env=env,
    );

    wait_for_port("127.0.0.1", server_port, timeout=90.0);
    time.sleep(5);
    return (
        server,
        server_port,
        f"http://127.0.0.1:{server_port}",
        temp_dir,
        original_cwd
    );
}

def _stop_running_server(server: Popen, temp_dir: str, original_cwd: str) -> None {
    """Stop the running server and clean up."""
    server.terminate();
    try {
        server.wait(timeout=15);
    } except Exception {
        server.kill();
        server.wait(timeout=5);
    }
    time.sleep(1);
    gc.collect();
    os.chdir(original_cwd);
    gc.collect();
}

test "navigate without auth redirects to login" {
    (server, port, url, temp_dir, original_cwd) = _start_running_server();
    try {
        with sync_playwright() as p {
            browser = p.chromium.launch(headless=True);
            context = browser.new_context();
            page = context.new_page();
            try {
                page.goto(f"{url}/nested", wait_until="networkidle", timeout=60000);
                page.wait_for_timeout(2000);
                assert "/login" in page.url.lower();
            } finally {
                context.close();
                browser.close();
            }
        }
    } finally {
        _stop_running_server(server, temp_dir, original_cwd);
    }
}

test "signup form submission" {
    (server, port, url, temp_dir, original_cwd) = _start_running_server();
    try {
        with sync_playwright() as p {
            browser = p.chromium.launch(headless=True);
            context = browser.new_context();
            page = context.new_page();
            try {
                _signup(page, url, f"e2e_signup_{int(time.time())}", "test_pass_123",);
                assert "/signup" not in page.url.lower();
            } finally {
                context.close();
                browser.close();
            }
        }
    } finally {
        _stop_running_server(server, temp_dir, original_cwd);
    }
}

test "login with valid credentials" {
    (server, port, url, temp_dir, original_cwd) = _start_running_server();
    try {
        with sync_playwright() as p {
            browser = p.chromium.launch(headless=True);
            context = browser.new_context();
            page = context.new_page();
            try {
                username = f"e2e_login_{int(time.time())}";
                password = "valid_pass_123";
                _signup(page, url, username, password);
                _logout(page);
                _login(page, url, username, password);
                assert "/login" not in page.url.lower()
                and "/signup" not in page.url.lower();
            } finally {
                context.close();
                browser.close();
            }
        }
    } finally {
        _stop_running_server(server, temp_dir, original_cwd);
    }
}

test "login with invalid credentials" {
    (server, port, url, temp_dir, original_cwd) = _start_running_server();
    try {
        with sync_playwright() as p {
            browser = p.chromium.launch(headless=True);
            context = browser.new_context();
            page = context.new_page();
            try {
                _login(page, url, "nonexistent_999", "wrong_pass");
                assert "/login" in page.url.lower();
                assert page.locator("text=/Invalid credentials/i").first.is_visible();
            } finally {
                context.close();
                browser.close();
            }
        }
    } finally {
        _stop_running_server(server, temp_dir, original_cwd);
    }
}

test "logout functionality" {
    (server, port, url, temp_dir, original_cwd) = _start_running_server();
    try {
        with sync_playwright() as p {
            browser = p.chromium.launch(headless=True);
            context = browser.new_context();
            page = context.new_page();
            try {
                _signup(page, url, f"e2e_logout_{int(time.time())}", "logout_pass_123");
                logout_btn = page.locator('button:has-text("Logout")').first;
                logout_btn.click();
                page.wait_for_timeout(1500);
                assert "/login" in page.url.lower()
                and not logout_btn.is_visible(timeout=5000);
            } finally {
                context.close();
                browser.close();
            }
        }
    } finally {
        _stop_running_server(server, temp_dir, original_cwd);
    }
}

test "complete auth flow" {
    (server, port, url, temp_dir, original_cwd) = _start_running_server();
    try {
        with sync_playwright() as p {
            browser = p.chromium.launch(headless=True);
            context = browser.new_context();
            page = context.new_page();
            try {
                username = f"e2e_complete_{int(time.time())}";
                password = "complete_pass_123";

                _signup(page, url, username, password);
                assert "/signup" not in page.url.lower();

                _logout(page);
                _login(page, url, username, password);
                assert "/login" not in page.url.lower();

                page.goto(f"{url}/nested", wait_until="networkidle", timeout=30000);
                assert "/nested" in page.url.lower();
            } finally {
                context.close();
                browser.close();
            }
        }
    } finally {
        _stop_running_server(server, temp_dir, original_cwd);
    }
}

def _start_priv_walker_server -> tuple {
    """Start the priv_walker_auth fixture server.

    Returns (process, port, url, temp_dir, original_cwd).
    """
    tests_dir = os.path.dirname(__file__);
    fixture_path = os.path.join(tests_dir, "fixtures", "priv_walker_auth");

    if not os.path.isdir(fixture_path) {
        pytest.skip("priv_walker_auth fixture directory not found");
    }

    app_name = "e2e-priv-walker-auth";
    jac_cmd = get_jac_command();
    env = get_env_with_npm();

    temp_dir = tempfile.mkdtemp();
    original_cwd = os.getcwd();
    os.chdir(temp_dir);

    # Create project from client template
    create_result = run(
        [*jac_cmd, "create", "--use", "client", app_name],
        capture_output=True,
        text=True,
        env=env,
    );
    if create_result.returncode != 0 {
        pytest.fail(f"jac create --use client failed: {create_result.stderr}");
    }

    project_path = os.path.join(temp_dir, app_name);

    # Copy fixture files into the project
    import shutil;
    for entry in os.listdir(fixture_path) {
        src = os.path.join(fixture_path, entry);
        dst = os.path.join(project_path, entry);
        if os.path.isdir(src) {
            shutil.copytree(src, dst, dirs_exist_ok=True);
        } else {
            shutil.copy2(src, dst);
        }
    }

    # Install npm packages
    add_result = run(
        [*jac_cmd, "add", "--npm"],
        cwd=project_path,
        capture_output=True,
        text=True,
        env=env,
    );
    if add_result.returncode != 0 {
        pytest.fail(f"jac add --npm failed: {add_result.stderr}");
    }

    server_port = get_free_port();
    server = Popen(
        [*jac_cmd, "start", "-p", str(server_port)], cwd=project_path, env=env,
    );

    wait_for_port("127.0.0.1", server_port, timeout=90.0);
    time.sleep(5);
    return (
        server,
        server_port,
        f"http://127.0.0.1:{server_port}",
        temp_dir,
        original_cwd
    );
}

test "stale token auto-clears on 401 from priv walker" {
    """Test that a stale JWT in localStorage is auto-cleared when a
    walker:priv endpoint returns 401, redirecting the user to login.

    This is the browser-level test for the auto-logout fix in
    client_runtime.impl.jac (__jacSpawn and __jacCallFunction).
    """(
        server, port, url, temp_dir, original_cwd
    ) = _start_priv_walker_server();
    try {
        with sync_playwright() as p {
            browser = p.chromium.launch(headless=True);
            context = browser.new_context();
            page = context.new_page();
            try {
                # Step 1: Fresh load should show login
                page.goto(url, wait_until="networkidle", timeout=60000);
                page.wait_for_timeout(3000);
                assert page.locator('#login-title:has-text("Sign In")').count() > 0 , (
                    "Fresh load should show Sign In form"
                );

                # Step 2: Inject a stale token into localStorage
                stale_token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VybmFtZSI6Im5vYm9keSJ9.totally_invalid";
                page.evaluate(
                    f'window.localStorage.setItem("jac_token", "{stale_token}")'
                );
                token_before = page.evaluate(
                    'window.localStorage.getItem("jac_token")'
                );
                assert token_before == stale_token , "Stale token should be in localStorage";

                # Step 3: Reload - app sees token, calls priv walker, gets 401
                # The runtime should auto-clear the token and reload
                page.reload(wait_until="networkidle", timeout=60000);
                page.wait_for_timeout(5000);

                # Step 4: Verify token was cleared and login screen is shown
                token_after = page.evaluate('window.localStorage.getItem("jac_token")');
                assert token_after is None or token_after == "" , (
                    f"Token should be cleared after 401, but got: {token_after}"
                );

                has_login = page.locator('#login-title:has-text("Sign In")').count() > 0;
                has_loading_stuck = page.locator('#notes-loading').count() > 0;
                assert has_login , "Should show login screen after 401 auto-logout";
                assert not has_loading_stuck , (
                    "Should NOT be stuck on 'Loading notes...' after 401"
                );

                # Step 5: Verify normal auth flow still works
                page.locator('#toggle-auth').click();
                page.wait_for_timeout(500);
                username = f"e2e_401_{int(time.time())}";
                page.locator('#username-input').fill(username);
                page.locator('#password-input').fill("test_pass_123");
                page.locator('#submit-btn').click();
                page.wait_for_timeout(3000);

                # Should now be in the main app
                assert page.locator('h1:has-text("Private Notes")').count() > 0 , (
                    "After signup, should see Private Notes"
                );
                assert page.locator('#notes-list').count() > 0 , (
                    "Notes list should be rendered (not stuck loading)"
                );
            } finally {
                context.close();
                browser.close();
            }
        }
    } finally {
        _stop_running_server(server, temp_dir, original_cwd);
    }
}
