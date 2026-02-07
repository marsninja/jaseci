"""Bootstrap AST node definitions for the Jac bootstrap compiler (Layer 1).

These are lightweight AST nodes used only by the bootstrap compiler chain.
They are NOT unitree nodes -- they exist solely within the bootstrap pipeline.
All nodes use the obj/has pattern so the seed compiler can compile them.
""";

# =============================================================================
# Token
# =============================================================================

obj BootstrapToken {
    has kind: str = "",
        value: str = "",
        line: int = 0,
        col: int = 0;
}

# =============================================================================
# Base AST Node
# =============================================================================

obj AstNode {
    has kind: str = "",
        line: int = 0,
        col: int = 0;
}

# =============================================================================
# Module
# =============================================================================

obj ModuleNode(AstNode) {
    has name: str = "",
        path: str = "",
        body: list[AstNode] = [],
        imports: list[AstNode] = [];
}

# =============================================================================
# Import
# =============================================================================

obj ImportNode(AstNode) {
    has module: str = "",
        names: list[AstNode] = [],
        is_from: bool = False;
}

obj ImportName(AstNode) {
    has name: str = "",
        alias: str | None = None;
}

# =============================================================================
# Class (obj)
# =============================================================================

obj ClassNode(AstNode) {
    has name: str = "",
        bases: list[AstNode] = [],
        body: list[AstNode] = [],
        decorators: list[AstNode] = [],
        is_enum: bool = False,
        is_abstract: bool = False;
}

# =============================================================================
# Field (has)
# =============================================================================

obj FieldNode(AstNode) {
    has name: str = "",
        type_ann: AstNode | None = None,
        default: AstNode | None = None,
        is_static: bool = False;
}

# =============================================================================
# Function / Method
# =============================================================================

obj FuncNode(AstNode) {
    has name: str = "",
        params: list[AstNode] = [],
        return_type: AstNode | None = None,
        body: list[AstNode] = [],
        decorators: list[AstNode] = [],
        is_static: bool = False,
        is_abstract: bool = False,
        has_self: bool = False;
}

obj ParamNode(AstNode) {
    has name: str = "",
        type_ann: AstNode | None = None,
        default: AstNode | None = None,
        is_star: bool = False,
        is_dstar: bool = False;
}

# =============================================================================
# Impl
# =============================================================================

obj ImplNode(AstNode) {
    has target: str = "",
        methods: list[AstNode] = [];
}

# =============================================================================
# Glob
# =============================================================================

obj GlobNode(AstNode) {
    has name: str = "",
        type_ann: AstNode | None = None,
        value: AstNode | None = None;
}

# =============================================================================
# Enum Member
# =============================================================================

obj EnumMemberNode(AstNode) {
    has name: str = "",
        value: AstNode | None = None;
}

# =============================================================================
# Statements
# =============================================================================

obj IfNode(AstNode) {
    has test: AstNode | None = None,
        body: list[AstNode] = [],
        elif_branches: list[AstNode] = [],
        else_body: list[AstNode] = [];
}

obj ElifNode(AstNode) {
    has test: AstNode | None = None,
        body: list[AstNode] = [];
}

obj WhileNode(AstNode) {
    has test: AstNode | None = None,
        body: list[AstNode] = [];
}

obj ForNode(AstNode) {
    has target: AstNode | None = None,
        iter: AstNode | None = None,
        body: list[AstNode] = [];
}

obj TryNode(AstNode) {
    has body: list[AstNode] = [],
        handlers: list[AstNode] = [],
        else_body: list[AstNode] = [],
        finally_body: list[AstNode] = [];
}

obj ExceptHandler(AstNode) {
    has exc_type: AstNode | None = None,
        name: str | None = None,
        body: list[AstNode] = [];
}

obj WithNode(AstNode) {
    has items: list[AstNode] = [],
        body: list[AstNode] = [];
}

obj WithItem(AstNode) {
    has context: AstNode | None = None,
        var: AstNode | None = None;
}

obj ReturnNode(AstNode) {
    has value: AstNode | None = None;
}

obj BreakNode(AstNode) { }
obj ContinueNode(AstNode) { }

obj AssignNode(AstNode) {
    has target: AstNode | None = None,
        value: AstNode | None = None;
}

obj AugAssignNode(AstNode) {
    has target: AstNode | None = None,
        op: str = "",
        value: AstNode | None = None;
}

obj AnnAssignNode(AstNode) {
    has target: AstNode | None = None,
        type_ann: AstNode | None = None,
        value: AstNode | None = None;
}

obj ExprStmtNode(AstNode) {
    has value: AstNode | None = None;
}

obj AssertNode(AstNode) {
    has test: AstNode | None = None,
        msg: AstNode | None = None;
}

obj DeleteNode(AstNode) {
    has targets: list[AstNode] = [];
}

obj PassNode(AstNode) { }

# =============================================================================
# Expressions
# =============================================================================

obj NameNode(AstNode) {
    has name: str = "";
}

obj ConstNode(AstNode) {
    has value: str = "",
        const_type: str = "str";
}

obj FStringNode(AstNode) {
    has parts: list[AstNode] = [];
}

obj FStringPart(AstNode) {
    has is_expr: bool = False,
        text: str = "",
        expr: AstNode | None = None;
}

obj BinOpNode(AstNode) {
    has left: AstNode | None = None,
        op: str = "",
        right: AstNode | None = None;
}

obj UnaryOpNode(AstNode) {
    has op: str = "",
        operand: AstNode | None = None;
}

obj BoolOpNode(AstNode) {
    has op: str = "",
        values: list[AstNode] = [];
}

obj CompareNode(AstNode) {
    has left: AstNode | None = None,
        ops: list[str] = [],
        comparators: list[AstNode] = [];
}

obj CallNode(AstNode) {
    has func: AstNode | None = None,
        args: list[AstNode] = [],
        kwargs: list[AstNode] = [];
}

obj KeywordArg(AstNode) {
    has name: str | None = None,
        value: AstNode | None = None;
}

obj AttrNode(AstNode) {
    has value: AstNode | None = None,
        attr: str = "";
}

obj SubscriptNode(AstNode) {
    has value: AstNode | None = None,
        index: AstNode | None = None;
}

obj TernaryNode(AstNode) {
    has test: AstNode | None = None,
        body: AstNode | None = None,
        orelse: AstNode | None = None;
}

obj TupleNode(AstNode) {
    has elts: list[AstNode] = [];
}

obj ListNode(AstNode) {
    has elts: list[AstNode] = [];
}

obj DictNode(AstNode) {
    has keys: list[AstNode] = [],
        values: list[AstNode] = [];
}

obj SetNode(AstNode) {
    has elts: list[AstNode] = [];
}

# =============================================================================
# Comprehension Nodes
# =============================================================================

obj ListCompNode(AstNode) {
    has elt: AstNode | None = None,
        generators: list[AstNode] = [];
}

obj DictCompNode(AstNode) {
    has key: AstNode | None = None,
        value: AstNode | None = None,
        generators: list[AstNode] = [];
}

obj ComprehensionGen(AstNode) {
    has target: AstNode | None = None,
        iter: AstNode | None = None,
        ifs: list[AstNode] = [];
}

# =============================================================================
# Type Annotation Nodes
# =============================================================================

obj TypeNode(AstNode) {
    has name: str = "",
        args: list[AstNode] = [];
}

obj UnionTypeNode(AstNode) {
    has types: list[AstNode] = [];
}

# =============================================================================
# Decorator
# =============================================================================

obj DecoratorNode(AstNode) {
    has expr: AstNode | None = None;
}

# =============================================================================
# Star / DblStar Expressions
# =============================================================================

obj StarExpr(AstNode) {
    has value: AstNode | None = None;
}

obj DblStarExpr(AstNode) {
    has value: AstNode | None = None;
}

# =============================================================================
# Walrus Operator
# =============================================================================

obj WalrusNode(AstNode) {
    has target: AstNode | None = None,
        value: AstNode | None = None;
}

# =============================================================================
# Lambda
# =============================================================================

obj LambdaNode(AstNode) {
    has params: list[AstNode] = [],
        body: AstNode | None = None;
}

# =============================================================================
# Slice
# =============================================================================

obj SliceNode(AstNode) {
    has lower: AstNode | None = None,
        upper: AstNode | None = None,
        step: AstNode | None = None;
}
