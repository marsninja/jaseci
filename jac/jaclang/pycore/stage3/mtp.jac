"""Meaning Typed Programming constructs for Jac Language.""";

import from typing { Any }


# =============================================================================
# Info Base Types
# =============================================================================


obj Info {
    """Base info type for MTP metadata.""";

    has name: str = "",
        semstr: str | None = None;
}


obj VarInfo(Info) {
    """Variable info with type metadata.""";

    has type_info: Any = None;
}


obj ParamInfo(VarInfo) {
    """Parameter info.""";
}


obj FieldInfo(VarInfo) {
    """Field info.""";
}


# =============================================================================
# Enum Info
# =============================================================================


obj EnumInfo(Info) {
    """Enum info with members list.""";

    has members: list[FieldInfo] = [];
}


# =============================================================================
# Class Info
# =============================================================================


obj ClassInfo(Info) {
    """Class info with fields, bases, and methods.""";

    has fields: list = [],
        base_classes: list = [],
        methods: list = [];
}


# =============================================================================
# Function Info
# =============================================================================


obj FunctionInfo(Info) {
    """Function info with params and return type.""";

    has params: list | None = None,
        return_type: Any = None,
        tools: list | None = None,
        by_call: bool = False;
}


obj MethodInfo(FunctionInfo) {
    """Method info with parent class reference.""";

    has parent_class: ClassInfo | None = None;
}


# =============================================================================
# Runtime Types
# =============================================================================


obj MTRuntime {
    """Runtime context for Meaning Typed Programming.""";

    has caller: Any = None,
        args: dict = {},
        call_params: dict = {},
        mtir: MTIR | None = None;
}

impl MTRuntime {
    @staticmethod
    def factory(
        caller: Any,
        args: dict,
        call_params: dict,
        mtir: MTIR | None = None
    ) -> MTRuntime {
        return MTRuntime(
            caller=caller,
            args=args,
            call_params=call_params,
            mtir=mtir
        );
    }
}


obj MTIR {
    """Intermediate Representation for Meaning Typed Programming.""";

    has caller: Any = None,
        args: dict = {},
        call_params: dict = {},
        ir_info: Info | None = None;
}

impl MTIR {
    @property
    def runtime() -> MTRuntime {
        return MTRuntime.factory(self.caller, self.args, self.call_params);
    }
}


# =============================================================================
# Generic Type Helpers
# =============================================================================


def mk_list(inner: Any) -> tuple {
    return ("list", inner);
}


def mk_dict(key: Any, val: Any) -> tuple {
    return ("dict", key, val);
}


def mk_tuple(*types: Any) -> tuple {
    return ("tuple",) + tuple(types);
}


def mk_union(*types: Any) -> tuple {
    return ("union",) + tuple(types);
}


def is_list_type(t: Any) -> bool {
    return isinstance(t, tuple) and len(t) >= 2 and t[0] == "list";
}


def is_dict_type(t: Any) -> bool {
    return isinstance(t, tuple) and len(t) == 3 and t[0] == "dict";
}


def is_tuple_type(t: Any) -> bool {
    return isinstance(t, tuple) and len(t) >= 2 and t[0] == "tuple";
}


def is_union_type(t: Any) -> bool {
    return isinstance(t, tuple) and len(t) >= 2 and t[0] == "union";
}


def inner_types(t: Any) -> tuple {
    if isinstance(t, tuple) and len(t) >= 2 {
        return t[1:];
    }
    return ();
}


def type_to_str(t: Any) -> str {
    """Pretty-print a type-info value.""";
    if t is None {
        return "None";
    }
    if isinstance(t, str) {
        return t;
    }
    try {
        if hasattr(t, "name") {
            return t.name;
        }
    } except Exception {
        pass;
    }
    if isinstance(t, tuple) {
        head = t[0];
        if head == "list" {
            return f"list[{type_to_str(t[1])}]";
        }
        if head == "dict" {
            return f"dict[{type_to_str(t[1])},{type_to_str(t[2])}]";
        }
        if head == "tuple" {
            return "tuple[" + ",".join([type_to_str(x) for x in t[1:]]) + "]";
        }
        if head == "union" {
            return "|".join([type_to_str(x) for x in t[1:]]);
        }
        return head + "[" + ",".join([type_to_str(x) for x in t[1:]]) + "]";
    }
    return str(t);
}
