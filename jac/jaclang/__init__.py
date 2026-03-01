"""The Jac Programming Language."""

import os
import sys

# Vendor path for bundled dependencies (lsprotocol, pygls).
_vendor_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "vendor")
if _vendor_dir not in sys.path:
    sys.path.insert(0, _vendor_dir)

# Meta importer enables `import` of .jac files as Python modules.
from jaclang.meta_importer import JacMetaImporter  # noqa: E402

if not any(isinstance(f, JacMetaImporter) for f in sys.meta_path):
    sys.meta_path.insert(0, JacMetaImporter())


# Backward-compat re-exports. Prefer `from jaclang.jac0core.runtime import ...`.
def __getattr__(name: str) -> object:
    _lazy_names = {
        "JacRuntime",
        "JacRuntimeInterface",
        "JacRuntimeImpl",
        "plugin_manager",
    }
    if name in _lazy_names:
        from jaclang.jac0core import runtime

        return getattr(runtime, name)
    raise AttributeError(f"module 'jaclang' has no attribute {name!r}")


__all__ = ["JacRuntimeInterface", "JacRuntime"]
