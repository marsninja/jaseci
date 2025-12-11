"""Compatibility shim - codeinfo moved to pycore.ast.codeinfo."""

import sys

from jaclang.pycore.ast import codeinfo as _codeinfo

sys.modules[__name__] = _codeinfo

from jaclang.pycore.ast.codeinfo import *  # noqa: F401, F403
