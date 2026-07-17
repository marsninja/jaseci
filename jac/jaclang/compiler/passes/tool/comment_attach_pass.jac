import jaclang.jac0core.unitree as uni;
import from jaclang.jac0core.passes { Transform }

obj NodeComments {
    has leading: list[uni.CommentToken] = [],
        trailing_inline: list[uni.CommentToken] = [],
        trailing_own: list[uni.CommentToken] = [],
        indent_trailing_own: bool = False;
}

obj CommentAttachPass(Transform[uni.Module, uni.Module]) {
    def transform(ir_in: uni.Module) -> uni.Module;
    def _node_comments(nd: uni.UniNode) -> NodeComments;
    def _attach_trailing_own(tok: uni.Token, comment: uni.CommentToken) -> None;
    def _largest_ending_at(tok: uni.Token) -> uni.UniNode;
    def _largest_starting_at(tok: uni.Token) -> uni.UniNode;
}
