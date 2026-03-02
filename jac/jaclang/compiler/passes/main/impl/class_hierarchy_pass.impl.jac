"""Class Hierarchy Pass implementation."""
import jaclang.jac0core.unitree as uni;
import from jaclang.jac0core.passes { UniPass }
import from jaclang.jac0core.constant { SymbolType }
import from typing { Any }

impl ClassHierarchyPass.init(
    ir_in: uni.Module, prog: Any, cancel_token: Any = None
) -> None {
    super.init(ir_in, prog, cancel_token);
}

impl ClassHierarchyPass.before_pass -> None {
    # Read existing type evaluator without creating one.
    self.te = getattr(self.prog, 'type_evaluator', None);
    self.arch_nodes: dict[str, uni.Archetype] = {};
    self.hierarchy: dict[str, str] = {};
    self.method_registry: dict[str, list[str]] = {};
}

"""Collect archetype hierarchy and method info from type system."""
impl ClassHierarchyPass.exit_archetype(nd: uni.Archetype) -> None {
    if not nd.name {
        return;
    }
    aname = nd.name?.value or str(nd.name);
    if not aname {
        return;
    }
    self.arch_nodes[aname] = nd;

    # Use type system to get class hierarchy (uses type().__name__
    # checks to avoid importing from type_system.types)
    if self.te is not None {
        try {
            ct = self.te.get_type_of_class(nd);
            if ct is not None and type(ct).__name__ == "ClassType" and ct.shared {
                # Extract parent from MRO
                mro = ct.shared.mro;
                if mro and len(mro) > 1 {
                    # MRO[0] is self, MRO[1] is direct parent (if not object)
                    parent_ct = mro[1];
                    if (
                        type(parent_ct).__name__ == "ClassType"
                        and parent_ct.shared
                        and parent_ct.shared.class_name != "object"
                        and not parent_ct.shared.is_builtin_class
                    ) {
                        parent_name = parent_ct.shared.class_name;
                        self.hierarchy[aname] = parent_name;
                        nd.gen.class_parent = parent_name;
                    }
                }

                # Collect methods from symbol table
                methods: list[str] = [];
                if ct.shared.symbol_table {
                    for (sym_name, sym) in ct.shared.symbol_table.names_in_scope.items() {
                        if sym.sym_type == SymbolType.ABILITY {
                            methods.append(sym_name);
                        }
                    }
                }
                self.method_registry[aname] = methods;
            }
        } except Exception {
            ;
        }
    } else {
        # Fallback: walk base_classes AST
        if nd.base_classes {
            for base_expr in nd.base_classes {
                if isinstance(base_expr, uni.Name) {
                    parent_name = base_expr.value;
                    if parent_name and parent_name != "object" {
                        self.hierarchy[aname] = parent_name;
                        nd.gen.class_parent = parent_name;
                        break;
                    }
                }
            }
        }
    }
}

"""Build vtable layouts after all archetypes are collected."""
impl ClassHierarchyPass.after_pass -> None {
    # Determine which classes need vtables
    parents_set: set[str] = set(self.hierarchy.values());

    # Build vtable layouts in topological order (parents before children)
    processed: set[str] = set();

    def build_layout(name: str) -> list[str] {
        if name in processed {
            arch_nd = self.arch_nodes.get(name);
            if arch_nd {
                return arch_nd.gen.vtable_layout or [];
            }
            return [];
        }
        processed.add(name);

        layout: list[str] = [];

        # Start from parent layout
        parent = self.hierarchy.get(name);
        if parent and parent in self.arch_nodes {
            layout = list(build_layout(parent));
        }

        # Add own methods not in parent layout
        own_methods = self.method_registry.get(name, []);
        layout_set = set(layout);
        for method in own_methods {
            if method not in layout_set and method != "postinit" and method != "init" {
                layout.append(method);
            }
        }

        # Store on archetype node
        arch_nd = self.arch_nodes.get(name);
        if arch_nd {
            needs_vt = (name in parents_set) or (name in self.hierarchy);
            arch_nd.gen.needs_vtable = needs_vt;
            arch_nd.gen.vtable_layout = layout;
            arch_nd.gen.vtable_indices = {m: i for (i, m) in enumerate(layout)};
        }

        return layout;
    }

    for aname in self.arch_nodes {
        if aname not in processed {
            build_layout(aname);
        }
    }
}
