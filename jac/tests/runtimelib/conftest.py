"""Pytest configuration and fixtures for runtimelib tests."""

from __future__ import annotations

from collections.abc import Generator
from pathlib import Path

import pytest


def fixture_abs_path(fixture: str) -> str:
    """Get absolute path of a fixture from the runtimelib fixtures directory.

    This is a standalone helper function for use in helper classes and functions
    that need fixture paths outside of test functions.

    Note: For test functions, use the pytest fixture_path fixture from root conftest.py.
    """
    fixtures_dir = Path(__file__).parent / "fixtures"
    return str((fixtures_dir / fixture).resolve())


@pytest.fixture(autouse=True)
def disable_jac_client_plugin() -> Generator[None, None, None]:
    """Disable jac-client plugin for runtimelib tests.

    The jac-client plugin overrides client bundle building hooks with its own
    implementation. These tests need to use the internal jaclang bundler,
    so we temporarily unregister the jac-client plugins during test execution.
    """
    from jaclang.pycore.runtime import plugin_manager

    # Store unregistered plugins to re-register after test
    unregistered_plugins: list[tuple[str, object]] = []

    # Plugin names registered by jac-client (from entry point names in pyproject.toml)
    jac_client_plugin_names = ["serve", "cli", "plugin_config"]

    for name in jac_client_plugin_names:
        plugin = plugin_manager.get_plugin(name)
        if plugin is not None:
            plugin_manager.unregister(name=name)
            unregistered_plugins.append((name, plugin))

    yield

    # Re-register plugins after test
    for name, plugin in unregistered_plugins:
        if not plugin_manager.is_registered(plugin):
            plugin_manager.register(plugin, name=name)
