"""Tests for client bundle generation."""

from __future__ import annotations

from collections.abc import Generator
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import pytest

from jaclang import JacRuntime as Jac
from jaclang.pycore.program import JacProgram


@pytest.fixture(scope="class", autouse=True)
def setup_jac_class(
    tmp_path_factory: pytest.TempPathFactory,
) -> Generator[None, None, None]:
    """Set up fresh Jac context once for all tests in this class."""
    tmp_dir = tmp_path_factory.mktemp("client_bundle")
    # Close existing context if any
    if Jac.exec_ctx is not None:
        Jac.exec_ctx.mem.close()
    Jac.loaded_modules.clear()
    Jac.base_path_dir = str(tmp_dir)
    Jac.program = JacProgram()
    Jac.pool = ThreadPoolExecutor()
    Jac.exec_ctx = Jac.create_j_context(user_root=None)
    yield
    if Jac.exec_ctx is not None:
        Jac.exec_ctx.mem.close()
    Jac.loaded_modules.clear()


def test_build_bundle_for_module():
    """Compile a Jac module and ensure client bundle metadata is emitted."""
    fixtures_dir = Path(__file__).parent / "fixtures"
    (module,) = Jac.jac_import("client_app", str(fixtures_dir))

    builder = Jac.get_client_bundle_builder()
    bundle = builder.build(module)

    # Check that actual client functions and globals are defined
    assert "function client_page()" in bundle.code
    assert "class ButtonProps" in bundle.code
    assert 'let API_LABEL = "Runtime Test";' in bundle.code
    # Check that module registration is present
    assert "__jacRegisterClientModule" in bundle.code
    assert "client_page" in bundle.client_functions
    assert "ButtonProps" in bundle.client_functions
    assert "API_LABEL" in bundle.client_globals
    assert len(bundle.hash) > 10

    cached = builder.build(module)
    assert bundle.hash == cached.hash
    assert bundle.code == cached.code


def test_build_bundle_with_cl_import():
    """Test that cl import statements are properly handled.

    With the @jac-client/utils syntax, imports from external packages like
    @jac-client/utils are kept as ES6 imports (not bundled inline). These
    are resolved at bundle time by Vite through alias configuration.
    """
    fixtures_dir = Path(__file__).parent / "fixtures"
    (module,) = Jac.jac_import("client_app_with_import", str(fixtures_dir))

    builder = Jac.get_client_bundle_builder()
    bundle = builder.build(module)

    # Check that our client code is present
    assert "function test_page()" in bundle.code
    assert 'let APP_TITLE = "Import Test App";' in bundle.code

    # ES6 import statements from external packages should be kept in the bundle
    # (they are resolved by Vite at bundle time through aliases)
    assert 'from "@jac-client/utils"' in bundle.code

    # Check that client functions are registered
    assert "test_page" in bundle.client_functions
    assert "APP_TITLE" in bundle.client_globals

    # Ensure the bundle has a valid hash
    assert len(bundle.hash) > 10


def test_build_bundle_with_relative_import():
    """Test that cl import from relative paths works correctly.

    Relative imports from local .jac files are bundled inline.
    External package imports (like @jac-client/utils) are kept as ES6 imports.
    """
    fixtures_dir = Path(__file__).parent / "fixtures"
    (module,) = Jac.jac_import("client_app_with_relative_import", str(fixtures_dir))

    builder = Jac.get_client_bundle_builder()
    bundle = builder.build(module)

    # Check that the imported module (client_ui_components) is included
    assert "// Imported .jac module: .client_ui_components" in bundle.code
    assert "function Button(" in bundle.code
    assert "function Card(" in bundle.code
    assert "function handleClick(" in bundle.code

    # Check that main_page is present
    assert "function main_page()" in bundle.code

    # ES6 import from @jac-client/utils should be kept (resolved by Vite)
    assert 'from "@jac-client/utils"' in bundle.code

    # Relative imports from .jac files should be bundled inline (no ES6 imports)
    assert 'from "./' not in bundle.code or 'from "@jac-client' in bundle.code

    # Verify client functions are registered
    assert "main_page" in bundle.client_functions


def test_no_relative_import_statements_in_bundle():
    """Test that relative import statements from .jac files are bundled inline.

    External package imports (like @jac-client/utils) are kept as ES6 imports
    since they are resolved by Vite at bundle time.
    """
    fixtures_dir = Path(__file__).parent / "fixtures"
    (module,) = Jac.jac_import("client_app_with_relative_import", str(fixtures_dir))

    builder = Jac.get_client_bundle_builder()
    bundle = builder.build(module)

    # Split bundle into lines and check for relative import statements
    lines = bundle.code.split("\n")
    import_lines = [
        line
        for line in lines
        if line.strip().startswith("import ") and " from " in line
    ]

    # Filter out external package imports (those are OK to keep)
    relative_import_lines = [
        line
        for line in import_lines
        if 'from "./' in line or "from './" in line
    ]

    # Should be exactly 0 relative import statements (bundled inline)
    assert len(relative_import_lines) == 0, (
        f"Found {len(relative_import_lines)} relative import(s): {relative_import_lines[:3]}"
    )


def test_transitive_imports_included():
    """Test that transitive imports from local .jac modules are included.

    Imports from external packages (like @jac-client/utils) are kept as ES6
    imports, not bundled inline.
    """
    fixtures_dir = Path(__file__).parent / "fixtures"
    (module,) = Jac.jac_import("client_app_with_relative_import", str(fixtures_dir))

    builder = Jac.get_client_bundle_builder()
    bundle = builder.build(module)

    # client_app_with_relative_import imports from client_ui_components
    # client_ui_components imports from @jac-client/utils (external)
    # So client_ui_components should be bundled, but @jac-client/utils is external

    # Check that local .jac module is included
    assert "// Imported .jac module: .client_ui_components" in bundle.code

    # External package imports are kept as ES6 imports (not bundled)
    assert 'from "@jac-client/utils"' in bundle.code


def test_bundle_size_reasonable():
    """Test that bundles with imports are reasonably sized."""
    fixtures_dir = Path(__file__).parent / "fixtures"

    # Simple module without imports
    (simple_module,) = Jac.jac_import("client_app", str(fixtures_dir))
    builder = Jac.get_client_bundle_builder()
    simple_bundle = builder.build(simple_module)

    # Module with imports
    (import_module,) = Jac.jac_import(
        "client_app_with_relative_import", str(fixtures_dir)
    )
    import_bundle = builder.build(import_module)

    # Bundle with imports should be larger (includes additional modules)
    assert len(import_bundle.code) > len(simple_bundle.code), (
        "Bundle with imports should be larger than simple bundle"
    )

    # But not unreasonably large (should be less than 10x)
    assert len(import_bundle.code) < len(simple_bundle.code) * 10, (
        "Bundle should not be unreasonably large"
    )


def test_import_path_conversion():
    """Test that Jac-style import paths are converted to JS paths."""
    from jaclang.pycore.modresolver import convert_to_js_import_path

    # Test single dot (current directory)
    assert convert_to_js_import_path(".module") == "./module.js"

    # Test double dot (parent directory)
    assert convert_to_js_import_path("..module") == "../module.js"

    # Test triple dot (grandparent directory)
    assert convert_to_js_import_path("...module") == "../../module.js"

    # Test absolute import (no dots)
    assert convert_to_js_import_path("module") == "module"


def test_cl_block_functions_exported():
    """Test that functions inside cl blocks are properly exported."""
    fixtures_dir = Path(__file__).parent / "fixtures"
    (module,) = Jac.jac_import("client_ui_components", str(fixtures_dir))

    builder = Jac.get_client_bundle_builder()
    bundle = builder.build(module)

    # Functions defined inside cl block should be in client_functions
    assert "Button" in bundle.client_functions
    assert "Card" in bundle.client_functions
    assert "handleClick" in bundle.client_functions

    # Check that functions are actually defined in the bundle
    assert "function Button(" in bundle.code
    assert "function Card(" in bundle.code
    assert "function handleClick(" in bundle.code


def test_bundle_caching_with_imports():
    """Test that bundle caching works correctly with imports."""
    fixtures_dir = Path(__file__).parent / "fixtures"
    (module,) = Jac.jac_import("client_app_with_relative_import", str(fixtures_dir))

    builder = Jac.get_client_bundle_builder()

    # Build bundle first time
    bundle1 = builder.build(module)

    # Build bundle second time (should use cache)
    bundle2 = builder.build(module)

    # Should be identical
    assert bundle1.hash == bundle2.hash
    assert bundle1.code == bundle2.code
    assert bundle1.client_functions == bundle2.client_functions

    # Force rebuild
    bundle3 = builder.build(module, force=True)

    # Should still be identical
    assert bundle1.hash == bundle3.hash
    assert bundle1.code == bundle3.code
