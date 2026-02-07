"""Bootstrap symbol table for the Jac bootstrap compiler (Layer 1).

Provides scope management, symbol tracking, impl matching, and .impl.jac
file discovery. Used by the bootstrap compiler to resolve names, match
impl blocks to their target classes, and locate annex implementation files.

Written using ONLY the Layer 0 subset so the seed compiler can compile it.
""";

import os;

import from jaclang.bootstrap.bootstrap_ast {
    AstNode, ModuleNode, ClassNode, FuncNode, ParamNode, FieldNode,
    ImplNode, GlobNode, ImportNode, ImportName, EnumMemberNode,
    NameNode
}

# =============================================================================
# Symbol
# =============================================================================

obj Symbol {
    has name: str = "",
        kind: str = "",
        node: AstNode | None = None,
        scope: AstNode | None = None;
}

# =============================================================================
# Scope
# =============================================================================

obj Scope {
    has name: str = "",
        parent: Scope | None = None,
        symbols: dict[str, Symbol] = {},
        children: list[Scope] = [],
        scope_kind: str = "module";
}

impl Scope {
    # -------------------------------------------------------------------------
    # Lookup
    # -------------------------------------------------------------------------

    def lookup(name: str) -> Symbol | None {
        if name in self.symbols {
            return self.symbols[name];
        }
        if self.parent is not None {
            return self.parent.lookup(name);
        }
        return None;
    }

    def lookup_local(name: str) -> Symbol | None {
        if name in self.symbols {
            return self.symbols[name];
        }
        return None;
    }

    # -------------------------------------------------------------------------
    # Define
    # -------------------------------------------------------------------------

    def define(name: str, kind: str, node: AstNode | None) -> Symbol {
        sym = Symbol(name=name, kind=kind, node=node);
        self.symbols[name] = sym;
        return sym;
    }

    def define_with_scope(name: str, kind: str, node: AstNode | None, scope_kind: str) -> Scope {
        sym = self.define(name, kind, node);
        child = Scope(name=name, parent=self, scope_kind=scope_kind);
        self.children.append(child);
        sym.scope = child;
        return child;
    }

    # -------------------------------------------------------------------------
    # Child Lookup
    # -------------------------------------------------------------------------

    def find_child(name: str) -> Scope | None {
        for child in self.children {
            if child.name == name {
                return child;
            }
        }
        return None;
    }
}

# =============================================================================
# Impl Record
# =============================================================================

obj ImplRecord {
    has target_name: str = "",
        methods: list[AstNode] = [],
        node: AstNode | None = None,
        matched: bool = False;
}

# =============================================================================
# Symbol Table Builder
# =============================================================================

obj BootstrapSymtab {
    has root_scope: Scope | None = None,
        current_scope: Scope | None = None,
        impl_records: list[ImplRecord] = [],
        errors: list[str] = [];

    # -------------------------------------------------------------------------
    # Build from Module
    # -------------------------------------------------------------------------

    def build(module: ModuleNode) -> Scope {
        self.root_scope = Scope(name=module.name, scope_kind="module");
        self.current_scope = self.root_scope;
        self.impl_records = [];
        self.errors = [];

        for node in module.body {
            self.build_node(node);
        }
        return self.root_scope;
    }

    def build_node(node: AstNode) -> None {
        if node.kind == "obj" or node.kind == "class" {
            self.build_class(node);
        } elif node.kind == "enum" {
            self.build_enum(node);
        } elif node.kind == "func" {
            self.build_func(node);
        } elif node.kind == "import" {
            self.build_import(node);
        } elif node.kind == "glob" {
            self.build_glob(node);
        } elif node.kind == "impl" {
            self.record_impl(node);
        }
    }

    # -------------------------------------------------------------------------
    # Class / Object
    # -------------------------------------------------------------------------

    def build_class(node: AstNode) -> None {
        class_scope = self.current_scope.define_with_scope(
            node.name, "obj", node, "class"
        );
        prev_scope = self.current_scope;
        self.current_scope = class_scope;

        for member in node.body {
            if member.kind == "field" {
                self.build_field(member);
            } elif member.kind == "func" {
                self.build_method(member);
            }
        }

        self.current_scope = prev_scope;
    }

    def build_field(node: AstNode) -> None {
        self.current_scope.define(node.name, "field", node);
    }

    def build_method(node: AstNode) -> None {
        method_scope = self.current_scope.define_with_scope(
            node.name, "method", node, "method"
        );
        prev_scope = self.current_scope;
        self.current_scope = method_scope;

        for param in node.params {
            self.current_scope.define(param.name, "param", param);
        }

        self.current_scope = prev_scope;
    }

    # -------------------------------------------------------------------------
    # Enum
    # -------------------------------------------------------------------------

    def build_enum(node: AstNode) -> None {
        enum_scope = self.current_scope.define_with_scope(
            node.name, "enum", node, "enum"
        );
        prev_scope = self.current_scope;
        self.current_scope = enum_scope;

        for member in node.body {
            if member.kind == "enum_member" {
                self.current_scope.define(member.name, "member", member);
            }
        }

        self.current_scope = prev_scope;
    }

    # -------------------------------------------------------------------------
    # Function
    # -------------------------------------------------------------------------

    def build_func(node: AstNode) -> None {
        func_scope = self.current_scope.define_with_scope(
            node.name, "func", node, "func"
        );
        prev_scope = self.current_scope;
        self.current_scope = func_scope;

        for param in node.params {
            self.current_scope.define(param.name, "param", param);
        }

        self.current_scope = prev_scope;
    }

    # -------------------------------------------------------------------------
    # Import
    # -------------------------------------------------------------------------

    def build_import(node: AstNode) -> None {
        if node.is_from {
            for imp_name in node.names {
                name = imp_name.name;
                if imp_name.alias is not None {
                    name = imp_name.alias;
                }
                self.current_scope.define(name, "import", node);
            }
        } else {
            parts: list[str] = [];
            mod_name = node.module;
            i = 0;
            while i < len(mod_name) {
                ch = mod_name[i];
                if ch == "." {
                    break;
                }
                i = i + 1;
            }
            top_name = mod_name[0:i];
            if i == len(mod_name) {
                top_name = mod_name;
            }
            self.current_scope.define(top_name, "import", node);
        }
    }

    # -------------------------------------------------------------------------
    # Glob
    # -------------------------------------------------------------------------

    def build_glob(node: AstNode) -> None {
        self.current_scope.define(node.name, "var", node);
    }

    # -------------------------------------------------------------------------
    # Impl Recording and Matching
    # -------------------------------------------------------------------------

    def record_impl(node: AstNode) -> None {
        record = ImplRecord(
            target_name=node.target,
            methods=node.methods,
            node=node,
            matched=False
        );
        self.impl_records.append(record);
    }

    def match_impls() -> None {
        for record in self.impl_records {
            target_sym = self.root_scope.lookup_local(record.target_name);
            if target_sym is None {
                self.errors.append(
                    f"Impl target not found: {record.target_name}"
                );
                continue;
            }
            if target_sym.scope is None {
                self.errors.append(
                    f"Impl target has no scope: {record.target_name}"
                );
                continue;
            }
            target_scope = target_sym.scope;
            for method in record.methods {
                method_scope = target_scope.define_with_scope(
                    method.name, "method", method, "method"
                );
                for param in method.params {
                    method_scope.define(param.name, "param", param);
                }
            }
            record.matched = True;
        }
    }

    def get_unmatched_impls() -> list[ImplRecord] {
        result: list[ImplRecord] = [];
        for record in self.impl_records {
            if not record.matched {
                result.append(record);
            }
        }
        return result;
    }

    # -------------------------------------------------------------------------
    # Impl File Discovery
    # -------------------------------------------------------------------------

    def discover_impl_files(source_path: str) -> list[str] {
        result: list[str] = [];

        if not source_path.endswith(".jac") {
            return result;
        }
        if source_path.endswith(".impl.jac") {
            return result;
        }

        # Extract base name and directory
        src_dir = os.path.dirname(source_path);
        src_name = os.path.basename(source_path);

        # Get base name without .jac extension
        base = src_name[0:len(src_name) - 4];

        # Handle .cl.jac files
        if base.endswith(".cl") {
            base = base[0:len(base) - 3];
        }

        suffix = ".impl.jac";

        # Search location 1: Same directory
        if os.path.isdir(src_dir) {
            entries = os.listdir(src_dir);
            for entry in entries {
                if entry.endswith(suffix) and entry.startswith(base + ".") {
                    full_path = os.path.join(src_dir, entry);
                    if os.path.isfile(full_path) {
                        result.append(full_path);
                    }
                }
            }
        }

        # Search location 2: Module folder (e.g., foo.impl/)
        mod_folder = os.path.join(src_dir, base + ".impl");
        if os.path.isdir(mod_folder) {
            entries = os.listdir(mod_folder);
            for entry in entries {
                if entry.endswith(suffix) {
                    full_path = os.path.join(mod_folder, entry);
                    if os.path.isfile(full_path) {
                        result.append(full_path);
                    }
                }
            }
        }

        # Search location 3: Shared impl/ folder
        shared_folder = os.path.join(src_dir, "impl");
        if os.path.isdir(shared_folder) {
            entries = os.listdir(shared_folder);
            for entry in entries {
                if entry.endswith(suffix) and entry.startswith(base + ".") {
                    full_path = os.path.join(shared_folder, entry);
                    if os.path.isfile(full_path) {
                        result.append(full_path);
                    }
                }
            }
        }

        return result;
    }

    # -------------------------------------------------------------------------
    # Scope Dump (for debugging)
    # -------------------------------------------------------------------------

    def dump_scope(scope: Scope, indent: int) -> str {
        result = "";
        prefix = "";
        i = 0;
        while i < indent {
            prefix = prefix + "  ";
            i = i + 1;
        }
        result = result + prefix + scope.scope_kind + " " + scope.name + "\n";
        for name in scope.symbols {
            sym = scope.symbols[name];
            result = result + prefix + "  " + sym.kind + " " + sym.name + "\n";
        }
        for child in scope.children {
            result = result + self.dump_scope(child, indent + 1);
        }
        return result;
    }
}
