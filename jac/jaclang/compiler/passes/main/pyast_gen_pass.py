"""Compatibility shim - pyast_gen_pass moved to pycore.passes."""

import sys

from jaclang.pycore.passes import pyast_gen_pass as _pyast_gen_pass

sys.modules[__name__] = _pyast_gen_pass

from jaclang.pycore.passes.pyast_gen_pass import *  # noqa: F401, F403
