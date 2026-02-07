"""Bootstrap compiler orchestration for the Jac bootstrap compiler (Layer 1).

Full pipeline: read source -> parse -> discover .impl.jac files -> parse impls
-> merge into module -> build symtab -> match impls -> codegen -> return Python.
Also provides bytecode caching for compiled modules.

Written using ONLY the Layer 0 subset so the seed compiler can compile it.
""";

import os;
import sys;
import marshal;
import types;

import from jaclang.bootstrap.bootstrap_ast {
    AstNode, ModuleNode, ImplNode
}
import from jaclang.bootstrap.bootstrap_lexer { BootstrapLexer }
import from jaclang.bootstrap.bootstrap_parser { BootstrapParser }
import from jaclang.bootstrap.bootstrap_codegen { BootstrapCodegen }
import from jaclang.bootstrap.bootstrap_symtab { BootstrapSymtab }

# =============================================================================
# Cache Entry
# =============================================================================

obj CacheEntry {
    has source_path: str = "",
        cache_path: str = "",
        source_mtime: float = 0.0,
        valid: bool = False;
}

# =============================================================================
# Bytecode Cache
# =============================================================================

obj BootstrapBytecodeCache {
    has cache_dir: str = "",
        entries: dict[str, CacheEntry] = {};

    # -------------------------------------------------------------------------
    # Cache Directory
    # -------------------------------------------------------------------------

    def init_cache_dir() -> str {
        home = os.path.expanduser("~");
        cache_base = os.path.join(home, ".cache", "jac", "bootstrap");
        if not os.path.exists(cache_base) {
            os.makedirs(cache_base);
        }
        self.cache_dir = cache_base;
        return cache_base;
    }

    # -------------------------------------------------------------------------
    # Cache Path Generation
    # -------------------------------------------------------------------------

    def get_cache_path(source_path: str) -> str {
        if self.cache_dir == "" {
            self.init_cache_dir();
        }
        abs_path = os.path.abspath(source_path);
        # Replace path separators with underscores for flat cache dir
        cache_name = abs_path.replace("/", "_").replace("\\", "_");
        if cache_name.endswith(".jac") {
            cache_name = cache_name[0:len(cache_name) - 4] + ".jbc";
        } else {
            cache_name = cache_name + ".jbc";
        }
        return os.path.join(self.cache_dir, cache_name);
    }

    # -------------------------------------------------------------------------
    # Cache Validation
    # -------------------------------------------------------------------------

    def is_cache_valid(source_path: str) -> bool {
        abs_path = os.path.abspath(source_path);
        cache_path = self.get_cache_path(abs_path);
        if not os.path.exists(cache_path) {
            return False;
        }
        src_mtime = os.path.getmtime(abs_path);
        cache_mtime = os.path.getmtime(cache_path);
        return cache_mtime >= src_mtime;
    }

    # -------------------------------------------------------------------------
    # Save / Load
    # -------------------------------------------------------------------------

    def save_cache(source_path: str, bytecode: bytes) -> None {
        cache_path = self.get_cache_path(source_path);
        f = open(cache_path, "wb");
        f.write(bytecode);
        f.close();
    }

    def load_cached(source_path: str) -> bytes | None {
        cache_path = self.get_cache_path(source_path);
        if not os.path.exists(cache_path) {
            return None;
        }
        f = open(cache_path, "rb");
        data = f.read();
        f.close();
        return data;
    }
}

# =============================================================================
# Compiler
# =============================================================================

obj BootstrapCompiler {
    has cache: BootstrapBytecodeCache | None = None,
        compiled_modules: dict[str, str] = {},
        errors: list[str] = [],
        verbose: bool = False;

    # -------------------------------------------------------------------------
    # Pipeline: Source -> Python
    # -------------------------------------------------------------------------

    def compile_file(path: str) -> str {
        abs_path = os.path.abspath(path);

        # Check if already compiled
        if abs_path in self.compiled_modules {
            return self.compiled_modules[abs_path];
        }

        # Read source
        f = open(abs_path, "r");
        source = f.read();
        f.close();

        # Parse main module
        parser = BootstrapParser(tokens=[], pos=0, filename=abs_path);
        module = parser.parse_module(source, abs_path);

        # Discover .impl.jac files
        symtab = BootstrapSymtab();
        impl_files = symtab.discover_impl_files(abs_path);

        # Parse and merge impl files
        for impl_path in impl_files {
            impl_f = open(impl_path, "r");
            impl_source = impl_f.read();
            impl_f.close();

            impl_parser = BootstrapParser(tokens=[], pos=0, filename=impl_path);
            impl_module = impl_parser.parse_module(impl_source, impl_path);

            # Merge impl module body into main module body
            for node in impl_module.body {
                module.body.append(node);
            }
        }

        # Build symbol table and match impls
        symtab.build(module);
        symtab.match_impls();

        # Check for errors
        unmatched = symtab.get_unmatched_impls();
        for record in unmatched {
            self.errors.append(f"Unmatched impl: {record.target_name}");
        }

        # Generate Python
        codegen = BootstrapCodegen();
        py_source = codegen.generate(module);

        # Cache the result
        self.compiled_modules[abs_path] = py_source;

        return py_source;
    }

    # -------------------------------------------------------------------------
    # Compile to Code Object
    # -------------------------------------------------------------------------

    def compile_to_code(path: str) -> object {
        abs_path = os.path.abspath(path);

        # Check bytecode cache
        if self.cache is not None {
            if self.cache.is_cache_valid(abs_path) {
                cached = self.cache.load_cached(abs_path);
                if cached is not None {
                    return marshal.loads(cached);
                }
            }
        }

        # Compile from source
        py_source = self.compile_file(abs_path);
        code_obj = compile(py_source, abs_path, "exec");

        # Save to cache
        if self.cache is not None {
            bytecode = marshal.dumps(code_obj);
            self.cache.save_cache(abs_path, bytecode);
        }

        return code_obj;
    }

    # -------------------------------------------------------------------------
    # Compile and Execute
    # -------------------------------------------------------------------------

    def compile_and_exec(path: str, namespace: dict | None) -> dict {
        if namespace is None {
            namespace = {};
        }
        code_obj = self.compile_to_code(path);
        exec(code_obj, namespace);
        return namespace;
    }

    def compile_module(path: str, module_name: str) -> object {
        abs_path = os.path.abspath(path);
        ns = {"__builtins__": __builtins__};
        self.compile_and_exec(abs_path, ns);

        # Register as a Python module
        mod = types.ModuleType(module_name);
        for key in ns {
            if not key.startswith("_") {
                setattr(mod, key, ns[key]);
            }
        }
        sys.modules[module_name] = mod;
        return mod;
    }

    # -------------------------------------------------------------------------
    # Initialization
    # -------------------------------------------------------------------------

    def init_cache() -> None {
        if self.cache is None {
            self.cache = BootstrapBytecodeCache();
            self.cache.init_cache_dir();
        }
    }
}

# =============================================================================
# Public API
# =============================================================================

glob _state: dict[str, BootstrapCompiler] = {};

def get_compiler() -> BootstrapCompiler {
    if "compiler" not in _state {
        c = BootstrapCompiler();
        c.init_cache();
        _state["compiler"] = c;
    }
    return _state["compiler"];
}

def bootstrap_compile(path: str) -> str {
    compiler = get_compiler();
    return compiler.compile_file(path);
}

def bootstrap_exec(path: str) -> dict {
    compiler = get_compiler();
    return compiler.compile_and_exec(path, None);
}
