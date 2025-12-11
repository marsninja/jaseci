"""Compatibility shim - transform moved to pycore.passes.transform."""

import sys

from jaclang.pycore.passes import transform as _transform

sys.modules[__name__] = _transform

from jaclang.pycore.passes.transform import *  # noqa: F401, F403
