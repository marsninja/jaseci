"""Compatibility shim - unitree moved to pycore.ast.unitree."""

import sys

# Import the actual module
from jaclang.pycore.ast import unitree as _unitree

# Replace this shim module with the actual module in sys.modules
# This ensures all attribute lookups work correctly
sys.modules[__name__] = _unitree

# Re-export for static analysis tools
from jaclang.pycore.ast.unitree import *  # noqa: F401, F403
