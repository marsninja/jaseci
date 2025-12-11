"""Compatibility shim - sym_tab_build_pass moved to pycore.passes."""

import sys

from jaclang.pycore.passes import sym_tab_build_pass as _sym_tab_build_pass

sys.modules[__name__] = _sym_tab_build_pass

from jaclang.pycore.passes.sym_tab_build_pass import *  # noqa: F401, F403
