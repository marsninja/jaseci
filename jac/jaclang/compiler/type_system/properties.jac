"""Property type utilities for Jac type system.

Handles @property, @cached_property, and custom descriptor protocols.
"""
import from . { types }
import jaclang.jac0core.unitree as uni;

# =============================================================================
# Property detection
# =============================================================================
"""Check if decorator type is the builtin property class."""
def is_property_decorator_type(decorator_type: types.TypeBase) -> bool;

"""Check if decorator type is cached_property from functools."""
def is_cached_property_decorator_type(decorator_type: types.TypeBase) -> bool;
