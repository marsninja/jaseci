"""Single source of truth for jac's global on-disk cache locations.

Pure Python with no jac dependencies, so it is importable during bootstrap —
before the jac0core ``.jac`` modules have been transpiled. Both the bootstrap
bytecode cache (``meta_importer``) and the JIR module cache
(``jaclang.jac0core.jir``) derive their directories from here, so the
platform-resolution logic lives in exactly one place.

Layout under the platform cache root::

    <root>/jac/jir/              # JIR cache namespace (get_jir_cache_dir)
    <root>/jac/jir/modules/      # serialized type-checked user modules
    <root>/jac/jir/native/       # native LLVM IR / object artifacts (global)
    <root>/jac/jir/bootstrap/    # marshalled jac0core bootstrap bytecode (.jbc)

Platform roots:
    Linux:   ~/.cache/jac/jir/             ($XDG_CACHE_HOME honored)
    macOS:   ~/Library/Caches/jac/jir/
    Windows: %LOCALAPPDATA%/jac/cache/jir/
"""

import os
import sys
from pathlib import Path


def get_jir_cache_dir() -> Path:
    """Return the platform-appropriate global cache directory for JIR files."""
    if sys.platform == "win32":
        base = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local"))
        return base / "jac" / "cache" / "jir"
    elif sys.platform == "darwin":
        return Path.home() / "Library" / "Caches" / "jac" / "jir"
    else:
        xdg = os.environ.get("XDG_CACHE_HOME")
        base = Path(xdg) if xdg else (Path.home() / ".cache")
        return base / "jac" / "jir"


def get_module_cache_dir() -> Path:
    """Global cache dir for serialized user modules (installed/external sources)."""
    return get_jir_cache_dir() / "modules"


def get_native_cache_dir() -> Path:
    """Global cache dir for native LLVM IR / object artifacts."""
    return get_jir_cache_dir() / "native"


def get_bootstrap_cache_dir() -> Path:
    """Global cache dir for marshalled jac0core bootstrap bytecode."""
    return get_jir_cache_dir() / "bootstrap"
