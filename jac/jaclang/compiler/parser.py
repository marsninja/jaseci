"""Compatibility shim - parser moved to pycore.parser.jac_parser."""

import sys

from jaclang.pycore.parser import jac_parser as _jac_parser

sys.modules[__name__] = _jac_parser

from jaclang.pycore.parser.jac_parser import *  # noqa: F401, F403
