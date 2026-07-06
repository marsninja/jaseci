"""Guard for #EXCEPT-UNRESOLVED: a RESOLVED exception class is still checked.

The permissive Any binding must apply ONLY when the exception class does not
resolve to a real class declaration. A handler bound from a genuine class --
whether a builtin (ValueError) or a legitimately imported one (JSONDecodeError,
which reaches the except clause as an import alias and must be followed to its
declaring class) -- keeps that class's type, so accessing a nonexistent
attribute must still raise E1030. The fix must not blanket-widen every except
variable to Any.
"""

import from json { JSONDecodeError }


def builtin_guard {
    try {
        _ = 1;
    } except ValueError as e {
        _ = e.no_such_attr_on_valueerror;
    }
}


def imported_guard {
    try {
        _ = 1;
    } except JSONDecodeError as e {
        _ = e.no_such_attr_on_jsondecodeerror;
    }
}
