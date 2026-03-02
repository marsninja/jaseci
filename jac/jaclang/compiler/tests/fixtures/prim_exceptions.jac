"""Exception hierarchy primitives: try/except with type hierarchy matching.

Cross-backend equivalence fixture.
All exceptions are raised explicitly (JS 1/0 yields Infinity, not an error).
"""

def exceptions_py() -> dict {
    results: dict = {};

    try {
        raise ValueError("test");
    } except ValueError {
        results["basic_catch"] = "caught";
    }

    try {
        raise ZeroDivisionError("div");
    } except ArithmeticError {
        results["catch_parent"] = "caught";
    }

    try {
        raise ZeroDivisionError("div2");
    } except Exception {
        results["catch_grandparent"] = "caught";
    }

    caught_wrong: str = "not caught";
    try {
        try {
            raise ValueError("val");
        } except TypeError {
            caught_wrong = "wrong handler";
        }
    } except Exception {
        caught_wrong = "fell through";
    }
    results["catch_wrong_type"] = caught_wrong;

    handler_name: str = "none";
    try {
        raise KeyError("k");
    } except TypeError {
        handler_name = "type_error";
    } except LookupError {
        handler_name = "lookup";
    } except Exception {
        handler_name = "exception";
    }
    results["multiple_handlers"] = handler_name;

    try {
        raise IndexError("idx");
    } except LookupError {
        results["nested_hierarchy"] = "caught";
    }

    parts: str = "";
    try {
        raise ValueError("v");
    } except ValueError {
        parts = "caught";
    } finally {
        parts = parts + "+finally";
    }
    results["finally_runs"] = parts;

    no_exc_result: str = "no handler";
    try {
        x: int = 42;
    } except ValueError {
        no_exc_result = "handler ran";
    }
    results["no_exception"] = no_exc_result;

    try {
        raise ValueError("test msg");
    } except ValueError as e {
        results["exception_message"] = "test msg" in str(e);
    }

    return results;
}

cl def exceptions_cl() -> dict {
    results: dict = {};

    try {
        raise ValueError("test");
    } except ValueError {
        results["basic_catch"] = "caught";
    }

    try {
        raise ZeroDivisionError("div");
    } except ArithmeticError {
        results["catch_parent"] = "caught";
    }

    try {
        raise ZeroDivisionError("div2");
    } except Exception {
        results["catch_grandparent"] = "caught";
    }

    caught_wrong: str = "not caught";
    try {
        try {
            raise ValueError("val");
        } except TypeError {
            caught_wrong = "wrong handler";
        }
    } except Exception {
        caught_wrong = "fell through";
    }
    results["catch_wrong_type"] = caught_wrong;

    handler_name: str = "none";
    try {
        raise KeyError("k");
    } except TypeError {
        handler_name = "type_error";
    } except LookupError {
        handler_name = "lookup";
    } except Exception {
        handler_name = "exception";
    }
    results["multiple_handlers"] = handler_name;

    try {
        raise IndexError("idx");
    } except LookupError {
        results["nested_hierarchy"] = "caught";
    }

    parts: str = "";
    try {
        raise ValueError("v");
    } except ValueError {
        parts = "caught";
    } finally {
        parts = parts + "+finally";
    }
    results["finally_runs"] = parts;

    no_exc_result: str = "no handler";
    try {
        x: int = 42;
    } except ValueError {
        no_exc_result = "handler ran";
    }
    results["no_exception"] = no_exc_result;

    try {
        raise ValueError("test msg");
    } except ValueError as e {
        results["exception_message"] = "test msg" in str(e);
    }

    return results;
}

def test_basic_catch_py() -> int {
    result: int = 0;
    try {
        raise ValueError("test");
    } except ValueError {
        result = 1;
    }
    return result;
}

def test_catch_parent_py() -> int {
    result: int = 0;
    try {
        raise ZeroDivisionError("div");
    } except ArithmeticError {
        result = 1;
    }
    return result;
}

def test_catch_grandparent_py() -> int {
    result: int = 0;
    try {
        raise ZeroDivisionError("div");
    } except Exception {
        result = 1;
    }
    return result;
}

def test_catch_wrong_type_py() -> int {
    result: int = 0;
    try {
        try {
            raise ValueError("val");
        } except TypeError {
            result = 1;
        }
    } except Exception {
        result = 2;
    }
    return result;
}

def test_multiple_handlers_py() -> int {
    result: int = 0;
    try {
        raise KeyError("k");
    } except TypeError {
        result = 1;
    } except LookupError {
        result = 2;
    } except Exception {
        result = 3;
    }
    return result;
}

def test_nested_hierarchy_py() -> int {
    result: int = 0;
    try {
        raise IndexError("idx");
    } except LookupError {
        result = 1;
    }
    return result;
}

def test_finally_runs_py() -> int {
    result: int = 0;
    try {
        raise ValueError("v");
    } except ValueError {
        result = result + 1;
    } finally {
        result = result + 10;
    }
    return result;
}

def test_no_exception_py() -> int {
    result: int = 0;
    try {
        result = 1;
    } except ValueError {
        result = -1;
    } else {
        result = result + 10;
    }
    return result;
}

def test_exc_as_binding_py() -> int {
    result: int = 0;
    try {
        raise ValueError("test msg");
    } except ValueError as e {
        result = 1;
    }
    return result;
}

na {
    def test_basic_catch_na() -> int {
        result: int = 0;
        try {
            raise ValueError("test");
        } except ValueError {
            result = 1;
        }
        return result;
    }

    def test_catch_parent_na() -> int {
        result: int = 0;
        try {
            raise ZeroDivisionError("div");
        } except ArithmeticError {
            result = 1;
        }
        return result;
    }

    def test_catch_grandparent_na() -> int {
        result: int = 0;
        try {
            raise ZeroDivisionError("div");
        } except Exception {
            result = 1;
        }
        return result;
    }

    def test_catch_wrong_type_na() -> int {
        result: int = 0;
        try {
            try {
                raise ValueError("val");
            } except TypeError {
                result = 1;
            }
        } except Exception {
            result = 2;
        }
        return result;
    }

    def test_multiple_handlers_na() -> int {
        result: int = 0;
        try {
            raise KeyError("k");
        } except TypeError {
            result = 1;
        } except LookupError {
            result = 2;
        } except Exception {
            result = 3;
        }
        return result;
    }

    def test_nested_hierarchy_na() -> int {
        result: int = 0;
        try {
            raise IndexError("idx");
        } except LookupError {
            result = 1;
        }
        return result;
    }

    def test_finally_runs_na() -> int {
        result: int = 0;
        try {
            raise ValueError("v");
        } except ValueError {
            result = result + 1;
        } finally {
            result = result + 10;
        }
        return result;
    }

    def test_no_exception_na() -> int {
        result: int = 0;
        try {
            result = 1;
        } except ValueError {
            result = -1;
        } else {
            result = result + 10;
        }
        return result;
    }

    def test_exc_as_binding_na() -> int {
        result: int = 0;
        try {
            raise ValueError("test msg");
        } except ValueError as e {
            result = 1;
        }
        return result;
    }
}
