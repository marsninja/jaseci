"""Helpers for guarding optional dependencies.

These now live in core (`jaclang.project.capabilities`) so the scale and byllm
subsystems share one implementation; re-exported here to keep scale's existing
import sites (`jaclang.scale._optdeps.optional_deps`) working unchanged.
"""

import from jaclang.project.capabilities { require_optional, is_optional_available }
