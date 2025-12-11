"""Compatibility shim - runtime moved to pycore.runtime.runtime."""

import sys

from jaclang.pycore.runtime import runtime as _runtime

sys.modules[__name__] = _runtime

from jaclang.pycore.runtime.runtime import *  # noqa: F401, F403
