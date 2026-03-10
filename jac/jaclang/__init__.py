"""The Jac Programming Language."""

import importlib.metadata
import json
import pathlib
import sys

from jaclang.meta_importer import JacMetaImporter  # noqa: E402

# Register JacMetaImporter BEFORE loading plugins, so .jac modules can be imported
if not any(isinstance(f, JacMetaImporter) for f in sys.meta_path):
    sys.meta_path.insert(0, JacMetaImporter())

# Import compiler first to ensure generated parsers exist before jac0core.parser is loaded
# Backwards-compatible import path for older plugins/tests.
# Prefer `jaclang.jac0core.runtime` going forward.
import jaclang.jac0core.runtime as _runtime_mod  # noqa: E402
from jaclang import compiler as _compiler  # noqa: E402, F401
from jaclang.jac0core.helpers import get_disabled_plugins  # noqa: E402
from jaclang.jac0core.runtime import (  # noqa: E402
    JacRuntime,
    JacRuntimeImpl,
    JacRuntimeInterface,
    plugin_manager,
)

sys.modules.setdefault("jaclang.runtimelib.runtime", _runtime_mod)

plugin_manager.register(JacRuntimeImpl)


def _read_jac_manifest() -> dict[str, dict]:
    """Read [tool.jac] from each distribution's source pyproject.toml.

    Returns a dict of {dist_name: {hooks: {...}, commands: {...}, extensions: {...}, ...}}.
    Only works for editable installs (which have direct_url.json pointing to source).
    Falls back gracefully — missing manifests mean eager loading.
    """
    try:
        import tomllib
    except ImportError:
        try:
            import tomli as tomllib  # type: ignore[no-redef]
        except ImportError:
            return {}

    result: dict[str, dict] = {}
    for dist in importlib.metadata.distributions():
        dist_name = dist.metadata.get("Name", "")
        # Only check distributions that have jac entry points.
        has_jac_ep = any(ep.group == "jac" for ep in dist.entry_points)
        if not has_jac_ep:
            continue
        # Find source pyproject.toml via direct_url.json (editable installs).
        try:
            du_text = dist.read_text("direct_url.json")
            if not du_text:
                continue
            info = json.loads(du_text)
            url = info.get("url", "")
            if not url.startswith("file://"):
                continue
            src_dir = pathlib.Path(url[7:])
            pyproject = src_dir / "pyproject.toml"
            if not pyproject.exists():
                continue
            with open(pyproject, "rb") as f:
                data = tomllib.load(f)
            jac_section = data.get("tool", {}).get("jac", {})
            if jac_section:
                result[dist_name] = jac_section
        except Exception:
            continue
    return result


# Lazy plugin loading: discover entry points and register them lazily.
# Plugins with a [tool.jac.hooks] manifest are deferred until their hooks are called.
# Plugins without a manifest fall back to eager loading (backwards compat).
# Disabling via JAC_DISABLED_PLUGINS env var or jac.toml [plugins].disabled is honored.
_disabled_list = get_disabled_plugins()
_disable_all = "*" in _disabled_list

# Read full [tool.jac] manifest from all distributions.
# Contains hooks, commands, extensions metadata.
_jac_manifest: dict[str, dict] = {}

if not _disable_all:
    _jac_manifest = _read_jac_manifest()

    # Build a flat map: ep_name -> "hook1,hook2,..." from all distributions.
    _hooks_manifest: dict[str, str] = {}
    for _dist_manifest in _jac_manifest.values():
        _dist_hooks = _dist_manifest.get("hooks", {})
        _hooks_manifest.update(_dist_hooks)

    # Register each jac entry point lazily or eagerly based on manifest.
    try:
        _jac_eps = importlib.metadata.entry_points(group="jac")
    except TypeError:
        _jac_eps = importlib.metadata.entry_points().get("jac", [])  # type: ignore[attr-defined]

    for _ep in _jac_eps:
        if _ep.name in plugin_manager._name2plugin:
            continue
        hook_csv = _hooks_manifest.get(_ep.name)
        if hook_csv is not None:
            hook_names = [h.strip() for h in hook_csv.split(",") if h.strip()]
            plugin_manager.register_lazy_entrypoint(
                _ep, hook_names=hook_names, disabled=_disabled_list
            )
        else:
            # No manifest — eager fallback for legacy/third-party plugins.
            plugin_manager.register_lazy_entrypoint(
                _ep, hook_names=None, disabled=_disabled_list
            )

# Schedule deferred native acceleration if autonative is enabled in jac.toml
try:
    from jaclang.project.config import get_config as _get_jac_config

    _jac_cfg = _get_jac_config()
    if _jac_cfg and _jac_cfg.run.autonative:
        from jaclang.jac0core.native_accel import schedule_native_acceleration

        schedule_native_acceleration()
except Exception:
    pass  # Config not available or acceleration failed — continue normally

__all__ = ["JacRuntimeInterface", "JacRuntime"]
