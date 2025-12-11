"""Compatibility shim - ast_gen moved to pycore.passes.ast_gen."""

import sys

from jaclang.pycore.passes import ast_gen as _ast_gen

sys.modules[__name__] = _ast_gen

from jaclang.pycore.passes.ast_gen import *  # noqa: F401, F403
