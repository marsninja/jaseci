"""Library module exporting a function with a float parameter.

Used by na_float_arg.na.jac to lock in correct cross-module marshalling of a
non-i64 argument. Guards against the #6386 Category-B path in calls.impl that
synthesized an absent callee signature as all-i64 by arg count -- a float
passed that way would be reinterpreted as an integer bit pattern.
"""

def:pub scale(x: float) -> float {
    return x * 2.0;
}
