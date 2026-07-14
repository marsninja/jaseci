"""Python-style property decorators in an 'obj' are non-idiomatic and warn (W2029).

Jac has native property syntax, so the decorator forms get the same nudge that
'@classmethod' (W2006) and '@staticmethod' (W2007) already get. The 'class'
archetype is Python's compatibility escape hatch and stays exempt.
"""

obj Container {
    has _val: int = 0;
    has val: int {
        getter {
            return self._val;
        }
        setter(new_val: int) {
            self._val = new_val;
        }
        deleter {
            self._val = 0;
        }
    }
}

class Legacy {
    has v: int {
        getter {
            return 1;
        }
    }
}
