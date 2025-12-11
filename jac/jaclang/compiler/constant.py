"""Compatibility shim - constant moved to pycore.ast.constant."""

import sys

from jaclang.pycore.ast import constant as _constant

sys.modules[__name__] = _constant

from jaclang.pycore.ast.constant import *  # noqa: F401, F403
