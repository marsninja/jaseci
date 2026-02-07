"""Code location info for AST nodes.""";

import from enum { Enum }
import from typing { Any }


# =============================================================================
# Client Manifest
# =============================================================================


obj ClientManifest {
    """Client-side rendering manifest metadata.""";

    has exports: list[str] = [],
        globals: list[str] = [],
        params: dict[str, list[str]] = {},
        globals_values: dict[str, Any] = {},
        has_client: bool = False,
        imports: dict[str, str] = {};
}


# =============================================================================
# Interop Context
# =============================================================================


enum InteropContext {
    SERVER = "server",
    NATIVE = "native",
    CLIENT = "client"
}


# =============================================================================
# Native Function/Module Info
# =============================================================================


obj NativeFunctionInfo {
    """Metadata for an exported native function.""";

    has name: str = "",
        ret_type: str = "int",
        param_types: list[str] = [],
        param_names: list[str] = [];
}


obj NativeModuleInfo {
    """Metadata for a compiled .na.jac module.""";

    has mod_path: str = "",
        llvm_module: Any = None,
        native_engine: Any = None,
        exported_functions: dict[str, NativeFunctionInfo] = {};
}


# =============================================================================
# Interop Binding
# =============================================================================


obj InteropBinding {
    """A function callable across codespace boundaries.""";

    has name: str = "",
        source_context: InteropContext | None = None,
        callers: set = set(),
        ret_type: str = "int",
        param_types: list[str] = [],
        param_names: list[str] = [],
        ast_node: Any = None,
        route: list = [],
        source_module: str | None = None;
}

impl InteropBinding {
    @property
    def is_direct() -> bool {
        return len(self.route) == 2;
    }

    @property
    def is_composed() -> bool {
        return len(self.route) > 2;
    }

    @property
    def is_cross_module() -> bool {
        return self.source_module is not None;
    }
}


# =============================================================================
# Interop Manifest
# =============================================================================


obj InteropManifest {
    """All cross-boundary function bindings for a module.""";

    has bindings: dict[str, InteropBinding] = {},
        native_module_imports: dict[str, NativeModuleInfo] = {},
        JAC_TO_CTYPES: dict[str, str] = {
            "int": "ctypes.c_int64",
            "float": "ctypes.c_double",
            "bool": "ctypes.c_bool",
            "str": "ctypes.c_char_p"
        };
}

impl InteropManifest {
    @property
    def native_imports() -> list {
        return [
            b for b in self.bindings.values()
            if b.source_context == InteropContext.SERVER
            and InteropContext.NATIVE in b.callers
        ];
    }

    @property
    def native_exports() -> list {
        return [
            b for b in self.bindings.values()
            if b.source_context == InteropContext.NATIVE
            and InteropContext.SERVER in b.callers
        ];
    }

    @property
    def native_cross_module_imports() -> list {
        return [
            b for b in self.bindings.values()
            if b.source_context == InteropContext.NATIVE
            and InteropContext.NATIVE in b.callers
            and b.source_module is not None
        ];
    }

    @property
    def server_exports_to_client() -> list {
        return [
            b for b in self.bindings.values()
            if b.source_context == InteropContext.SERVER
            and InteropContext.CLIENT in b.callers
        ];
    }
}


# =============================================================================
# Code Generation Target
# =============================================================================


obj CodeGenTarget {
    """Code generation target.""";

    has py: str = "",
        jac: str = "",
        _doc_ir: Any = None,
        js: str = "",
        client_manifest: ClientManifest | None = None,
        py_ast: list = [],
        py_bytecode: bytes | None = None,
        es_ast: Any = None,
        llvm_ir: Any = None,
        native_engine: Any = None,
        interop_manifest: InteropManifest | None = None,
        interop_py_funcs: dict[str, Any] = {},
        _interop_callbacks: list = [];
}

impl CodeGenTarget {
    @property
    def doc_ir() -> Any {
        if self._doc_ir is None {
            self._doc_ir = None;
        }
        return self._doc_ir;
    }

    @CodeGenTarget.doc_ir.setter
    def doc_ir(value: Any) -> None {
        self._doc_ir = value;
    }
}


# =============================================================================
# Code Location Info
# =============================================================================


obj CodeLocInfo {
    """Code location info.""";

    has first_tok: Any = None,
        last_tok: Any = None;
}

impl CodeLocInfo {
    @property
    def orig_src() -> Any {
        return self.first_tok.orig_src;
    }

    @property
    def mod_path() -> str {
        return self.first_tok.orig_src.file_path;
    }

    @property
    def first_line() -> int {
        return self.first_tok.line_no;
    }

    @property
    def last_line() -> int {
        return self.last_tok.end_line;
    }

    @property
    def col_start() -> int {
        return self.first_tok.c_start;
    }

    @property
    def col_end() -> int {
        return self.last_tok.c_end;
    }

    @property
    def pos_start() -> int {
        return self.first_tok.pos_start;
    }

    @property
    def pos_end() -> int {
        return self.last_tok.pos_end;
    }

    @property
    def tok_range() -> tuple {
        return (self.first_tok, self.last_tok);
    }

    @property
    def first_token() -> Any {
        return self.first_tok;
    }

    @property
    def last_token() -> Any {
        return self.last_tok;
    }

    def update_token_range(first_tok: Any, last_tok: Any) -> None {
        self.first_tok = first_tok;
        self.last_tok = last_tok;
    }

    def update_first_token(first_tok: Any) -> None {
        self.first_tok = first_tok;
    }

    def update_last_token(last_tok: Any) -> None {
        self.last_tok = last_tok;
    }

    def __str__() -> str {
        return f"{self.first_line}:{self.col_start} - {self.last_line}:{self.col_end}";
    }
}
