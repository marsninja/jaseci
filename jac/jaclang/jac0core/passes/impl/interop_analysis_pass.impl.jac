"""Implementation for interop_analysis_pass constructs."""
import from jaclang.jac0core.constant { CodeContext }

"""Initialize function definition tracking."""
impl InteropAnalysisPass.before_pass(self: InteropAnalysisPass) -> None {
    self._func_defs: dict[(str, tuple[(InteropContext, uni.Ability)])] = {};
    self._imported_native_funcs: dict[(str, tuple[(str, InteropContext)])] = {};
}

"""Determine the codespace context of a node."""
impl InteropAnalysisPass._get_context(
    self: InteropAnalysisPass, nd: uni.UniNode
) -> InteropContext {
    if nd.in_native_context() {
        return InteropContext.NATIVE;
    }
    if nd.in_client_context() {
        return InteropContext.CLIENT;
    }
    return InteropContext.SERVER;
}

"""Extract a type name string from a type annotation expression."""
impl InteropAnalysisPass._extract_type_name(
    self: InteropAnalysisPass, expr: (uni.UniNode | None)
) -> str {
    if (expr is None) {
        return 'int';
    }
    if isinstance(expr, uni.Name) {
        return expr.value;
    }
    if isinstance(expr, uni.Token) {
        return expr.value;
    }
    return 'int';
}

"""Check if a module name refers to a .na.jac file and return the path
suffix.

        Given a module name like 'na_math_utils', checks if
'na_math_utils.na.jac'
        exists relative to the current module. Returns the module path for
linking
        (e.g., 'na_math_utils.na') or None if not a native module.
        """
impl InteropAnalysisPass._resolve_native_module(
    self: InteropAnalysisPass, module_name: str
) -> (str | None) {
    import os;
    base_dir = '.';
    if (self.ir_in and self.ir_in.loc) {
        base_dir = os.path.dirname(self.ir_in.loc.mod_path);
    }
    # Strip leading dots from relative imports (e.g., '.tokens' → 'tokens')
    clean_name = module_name.lstrip('.');
    na_jac_path = os.path.join(base_dir, f"{clean_name}.na.jac");
    if os.path.exists(na_jac_path) {
        return f"{clean_name}.na";
    }
    return None;
}

"""Track imports from .na.jac modules."""
impl InteropAnalysisPass.enter_import(
    self: InteropAnalysisPass, nd: uni.Import
) -> None {
    import_context = self._get_context(nd);
    if (nd.from_loc and isinstance(nd.from_loc, uni.ModulePath)) {
        module_name = getattr(nd.from_loc, 'dot_path_str', None);
        if (not module_name and nd.from_loc?.path and nd.from_loc.path) {
            module_name = '.'.join(
                getattr(p, 'value', str(p)) for p in nd.from_loc.path
            );
        }
        if module_name {
            native_path = self._resolve_native_module(module_name);
            if (native_path and nd.items) {
                manifest = self.ir_in.gen.interop_manifest;
                for item in nd.items {
                    if isinstance(item, uni.ModuleItem) {
                        func_name = getattr(item.name, 'value', str(item.name));
                        self._imported_native_funcs[func_name] = (
                            native_path,
                            import_context
                        );
                        # For native-to-native imports, create binding immediately
                        # so NativeCompilePass can link the module. This avoids
                        # relying on enter_func_call which may not visit annex bodies.
                        # Check both explicit na {} context and .na.jac file context.
                        is_native_ctx = (
                            import_context == InteropContext.NATIVE
                            or (
                                self.ir_in
                                and self.ir_in.loc
                                and self.ir_in.loc.mod_path.endswith('.na.jac')
                            )
                        );
                        if (is_native_ctx and func_name not in manifest.bindings) {
                            binding = InteropBinding(
                                name=func_name,
                                source_context=InteropContext.NATIVE,
                                callers={InteropContext.NATIVE},
                                ret_type='int',
                                param_types=[],
                                param_names=[],
                                ast_node=None,
                                route=[InteropContext.NATIVE, InteropContext.NATIVE],
                                source_module=native_path
                            );
                            manifest.bindings[func_name] = binding;
                        }
                    }
                }
            }
        }
    }
}

"""Record function definition and its context."""
impl InteropAnalysisPass.enter_ability(
    self: InteropAnalysisPass, nd: uni.Ability
) -> None {
    if (nd.sym_name and isinstance(nd.signature, uni.FuncSignature)) {
        nd_cc = nd.code_context;
        if nd_cc == uni.CodeContext.NATIVE {
            ctx = InteropContext.NATIVE;
        } elif nd_cc == uni.CodeContext.CLIENT {
            ctx = InteropContext.CLIENT;
        } else {
            ctx = self._get_context(nd);
        }
        self._func_defs[nd.sym_name] = (ctx, nd);
    }
}

"""Check if a function call crosses context boundaries."""
impl InteropAnalysisPass.enter_func_call(
    self: InteropAnalysisPass, nd: uni.FuncCall
) -> None {
    func_name = None;
    if isinstance(nd.target, uni.Name) {
        func_name = nd.target.value;
    } elif isinstance(nd.target, uni.NameAtom) {
        func_name = nd.target.sym_name;
    }
    if not func_name {
        return;
    }
    caller_ctx = self._get_context(nd);
    manifest = self.ir_in.gen.interop_manifest;
    if (func_name in self._imported_native_funcs) {
        (source_module, import_ctx) = self._imported_native_funcs[func_name];
        if (caller_ctx == InteropContext.NATIVE) {
            if (func_name not in manifest.bindings) {
                binding = InteropBinding(
                    name=func_name,
                    source_context=InteropContext.NATIVE,
                    callers={InteropContext.NATIVE},
                    ret_type='int',
                    param_types=[],
                    param_names=[],
                    ast_node=None,
                    route=[InteropContext.NATIVE, InteropContext.NATIVE],
                    source_module=source_module
                );
                manifest.bindings[func_name] = binding;
            } else {
                manifest.bindings[func_name].callers.add(InteropContext.NATIVE);
            }
        }
        return;
    }
    if (func_name not in self._func_defs) {
        return;
    }
    (callee_ctx, callee_node) = self._func_defs[func_name];
    if (caller_ctx == callee_ctx) {
        return;
    }
    if (func_name in manifest.bindings) {
        manifest.bindings[func_name].callers.add(caller_ctx);
    } else {
        sig = callee_node.signature;
        assert isinstance(sig, uni.FuncSignature);
        ret_type = self._extract_type_name(sig.return_type);
        param_types: list = [];
        param_names: list = [];
        for p in sig.params {
            param_names.append(p.sym_name);
            if p.type_tag {
                param_types.append(self._extract_type_name(p.type_tag.tag));
            } else {
                param_types.append('int');
            }
        }
        binding = InteropBinding(
            name=func_name,
            source_context=callee_ctx,
            callers={caller_ctx},
            ret_type=ret_type,
            param_types=param_types,
            param_names=param_names,
            ast_node=callee_node,
            route=[caller_ctx, callee_ctx]
        );
        manifest.bindings[func_name] = binding;
    }
}

"""Mark archetypes used in cross-boundary return types as SHARED."""
impl InteropAnalysisPass.after_pass(self: InteropAnalysisPass) -> None {
    manifest = self.ir_in.gen.interop_manifest;
    # Collect type names referenced in cross-boundary bindings (client<->server)
    type_names: set[str] = set();
    for (name, binding) in manifest.bindings.items() {
        has_client_caller = InteropContext.CLIENT in binding.callers;
        is_server_source = binding.source_context == InteropContext.SERVER;
        if has_client_caller and is_server_source {
            # Collect return type and param types that might be archetypes
            if binding.ret_type
            and binding.ret_type not in (
                'int',
                'float',
                'str',
                'bool',
                'None',
                'dict',
                'list',
                'Any'
            ) {
                type_names.add(binding.ret_type);
            }
            for pt in binding.param_types {
                if pt
                and pt not in (
                    'int',
                    'float',
                    'str',
                    'bool',
                    'None',
                    'dict',
                    'list',
                    'Any'
                ) {
                    type_names.add(pt);
                }
            }
        }
    }
    if not type_names {
        return;
    }
    # Look up each type name in the module's symbol table and mark as SHARED
    visited: set[str] = set();
    for type_name in type_names {
        if type_name in self.ir_in.names_in_scope {
            sym = self.ir_in.names_in_scope[type_name];
            decl_node = sym.decl;
            # Walk up to find the Archetype AST node
            arch_node = decl_node.find_parent_of_type(uni.Archetype);
            if arch_node is None and isinstance(decl_node, uni.NameAtom) {
                # The decl might be the Archetype's name directly
                parent = decl_node.parent;
                if isinstance(parent, uni.Archetype) {
                    arch_node = parent;
                }
            }
            if arch_node is not None and isinstance(arch_node, uni.Archetype) {
                self._mark_archetype_shared(arch_node, visited);
            }
        }
    }
}

"""Recursively mark an archetype and its field types as SHARED."""
impl InteropAnalysisPass._mark_archetype_shared(
    self: InteropAnalysisPass, arch: uni.Archetype, visited: set[str]
) -> None {
    arch_name = arch.name.value if isinstance(arch.name, uni.Name) else str(arch.name);
    if arch_name in visited {
        return;
    }
    visited.add(arch_name);
    # Only promote SERVER archetypes to SHARED (don't touch CLIENT or NATIVE)
    if arch.code_context == CodeContext.SERVER {
        arch.code_context = CodeContext.SHARED;
    }
    # Recursively mark archetypes referenced in has-field types
    for has_var in arch.get_has_vars() {
        if has_var.type_tag {
            field_type_name = self._extract_type_name(has_var.type_tag.tag);
            if field_type_name
            and field_type_name not in (
                'int',
                'float',
                'str',
                'bool',
                'None',
                'dict',
                'list',
                'Any'
            ) {
                if field_type_name in self.ir_in.names_in_scope {
                    field_sym = self.ir_in.names_in_scope[field_type_name];
                    field_decl = field_sym.decl;
                    field_arch = field_decl.find_parent_of_type(uni.Archetype);
                    if field_arch is None and isinstance(field_decl, uni.NameAtom) {
                        parent = field_decl.parent;
                        if isinstance(parent, uni.Archetype) {
                            field_arch = parent;
                        }
                    }
                    if field_arch is not None
                    and isinstance(field_arch, uni.Archetype) {
                        self._mark_archetype_shared(field_arch, visited);
                    }
                }
            }
        }
    }
    # Also mark base classes as SHARED
    if arch.base_classes {
        for base_expr in arch.base_classes {
            base_name = None;
            if isinstance(base_expr, uni.Name) {
                base_name = base_expr.value;
            } elif isinstance(base_expr, uni.NameAtom) {
                base_name = base_expr.sym_name;
            }
            if base_name and base_name in self.ir_in.names_in_scope {
                base_sym = self.ir_in.names_in_scope[base_name];
                base_decl = base_sym.decl;
                base_arch = base_decl.find_parent_of_type(uni.Archetype);
                if base_arch is None and isinstance(base_decl, uni.NameAtom) {
                    parent = base_decl.parent;
                    if isinstance(parent, uni.Archetype) {
                        base_arch = parent;
                    }
                }
                if base_arch is not None and isinstance(base_arch, uni.Archetype) {
                    self._mark_archetype_shared(base_arch, visited);
                }
            }
        }
    }
}
