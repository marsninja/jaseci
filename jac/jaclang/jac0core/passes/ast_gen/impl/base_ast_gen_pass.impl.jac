"""Implementation for base_ast_gen_pass constructs."""

"""Return the module's standalone statement stream for codegen.

    Annex/test/variant bodies are already merged into nd.body by JacAnnexPass.
    Matched ImplDefs are emitted via their declarations, so they are dropped
    from this standalone stream.
"""
impl BaseAstGenPass._merge_module_bodies(nd: uni.Module) -> list {
    return [
        item
        for item in nd.body
        if not isinstance(item, uni.ImplDef)
    ];
}

"""Instantiate child passes for sub-modules.

    Annex/test/variant bodies are merged into the head module, so there are no
    separate sub-modules to codegen.
"""
impl BaseAstGenPass._init_child_passes(
    pass_class: type[ChildPassT]
) -> list[ChildPassT] {
    return [];
}

"""Flatten nested AST lists while skipping ``None`` entries."""
impl BaseAstGenPass._flatten_ast_list(items: list[T | list[T] | None]) -> list[T] {
    flattened: list[T] = [];
    for item in items {
        if isinstance(item, `list) {
            flattened.extend(item);
        } elif (item is not None) {
            flattened.append(item);
        }
    }
    return flattened;
}
