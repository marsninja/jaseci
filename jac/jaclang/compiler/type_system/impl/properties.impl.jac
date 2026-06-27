"""Implementation of property type utilities."""

# =============================================================================
# Property detection
# =============================================================================
"""Check if a decorator type is the builtin property class."""
impl is_property_decorator_type(decorator_type: types.TypeBase) -> bool {
    if not isinstance(decorator_type, types.ClassType) {
        return False;
    }
    return decorator_type.is_builtin("property");
}

"""Check if a decorator type is cached_property from functools."""
impl is_cached_property_decorator_type(decorator_type: types.TypeBase) -> bool {
    if not isinstance(decorator_type, types.ClassType) {
        return False;
    }
    return (
        decorator_type.shared.class_name == "cached_property"
        and decorator_type.shared.is_from_stdlib_stub
    );
}
