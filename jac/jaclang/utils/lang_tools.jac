"""Language tools for the Jaclang project."""
"""Information about a kid."""
class AstKidInfo {
    def init(
        self: AstKidInfo, name: str, typ: str, <>default: (str | None) = None
    ) -> None;
}

"""Meta data about AST nodes."""
class UniNodeInfo {
    has type_map: dict[(str, type)] = {};

    def init(self: UniNodeInfo, cls: type) -> None;
    def process(self: UniNodeInfo, cls: type[uni.UniNode]) -> None;
}

"""Ast tools."""
class AstTool {
    def init(self: AstTool) -> None;
    def pass_template(self: AstTool) -> str;
    def py_uni_nodes(self: AstTool) -> str;
    def ir(self: AstTool, args: list[str]) -> str;
    def autodoc_uninode(self: AstTool) -> str;
    def automate_ref(self: AstTool) -> str;
}
