"""Compatibility shim - base_ast_gen_pass moved to pycore.passes.ast_gen.base_ast_gen_pass."""

import sys

from jaclang.pycore.passes.ast_gen import base_ast_gen_pass as _base_ast_gen_pass

sys.modules[__name__] = _base_ast_gen_pass

from jaclang.pycore.passes.ast_gen.base_ast_gen_pass import *  # noqa: F401, F403
