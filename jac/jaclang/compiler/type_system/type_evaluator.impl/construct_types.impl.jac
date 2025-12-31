"""Return the effective type of root."""
impl TypeEvaluator._get_type_of_root(
    self: TypeEvaluator, node_: uni.SpecialVarRef
) -> TypeBase {
    node_.sym = self.prefetch.root_class.get_class_symbol();
    node_.type = self.prefetch.root_class.clone_as_instance();
    return node_.type;
}

"""Return the effective type of self."""
impl TypeEvaluator._get_type_of_self(
    self: TypeEvaluator, node_: uni.SpecialVarRef
) -> TypeBase {
    if method := self._get_enclosing_method(node_) {
        cls = method.method_owner;
        if isinstance(cls, uni.Archetype) {
            node_.sym = type_utils.lookup_symtab(
                method, node_.value, self.builtins_module
            );
            node_.type = self.get_type_of_class(cls).clone_as_instance();
            return node_.type;
        }
        if isinstance(cls, uni.Enum) {
            node_.sym = type_utils.lookup_symtab(
                method, node_.value, self.builtins_module
            );
            node_.type = self.get_type_of_enum(cls).clone_as_instance();
            return node_.type;
        }
    }
    return types.UnknownType();
}

"""Return the effective type of the float."""
impl TypeEvaluator.get_type_of_float(self: TypeEvaluator, node: uni.Float) -> TypeBase {
    assert self.prefetch.float_class is not None;
    return self.prefetch.float_class;
}

"""Return the effective type of the int."""
impl TypeEvaluator.get_type_of_int(self: TypeEvaluator, node: uni.Int) -> TypeBase {
    assert self.prefetch.int_class is not None;
    # Create a LiteralType for integer literals
    int_value = int(node.value);
    return types.LiteralType(
        value=int_value,
        base_type=self.prefetch.int_class
    );
}

"""Return the effective type of the string."""
impl TypeEvaluator.get_type_of_string(
    self: TypeEvaluator, node: uni.String | uni.MultiString
) -> TypeBase {
    assert self.prefetch.str_class is not None;
    # Create a LiteralType for string literals
    if isinstance(node, uni.String) {
        str_value = node.value;
        # Remove quotes from the string value
        if str_value.startswith('"') or str_value.startswith("'") {
            str_value = str_value[1:-1];
        }
        return types.LiteralType(
            value=str_value,
            base_type=self.prefetch.str_class
        );
    }
    # For MultiString, widen to str since value may be complex
    return self.prefetch.str_class;
}

"""Return the effective type of the boolean."""
impl TypeEvaluator.get_type_of_bool(self: TypeEvaluator, node: uni.Bool) -> TypeBase {
    assert self.prefetch.bool_class is not None;
    # Create a LiteralType for boolean literals
    bool_value = node.value;
    return types.LiteralType(
        value=bool_value,
        base_type=self.prefetch.bool_class
    );
}

"""Return the effective type of a lambda expression."""
impl TypeEvaluator.get_type_of_lambda(self: TypeEvaluator, node: uni.LambdaExpr) -> TypeBase {
    # Define helper function for parameter category.
    def _get_param_category(param: uni.ParamVar) -> types.ParameterCategory {
        if param.is_vararg {
            return types.ParameterCategory.ArgsList;
        }
        if param.is_kwargs {
            return types.ParameterCategory.KwargsDict;
        }
        return types.ParameterCategory.Positional;
    }

    # Define helper function for parameter kind conversion.
    def _convert_param_kind(kind: uni.ParamKind) -> types.ParamKind {
        match kind {
            case uni.ParamKind.POSONLY: return types.ParamKind.POSONLY;
            case uni.ParamKind.NORMAL: return types.ParamKind.NORMAL;
            case uni.ParamKind.VARARG: return types.ParamKind.VARARG;
            case uni.ParamKind.KWONLY: return types.ParamKind.KWONLY;
            case uni.ParamKind.KWARG: return types.ParamKind.KWARG;
            case _: return types.ParamKind.NORMAL;
        }
    }

    # Get return type
    return_type: TypeBase = types.UnknownType();
    if node.signature is not None and isinstance(node.signature.return_type, uni.Expr) {
        return_type = self._convert_to_instance(
            self.get_type_of_expression(node.signature.return_type)
        );
    } else {
        # Infer return type from body if it's a single expression
        if isinstance(node.body, uni.Expr) {
            return_type = self.get_type_of_expression(node.body);
        } elif self.prefetch and self.prefetch.none_type_class {
            return_type = self._convert_to_instance(self.prefetch.none_type_class);
        }
    }

    # Get parameters
    parameters: list[types.Parameter] = [];
    if node.signature is not None {
        for param in node.signature.params {
            if param.type_tag is not None {
                param_type = self._convert_to_instance(
                    self.get_type_of_expression(param.type_tag.tag)
                );
            } else {
                param_type = types.UnknownType();
            }
            default_value = param.value is not None;
            parameters.append(
                types.Parameter(
                    name=param.name.sym_name,
                    category=_get_param_category(param),
                    param_type=param_type,
                    default_value=default_value,
                    is_self=False,
                    is_cls=False,
                    param_kind=_convert_param_kind(param.param_kind)
                )
            );
        }
    }

    func_type = types.FunctionType(
        func_name="<lambda>",
        return_type=return_type,
        parameters=parameters
    );
    return func_type;
}

"""Return the effective type of a list comprehension: [x for x in items]."""
impl TypeEvaluator.get_type_of_list_compr(self: TypeEvaluator, node: uni.ListCompr) -> TypeBase {
    # The element type is the type of the output expression
    element_type = self.get_type_of_expression(node.out_expr);

    # Get list type and create list[element_type]
    if self.prefetch and self.prefetch.list_class {
        list_type = self.prefetch.list_class;
        if isinstance(list_type, types.ClassType) {
            # Clone the class type and set the type argument
            result = list_type.clone_as_instance();
            result.private.type_args = [element_type];
            return result;
        }
    }
    return types.UnknownType();
}

"""Return the effective type of a set comprehension: {x for x in items}."""
impl TypeEvaluator.get_type_of_set_compr(self: TypeEvaluator, node: uni.SetCompr) -> TypeBase {
    # The element type is the type of the output expression
    element_type = self.get_type_of_expression(node.out_expr);

    # Get set type and create set[element_type]
    if self.prefetch and self.prefetch.set_class {
        set_type = self.prefetch.set_class;
        if isinstance(set_type, types.ClassType) {
            # Clone the class type and set the type argument
            result = set_type.clone_as_instance();
            result.private.type_args = [element_type];
            return result;
        }
    }
    return types.UnknownType();
}

"""Return the effective type of a dict comprehension: {k: v for k, v in items}."""
impl TypeEvaluator.get_type_of_dict_compr(self: TypeEvaluator, node: uni.DictCompr) -> TypeBase {
    # Get key and value types from the kv_pair
    key_type = self.get_type_of_expression(node.kv_pair.key);
    value_type = self.get_type_of_expression(node.kv_pair.value);

    # Get dict type and create dict[key_type, value_type]
    if self.prefetch and self.prefetch.dict_class {
        dict_type = self.prefetch.dict_class;
        if isinstance(dict_type, types.ClassType) {
            # Clone the class type and set the type arguments
            result = dict_type.clone_as_instance();
            result.private.type_args = [key_type, value_type];
            return result;
        }
    }
    return types.UnknownType();
}

"""Return the effective type of a generator expression: (x for x in items)."""
impl TypeEvaluator.get_type_of_gen_compr(self: TypeEvaluator, node: uni.GenCompr) -> TypeBase {
    # The element type is the type of the output expression
    element_type = self.get_type_of_expression(node.out_expr);

    # Get Generator type and create Generator[element_type, None, None]
    if self.prefetch and self.prefetch.generator_class {
        gen_type = self.prefetch.generator_class;
        if isinstance(gen_type, types.ClassType) {
            # Clone the class type and set the type arguments
            result = gen_type.clone_as_instance();
            # Generator[YieldType, SendType, ReturnType] - for simple generators
            # it's Generator[T, None, None]
            if self.prefetch.none_type_class {
                none_type = self._convert_to_instance(self.prefetch.none_type_class);
                result.private.type_args = [element_type, none_type, none_type];
            } else {
                result.private.type_args = [element_type];
            }
            return result;
        }
    }
    return types.UnknownType();
}

"""Return the effective type of an if-else expression: value if condition else else_value."""
impl TypeEvaluator.get_type_of_if_else_expr(self: TypeEvaluator, node: uni.IfElseExpr) -> TypeBase {
    # Get the types of both branches
    true_type = self.get_type_of_expression(node.value);
    false_type = self.get_type_of_expression(node.else_value);

    # If both types are the same, return that type
    if self.assign_type(true_type, false_type) and self.assign_type(false_type, true_type) {
        # Types are equivalent, return either one (prefer non-literal)
        if isinstance(true_type, types.LiteralType) {
            return true_type.widen();
        }
        return true_type;
    }

    # If one type is assignable to the other, return the more general type
    if self.assign_type(true_type, false_type) {
        return false_type;
    }
    if self.assign_type(false_type, true_type) {
        return true_type;
    }

    # Types are not compatible - create a union type
    return types.UnionType(types=[true_type, false_type]);
}

"""Return the effective type of a boolean expression (and/or): a and b, a or b."""
impl TypeEvaluator.get_type_of_bool_expr(self: TypeEvaluator, node: uni.BoolExpr) -> TypeBase {
    # Boolean expressions with 'and' or 'or' can return either operand
    # For static typing purposes:
    # - 'and': Returns the first falsy value or the last value
    # - 'or': Returns the first truthy value or the last value
    # The result type is a union of all operand types (simplified)

    if len(node.values) == 0 {
        return types.UnknownType();
    }

    if len(node.values) == 1 {
        return self.get_type_of_expression(node.values[0]);
    }

    # Collect all types from the values
    result_types: list[types.TypeBase] = [];
    for value in node.values {
        val_type = self.get_type_of_expression(value);
        result_types.append(val_type);
    }

    # If all types are the same, return that type
    first_type = result_types[0];
    all_same = True;
    for t in result_types[1:] {
        if not (self.assign_type(t, first_type) and self.assign_type(first_type, t)) {
            all_same = False;
            break;
        }
    }

    if all_same {
        # Return the widened type if it's a literal
        if isinstance(first_type, types.LiteralType) {
            return first_type.widen();
        }
        return first_type;
    }

    # Different types - for 'and' or 'or', create a union type
    return types.UnionType(types=result_types);
}

"""Return the effective type of a comparison expression: a < b, a == b, etc."""
impl TypeEvaluator.get_type_of_compare_expr(self: TypeEvaluator, node: uni.CompareExpr) -> TypeBase {
    # Comparisons always return bool
    # Evaluate the expressions for potential side effects (like symbol resolution)
    _ = self.get_type_of_expression(node.left);
    for right in node.rights {
        _ = self.get_type_of_expression(right);
    }

    if self.prefetch and self.prefetch.bool_class {
        return self._convert_to_instance(self.prefetch.bool_class);
    }
    return types.UnknownType();
}

"""Return the effective type of an ability."""
impl TypeEvaluator.get_type_of_ability(
    self: TypeEvaluator, node_: uni.Ability
) -> TypeBase {
    if node_.name_spec.type is not None {
        return node_.name_spec.type;
    }
    if not isinstance(node_.signature, uni.FuncSignature) {
        func_type = types.FunctionType(
            func_name=node_.name_spec.sym_name,
            return_type=types.UnknownType(),
            parameters=None,
        );
        node_.name_spec.type = func_type;
        return node_.name_spec.type;
    }
    return_type: TypeBase = types.UnknownType();
    if isinstance(node_.signature.return_type, uni.Expr) {
        return_type = self._convert_to_instance(
            self.get_type_of_expression(node_.signature.return_type)
        );
    } else {
        if self.prefetch and self.prefetch.none_type_class {
            return_type = self._convert_to_instance(self.prefetch.none_type_class);
        }
    }
    # Define helper function for parameter conversion.
    def _get_param_category(param: uni.ParamVar) -> types.ParameterCategory {
        if param.is_vararg {
            return types.ParameterCategory.ArgsList;
        }
        if param.is_kwargs {
            return types.ParameterCategory.KwargsDict;
        }
        return types.ParameterCategory.Positional;
    }
    # Define helper function for parameter kind conversion.
    def _convert_param_kind(kind: uni.ParamKind) -> types.ParamKind {
        match kind {
            case uni.ParamKind.POSONLY:
                return types.ParamKind.POSONLY;

            case uni.ParamKind.NORMAL:
                return types.ParamKind.NORMAL;

            case uni.ParamKind.VARARG:
                return types.ParamKind.VARARG;

            case uni.ParamKind.KWONLY:
                return types.ParamKind.KWONLY;

            case uni.ParamKind.KWARG:
                return types.ParamKind.KWARG;
                return types.ParamKind.NORMAL;

        }
    }
    parameters: list[types.Parameter] = [];
    for (idx, param) in enumerate(node_.signature.get_parameters()) {
        # TODO: Set parameter category for *args, and **kwargs
        param_type: TypeBase | None = None;

        if param.type_tag {
            param_type_cls = self.get_type_of_expression(param.type_tag.tag);
            param_type = self._convert_to_instance(param_type_cls);
        }

        parameters.append(
            types.Parameter(
                name=param.name.value,
                category=_get_param_category(param),
                param_type=param_type,
                default_value=param.value,
                is_self=(idx == 0 and self._is_expr_self(param.name)),
                is_cls=(idx == 0 and self._is_ability_classmethod(node_)),
                param_kind=_convert_param_kind(param.param_kind),
            )
        );
    }
    func_type = types.FunctionType(
        func_name=node_.name_spec.sym_name,
        return_type=return_type,
        parameters=parameters,
    );
    node_.name_spec.type = func_type;
    return func_type;
}

"""Return the effective type of the class."""
impl TypeEvaluator.get_type_of_class(
    self: TypeEvaluator, node_: uni.Archetype
) -> types.ClassType {
    # Is this type already cached?
    if node_.name_spec.type is not None {
        return cast(types.ClassType, node_.name_spec.type);
    }
    # Gather type parameters.
    type_params = self._extract_type_params(node_);
    base_classes: list[TypeBase] = [];
    for base_class in node_.base_classes or [] {
        base_class_type = self.get_type_of_expression(base_class);
        base_classes.append(base_class_type);
    }
    is_builtin_class = node_.find_parent_of_type(uni.Module) == self.builtins_module;
    # NOTE: obj, walker, node, edge are dataclass with symbol type as such but
    # other classes are with symbol type TYPE.
    # TODO: We need to handle @dataclass decorator as well.
    is_data_class = node_.sym_category != SymbolType.TYPE;
    cls_type = types.ClassType(
        types.ClassType.ClassDetailsShared(
            class_name=node_.name_spec.sym_name,
            symbol_table=node_,
            type_params=type_params,
            base_classes=base_classes,
            is_builtin_class=is_builtin_class,
            is_data_class=is_data_class,
        ),
        private=None,
        flags=types.TypeFlags.Instantiable,
    );
    # Compute the MRO for the class.
    type_utils.compute_mro_linearization(cls_type);
    # Cache the type, pyright is doing invalidateTypeCacheIfCanceled()
    # we're not doing that any time sooner.
    node_.name_spec.type = cls_type;
    return cls_type;
}

"""Return the effective type of the enum."""
impl TypeEvaluator.get_type_of_enum(
    self: TypeEvaluator, node_: uni.Enum
) -> types.ClassType {
    # Is this type already cached?
    if node_.name_spec.type is not None {
        return cast(types.ClassType, node_.name_spec.type);
    }

    # Enums inherit from Enum base class
    base_classes: list[TypeBase] = [];
    for base_class in node_.base_classes or [] {
        base_class_type = self.get_type_of_expression(base_class);
        base_classes.append(base_class_type);
    }

    is_builtin_class = node_.find_parent_of_type(uni.Module) == self.builtins_module;

    cls_type = types.ClassType(
        types.ClassType.ClassDetailsShared(
            class_name=node_.name_spec.sym_name,
            symbol_table=node_,
            type_params=[],
            base_classes=base_classes,
            is_builtin_class=is_builtin_class,
            is_data_class=False,
        ),
        private=None,
        flags=types.TypeFlags.Instantiable,
    );

    # Compute the MRO for the enum
    type_utils.compute_mro_linearization(cls_type);

    # Cache the type
    node_.name_spec.type = cls_type;
    return cls_type;
}

"""Return the built-in type with the given name."""
impl TypeEvaluator._get_type_from_module(
    self: TypeEvaluator, module: uni.Module, name: str
) -> TypeBase {
    if (symbol := type_utils.lookup_symtab(module, name, self.builtins_module)) is not None {
        return self.get_type_of_symbol(symbol);
    }
    return types.UnknownType();
}

impl TypeEvaluator.get_none_type(self: TypeEvaluator) -> TypeBase {
    if self.prefetch and self.prefetch.none_type_class {
        return self.prefetch.none_type_class;
    }
    return types.UnknownType();
}
