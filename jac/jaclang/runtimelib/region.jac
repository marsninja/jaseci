"""First-class region handle runtime for the Python backend (#7491 R4).

Native codegen gives Region handles arena semantics (bump allocation, bulk
free at the handle's drop point). Here memory stays GC-managed, but the
handle tracks drop-hooked objects created while it is open and runs their
hooks LIFO when the handle dies, so `drop` timing is portable across
backends: CPython refcounting fires __del__ at the closing brace for an
anonymous open (the lowering nulls its hidden temp in a finally) and at
the last reference's death for a named handle.
"""

glob _region_stack: list = [];

obj JacRegion {
    has _drops: list[any] = [];

    def _jac_open -> None {
        _region_stack.append(self);
    }

    def _jac_close -> None {
        if _region_stack and _region_stack[-1] is self {
            _region_stack.pop();
        }
    }

    def _jac_register(item: any) -> None {
        self._drops.append(item);
    }

    def _jac_drop -> None {
        _pending = self._drops;
        self._drops = [];
        for o in reversed(_pending) {
            try {
                o.drop();
            } except Exception {
                pass;
            }
        }
    }

    def __del__ -> None {
        self._jac_drop();
    }
}

def open_region(r: any) -> None {
    if isinstance(r, JacRegion) {
        r._jac_open();
    }
}

def close_region(r: any) -> None {
    if isinstance(r, JacRegion) {
        r._jac_close();
    }
}

def register_drop(item: any) -> None {
    if _region_stack {
        _region_stack[-1]._jac_register(item);
    }
}

def instrument_drops(cls: any) -> None {
    _orig_init = cls.__init__;
    def _region_init(inst: any, *args: any, **kwargs: any) -> None {
        _orig_init(inst, *args, **kwargs);
        register_drop(inst);
    }
    cls.__init__ = _region_init;
}
