"""Compatibility shim - jsx_processor moved to pycore.passes.ast_gen.jsx_processor."""

import sys

from jaclang.pycore.passes.ast_gen import jsx_processor as _jsx_processor

sys.modules[__name__] = _jsx_processor

from jaclang.pycore.passes.ast_gen.jsx_processor import *  # noqa: F401, F403
