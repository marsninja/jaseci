"""Virtual table (vtable) support for inheritance with C3 MRO."""
"""Vtable method-slot names for a class, in slot order, from LayoutRegistry.

Consumes the centralized vtable slot assignment directly instead of caching it
in a vtable_layouts shadow dict (#6386, Category C). Imported archetypes resolve
against their defining module's registry.
"""
impl NaIRGenPass._vtable_method_names(arch_name: str) -> list[str] {
    import from jaclang.compiler.passes.main.layout_pass { get_layout_registry }
    methods = get_layout_registry(self.ir_in, self.prog).get_methods(arch_name);
    if not methods {
        _arch = self.arch_ast_map.get(arch_name);
        _owner = _arch.find_parent_of_type(uni.Module) if _arch is not None else None;
        if _owner is not None and _owner is not self.ir_in {
            methods = get_layout_registry(_owner, self.prog).get_methods(arch_name);
        }
    }
    return [m.name for m in methods];
}

"""Vtable slot index of a method on a class, or None (#6386)."""
impl NaIRGenPass._vtable_method_index(
    arch_name: str, method_name: str
) -> (int | None) {
    for (i, n) in enumerate(self._vtable_method_names(arch_name)) {
        if n == method_name {
            return i;
        }
    }
    return None;
}

"""Emit a vtable global constant for a class."""
impl NaIRGenPass._emit_vtable_global(arch_name: str) -> None {
    layout = self._vtable_method_names(arch_name);
    if not layout {
        return;
    }
    i8_ptr = ir.IntType(8).as_pointer();
    vtable_type = ir.ArrayType(i8_ptr, len(layout));
    entries: list[ir.Constant] = [];
    mro = self.mro_order.get(arch_name, [arch_name]);
    for method_name in layout {
        # Resolve: walk MRO to find first implementation
        func = None;
        for check_name in mro {
            full_name = f"{check_name}.{method_name}";
            if full_name in self.method_funcs {
                func = self.method_funcs[full_name];
                break;
            }
        }
        if func is not None {
            entries.append(func.bitcast(i8_ptr));
        } else {
            entries.append(ir.Constant(i8_ptr, None));
        }
    }
    vtable_init = ir.Constant(vtable_type, entries);
    vtable_global = ir.GlobalVariable(
        self.llvm_module, vtable_type, name=f"{arch_name}.__vtable"
    );
    vtable_global.global_constant = True;
    vtable_global.linkage = "private";
    vtable_global.initializer = vtable_init;
    self.vtable_globals[arch_name] = vtable_global;
}

"""Generate a virtual method call via vtable lookup.
Devirtualizes to direct call when the method is never overridden by any subclass."""
impl NaIRGenPass._codegen_virtual_call(
    obj_val: ir.Value, method_name: str, args: list[ir.Value], obj_type_name: str
) -> (ir.Value | None) {
    method_idx = self._vtable_method_index(obj_type_name, method_name);
    if method_idx is None {
        return None;
    }
    # Find the resolved function (walk MRO)
    func = None;
    mro = self.mro_order.get(obj_type_name, [obj_type_name]);
    for check_name in mro {
        full_name = f"{check_name}.{method_name}";
        if full_name in self.method_funcs {
            func = self.method_funcs[full_name];
            break;
        }
    }
    if func is None {
        return None;
    }
    fn_type = func.function_type;
    # Coerce args to expected types
    coerced: list[ir.Value] = [];
    for (i, arg) in enumerate(args) {
        if i < len(fn_type.args) {
            coerced.append(self._coerce_type(arg, fn_type.args[i]));
        } else {
            coerced.append(arg);
        }
    }
    # Devirtualization: if this method is never overridden, use direct call
    non_overridden = self._non_overridden_methods.get(obj_type_name);
    if non_overridden is not None and method_name in non_overridden {
        return self.builder.call(func, coerced, name=f"call.{method_name}");
    }
    # Full vtable dispatch for overridden methods
    i32 = ir.IntType(32);
    i8_ptr = ir.IntType(8).as_pointer();
    # Load vtable pointer from field 0
    vtable_ptr_ptr = self.builder.gep(
        obj_val, [ir.Constant(i32, 0), ir.Constant(i32, 0)], name="vtable.ptr.ptr"
    );
    vtable_ptr = self.builder.load(vtable_ptr_ptr, name="vtable.ptr");
    # GEP to method index
    method_slot = self.builder.gep(
        vtable_ptr, [ir.Constant(i32, method_idx)], name=f"vt.{method_name}"
    );
    method_i8 = self.builder.load(method_slot, name=f"fn.{method_name}.raw");
    # Bitcast to expected function type and call
    typed_fn = self.builder.bitcast(
        method_i8, fn_type.as_pointer(), name=f"fn.{method_name}"
    );
    return self.builder.call(typed_fn, coerced, name=f"vcall.{method_name}");
}

"""Generate wrapper functions for inherited methods so they can be called by name."""
impl NaIRGenPass._generate_inherited_method_wrappers -> None {
    # For each class with parents, generate wrappers for inherited methods
    for (child_name, mro) in self.mro_order.items() {
        child_struct = self.struct_types.get(child_name);
        if child_struct is None or len(mro) < 2 {
            continue;
        }
        # Collect all methods from ancestors via MRO
        seen_methods: set[str] = set();
        for ancestor_name in mro[1:] {
            ancestor_layout = self._vtable_method_names(ancestor_name);
            for method_name in ancestor_layout {
                if method_name in seen_methods {
                    continue;
                }
                seen_methods.add(method_name);
                child_full = f"{child_name}.{method_name}";
                # Skip if child already has its own implementation
                if child_full in self.method_funcs {
                    continue;
                }
                # Find the actual implementation by walking MRO
                impl_func = None;
                impl_class: (str | None) = None;
                for mro_class in mro[1:] {
                    parent_full = f"{mro_class}.{method_name}";
                    if parent_full in self.method_funcs {
                        impl_func = self.method_funcs[parent_full];
                        impl_class = mro_class;
                        break;
                    }
                }
                if impl_func is None {
                    continue;
                }
                # Create wrapper function with child's struct type as self parameter
                orig_fn_type = impl_func.function_type;
                # Replace first param (self) with child's struct pointer
                new_param_types: list[ir.Type] = [child_struct.as_pointer()];
                for i in range(1, len(orig_fn_type.args)) {
                    new_param_types.append(orig_fn_type.args[i]);
                }
                wrapper_fn_type = ir.FunctionType(
                    orig_fn_type.return_type, new_param_types
                );
                wrapper_fn = ir.Function(
                    self.llvm_module, wrapper_fn_type, name=child_full
                );
                # Copy parameter names
                wrapper_fn.args[0].name = "self";
                for i in range(1, len(impl_func.args)) {
                    wrapper_fn.args[i].name = impl_func.args[i].name;
                }
                # Generate wrapper body
                entry_block = wrapper_fn.append_basic_block(name="entry");
                builder = ir.IRBuilder(entry_block);
                # For primary ancestors, bitcast works (prefix compatible)
                # For non-primary, bitcast also works at wrapper level since we
                # re-compile non-primary methods with the child struct in Pass 5.
                # Here we only generate wrappers for methods from primary ancestors.
                impl_struct = self.struct_types.get(impl_class);
                if impl_struct is None {
                    args: list[ir.Value] = list(wrapper_fn.args);
                } else {
                    parent_self = builder.bitcast(
                        wrapper_fn.args[0], impl_struct.as_pointer(), name="parent.self"
                    );
                    args: list[ir.Value] = [parent_self];
                    for i in range(1, len(wrapper_fn.args)) {
                        args.append(wrapper_fn.args[i]);
                    }
                }
                # Call the implementation
                result = builder.call(impl_func, args, name=f"inherited.{method_name}");
                # Return the result
                if isinstance(orig_fn_type.return_type, ir.VoidType) {
                    builder.ret_void();
                } else {
                    builder.ret(result);
                }
                # Register the wrapper
                self.method_funcs[child_full] = wrapper_fn;
                self.func_symtab[child_full] = wrapper_fn;
            }
        }
    }
}
# ─── Phase 6: Type Inference Helpers ──────────────────────────
