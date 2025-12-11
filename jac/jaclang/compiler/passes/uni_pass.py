"""Compatibility shim - uni_pass moved to pycore.passes.uni_pass."""

import sys

from jaclang.pycore.passes import uni_pass as _uni_pass

sys.modules[__name__] = _uni_pass

from jaclang.pycore.passes.uni_pass import *  # noqa: F401, F403
