"""Single source of truth for jac's global on-disk cache root.

Pure Python with no jac dependencies, so it is importable during bootstrap —
before the jac0core ``.jac`` modules have been transpiled. Both the bootstrap
bytecode cache (``meta_importer``) and the JIR module cache
(``jaclang.jac0core.jir``) derive their directories from here, so the
platform-resolution logic lives in exactly one place.

This module owns only the genuinely global, config-independent directories.
The per-module cache locations (``jir/modules/`` and its ``native/`` subdir)
are project-aware and therefore resolved in ``jaclang.jac0core.jir`` via
``get_module_cache_path``/``get_native_cache_dir(source_path)``, which fall
back to the project's ``.jac/cache`` when inside a project.

Platform roots:
    Linux:   ~/.cache/jac/jir/             ($XDG_CACHE_HOME honored)
    macOS:   ~/Library/Caches/jac/jir/
    Windows: %LOCALAPPDATA%/jac/cache/jir/

When the preferred root cannot be made writable (read-only or offline ``HOME``,
e.g. the single-binary launcher running with an unwritable home), all caches
fall back to a per-user temp dir so jac still runs. This mirrors the C
launcher's own cache-root fallback in ``tools/binary/launcher.c``.
"""

import os
import sys
import tempfile
from pathlib import Path


def _platform_jir_dir() -> Path:
    """The preferred (non-fallback) global JIR cache dir for this platform."""
    if sys.platform == "win32":
        base = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local"))
        return base / "jac" / "cache" / "jir"
    elif sys.platform == "darwin":
        return Path.home() / "Library" / "Caches" / "jac" / "jir"
    else:
        xdg = os.environ.get("XDG_CACHE_HOME")
        base = Path(xdg) if xdg else (Path.home() / ".cache")
        return base / "jac" / "jir"


def _writable(path: Path) -> bool:
    """True if `path` exists (or can be created) and is writable."""
    try:
        path.mkdir(parents=True, exist_ok=True)
    except OSError:
        return False
    return os.access(path, os.W_OK)


def _fallback_jir_dir() -> Path:
    """Per-user temp JIR cache dir, used when the preferred root is unwritable."""
    uid = os.getuid() if hasattr(os, "getuid") else os.environ.get("USERNAME", "user")
    return Path(tempfile.gettempdir()) / f"jac-cache-{uid}" / "jir"


def get_jir_cache_dir() -> Path:
    """Return the global JIR cache dir, falling back to a temp dir if needed."""
    primary = _platform_jir_dir()
    if _writable(primary):
        return primary
    fallback = _fallback_jir_dir()
    fallback.mkdir(parents=True, exist_ok=True)
    return fallback


def get_bootstrap_cache_dir() -> Path:
    """Global cache dir for marshalled jac0core bootstrap bytecode."""
    return get_jir_cache_dir() / "bootstrap"
