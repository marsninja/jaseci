"""Compatibility shim - pybc_gen_pass moved to pycore.passes."""

import sys

from jaclang.pycore.passes import pybc_gen_pass as _pybc_gen_pass

sys.modules[__name__] = _pybc_gen_pass

from jaclang.pycore.passes.pybc_gen_pass import *  # noqa: F401, F403
