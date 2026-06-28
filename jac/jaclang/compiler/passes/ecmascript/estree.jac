"""ESTree AST Node Definitions for ECMAScript.

This module provides a complete implementation of the ESTree specification,
which defines the standard AST format for JavaScript and ECMAScript.

The ESTree specification represents ECMAScript programs as abstract syntax trees
that are language-agnostic and can be used for various tools like parsers,
transpilers, and code analysis tools.

Reference: https://github.com/estree/estree
"""
import from typing { TypeAlias }
import from typing { Literal as TypingLiteral }

glob SourceType: TypeAlias = TypingLiteral[('script', 'module')],
     VariableDeclarationKind: TypeAlias = TypingLiteral[('var', 'let', 'const')],
     PropertyKind: TypeAlias = TypingLiteral[('init', 'get', 'set')],
     MethodDefinitionKind: TypeAlias = TypingLiteral[
         ('constructor', 'method', 'get', 'set')
     ];

"""Source location information for a node."""
obj SourceLocation {
    has source: (str | None) = None,
        start: (Position | None) = None,
        end: (Position | None) = None;
}

"""Position in source code."""
obj Position {
    has line: int = 0,
        column: int = 0;
}

"""Base obj for all ESTree nodes."""
obj Node {
    has `type: str,
        loc: (SourceLocation | None) = None;
}

"""Identifier node."""
obj Identifier(Node) {
    has name: str = '',
        `type: TypingLiteral['Identifier'] = 'Identifier';
}

"""Private identifier for obj members (ES2022)."""
obj PrivateIdentifier(Node) {
    has name: str = '',
        `type: TypingLiteral['PrivateIdentifier'] = 'PrivateIdentifier';
}

"""Literal value node (supports BigInt in ES2020)."""
obj Literal(Node) {
    has value: str | bool | None | int | float = None,
        raw: (str | None) = None,
        bigint: (str | None) = None,
        `type: TypingLiteral['Literal'] = 'Literal';
}

"""Root node of an ESTree."""
obj Program(Node) {
    has body: list[(Statement | ModuleDeclaration)] = [],
        sourceType: SourceType = 'script',
        `type: TypingLiteral['Program'] = 'Program';
}

"""Expression statement."""
obj ExpressionStatement(Node) {
    has expression: (Expression | None) = None,
        `type: TypingLiteral['ExpressionStatement'] = 'ExpressionStatement';
}

"""Block statement."""
obj BlockStatement(Node) {
    has body: List[Statement] = [],
        `type: TypingLiteral['BlockStatement'] = 'BlockStatement';
}

"""Return statement."""
obj ReturnStatement(Node) {
    has argument: (Expression | None) = None,
        `type: TypingLiteral['ReturnStatement'] = 'ReturnStatement';
}

"""Break statement."""
obj BreakStatement(Node) {
    has label: (Identifier | None) = None,
        `type: TypingLiteral['BreakStatement'] = 'BreakStatement';
}

"""Continue statement."""
obj ContinueStatement(Node) {
    has label: (Identifier | None) = None,
        `type: TypingLiteral['ContinueStatement'] = 'ContinueStatement';
}

"""If statement."""
obj IfStatement(Node) {
    has `test: (Expression | None) = None,
        consequent: (Statement | None) = None,
        alternate: (Statement | None) = None,
        `type: TypingLiteral['IfStatement'] = 'IfStatement';
}

"""Switch statement."""
obj SwitchStatement(Node) {
    has discriminant: (Expression | None) = None,
        cases: list[SwitchCase] = [],
        `type: TypingLiteral['SwitchStatement'] = 'SwitchStatement';
}

"""Switch case clause."""
obj SwitchCase(Node) {
    has `test: (Expression | None) = None,
        consequent: list[Statement] = [],
        `type: TypingLiteral['SwitchCase'] = 'SwitchCase';
}

"""Throw statement."""
obj ThrowStatement(Node) {
    has argument: (Expression | None) = None,
        `type: TypingLiteral['ThrowStatement'] = 'ThrowStatement';
}

"""Try statement."""
obj TryStatement(Node) {
    has block: (BlockStatement | None) = None,
        handler: (CatchClause | None) = None,
        finalizer: (BlockStatement | None) = None,
        `type: TypingLiteral['TryStatement'] = 'TryStatement';
}

"""Catch clause."""
obj CatchClause(Node) {
    has param: (Pattern | None) = None,
        body: (BlockStatement | None) = None,
        `type: TypingLiteral['CatchClause'] = 'CatchClause';
}

"""While statement."""
obj WhileStatement(Node) {
    has `test: (Expression | None) = None,
        body: (Statement | None) = None,
        `type: TypingLiteral['WhileStatement'] = 'WhileStatement';
}

"""For statement."""
obj ForStatement(Node) {
    has `init: VariableDeclaration | Expression | None = None,
        `test: (Expression | None) = None,
        update: (Expression | None) = None,
        body: (Statement | None) = None,
        `type: TypingLiteral['ForStatement'] = 'ForStatement';
}

"""For-of statement (ES6)."""
obj ForOfStatement(Node) {
    has left: VariableDeclaration | Pattern | None = None,
        right: (Expression | None) = None,
        body: (Statement | None) = None,
        await_: bool = False,
        `type: TypingLiteral['ForOfStatement'] = 'ForOfStatement';
}

"""Function declaration."""
obj FunctionDeclaration(Node) {
    has id: (Identifier | None) = None,
        params: list[Pattern] = [],
        body: (BlockStatement | None) = None,
        generator: bool = False,
        async_: bool = False,
        `type: TypingLiteral['FunctionDeclaration'] = 'FunctionDeclaration';
}

"""Variable declaration."""
obj VariableDeclaration(Node) {
    has declarations: list[VariableDeclarator] = [],
        kind: VariableDeclarationKind = 'var',
        `type: TypingLiteral['VariableDeclaration'] = 'VariableDeclaration';
}

"""Variable declarator."""
obj VariableDeclarator(Node) {
    has id: (Pattern | None) = None,
        `init: (Expression | None) = None,
        `type: TypingLiteral['VariableDeclarator'] = 'VariableDeclarator';
}

"""This expression."""
obj ThisExpression(Node) {
    has `type: TypingLiteral['ThisExpression'] = 'ThisExpression';
}

"""Array expression."""
obj ArrayExpression(Node) {
    has elements: list[Expression | SpreadElement | None] = [],
        `type: TypingLiteral['ArrayExpression'] = 'ArrayExpression';
}

"""Object expression."""
obj ObjectExpression(Node) {
    has properties: list[(Property | SpreadElement)] = [],
        `type: TypingLiteral['ObjectExpression'] = 'ObjectExpression';
}

"""Object property."""
obj Property(Node) {
    has key: (Expression | Identifier | Literal | None) = None,
        value: (Expression | None) = None,
        kind: PropertyKind = 'init',
        method: bool = False,
        shorthand: bool = False,
        computed: bool = False,
        `type: TypingLiteral['Property'] = 'Property';
}

"""Function expression."""
obj FunctionExpression(Node) {
    has id: (Identifier | None) = None,
        params: list[Pattern] = [],
        body: (BlockStatement | None) = None,
        generator: bool = False,
        async_: bool = False,
        `type: TypingLiteral['FunctionExpression'] = 'FunctionExpression';
}

"""Arrow function expression (ES6)."""
obj ArrowFunctionExpression(Node) {
    has params: list[Pattern] = [],
        body: BlockStatement | Expression | None = None,
        expression: bool = False,
        async_: bool = False,
        `type: TypingLiteral['ArrowFunctionExpression'] = 'ArrowFunctionExpression';
}

"""Unary expression."""
obj UnaryExpression(Node) {
    has operator: str = '',
        prefix: bool = True,
        argument: (Expression | None) = None,
        `type: TypingLiteral['UnaryExpression'] = 'UnaryExpression';
}

"""Binary expression."""
obj BinaryExpression(Node) {
    has operator: str = '',
        left: (Expression | None) = None,
        right: (Expression | None) = None,
        `type: TypingLiteral['BinaryExpression'] = 'BinaryExpression';
}

"""Assignment expression."""
obj AssignmentExpression(Node) {
    has operator: str = '=',
        left: Pattern | Expression | None = None,
        right: (Expression | None) = None,
        `type: TypingLiteral['AssignmentExpression'] = 'AssignmentExpression';
}

"""Logical expression."""
obj LogicalExpression(Node) {
    has operator: str = '&&',
        left: (Expression | None) = None,
        right: (Expression | None) = None,
        `type: TypingLiteral['LogicalExpression'] = 'LogicalExpression';
}

"""Member expression."""
obj MemberExpression(Node) {
    has object: Expression | None = None,
        property: (Expression | None) = None,
        computed: bool = False,
        optional: bool = False,
        `type: TypingLiteral['MemberExpression'] = 'MemberExpression';
}

"""Conditional (ternary) expression."""
obj ConditionalExpression(Node) {
    has `test: (Expression | None) = None,
        consequent: (Expression | None) = None,
        alternate: (Expression | None) = None,
        `type: TypingLiteral['ConditionalExpression'] = 'ConditionalExpression';
}

"""Call expression."""
obj CallExpression(Node) {
    has callee: Expression | None = None,
        arguments: list[(Expression | SpreadElement)] = [],
        optional: bool = False,
        `type: TypingLiteral['CallExpression'] = 'CallExpression';
}

"""New expression."""
obj NewExpression(Node) {
    has callee: (Expression | None) = None,
        arguments: list[(Expression | SpreadElement)] = [],
        `type: TypingLiteral['NewExpression'] = 'NewExpression';
}

"""Await expression (ES2017)."""
obj AwaitExpression(Node) {
    has argument: (Expression | None) = None,
        `type: TypingLiteral['AwaitExpression'] = 'AwaitExpression';
}

"""Template literal (ES6)."""
obj TemplateLiteral(Node) {
    has quasis: list[TemplateElement] = [],
        expressions: list[Expression] = [],
        `type: TypingLiteral['TemplateLiteral'] = 'TemplateLiteral';
}

"""Template element."""
obj TemplateElement(Node) {
    has tail: bool = False,
        value: dict[(str, str)] = {},
        `type: TypingLiteral['TemplateElement'] = 'TemplateElement';
}

"""Spread element (ES6)."""
obj SpreadElement(Node) {
    has argument: (Expression | None) = None,
        `type: TypingLiteral['SpreadElement'] = 'SpreadElement';
}

"""Assignment pattern (default parameters)."""
obj AssignmentPattern(Node) {
    has left: (Pattern | None) = None,
        right: (Expression | None) = None,
        `type: TypingLiteral['AssignmentPattern'] = 'AssignmentPattern';
}

"""Array destructuring pattern."""
obj ArrayPattern(Node) {
    has elements: list[(Pattern | None)] = [],
        `type: TypingLiteral['ArrayPattern'] = 'ArrayPattern';
}

"""Object destructuring pattern."""
obj ObjectPattern(Node) {
    has properties: list[(AssignmentProperty | RestElement)] = [],
        `type: TypingLiteral['ObjectPattern'] = 'ObjectPattern';
}

"""Assignment property in object pattern."""
obj AssignmentProperty(Node) {
    has key: (Expression | Identifier | Literal | None) = None,
        value: (Pattern | None) = None,
        kind: PropertyKind = 'init',
        method: bool = False,
        shorthand: bool = False,
        computed: bool = False,
        `type: TypingLiteral['Property'] = 'Property';
}

"""Rest element."""
obj RestElement(Node) {
    has argument: (Pattern | None) = None,
        `type: TypingLiteral['RestElement'] = 'RestElement';
}

"""Class declaration."""
obj ClassDeclaration(Node) {
    has id: (Identifier | None) = None,
        superClass: (Expression | None) = None,
        body: (ClassBody | None) = None,
        `type: TypingLiteral['ClassDeclaration'] = 'ClassDeclaration';
}

"""Class body (ES2022: supports methods, properties, and static blocks)."""
obj ClassBody(Node) {
    has body: list[MethodDefinition | PropertyDefinition] = [],
        `type: TypingLiteral['ClassBody'] = 'ClassBody';
}

"""Method definition (ES2022: supports private identifiers)."""
obj MethodDefinition(Node) {
    has key: (Expression | Identifier | PrivateIdentifier | None) = None,
        value: (FunctionExpression | None) = None,
        kind: MethodDefinitionKind = 'method',
        computed: bool = False,
        `static: bool = False,
        `type: TypingLiteral['MethodDefinition'] = 'MethodDefinition';
}

"""Class field definition (ES2022)."""
obj PropertyDefinition(Node) {
    has key: (Expression | Identifier | PrivateIdentifier | None) = None,
        value: (Expression | None) = None,
        computed: bool = False,
        `static: bool = False,
        `type: TypingLiteral['PropertyDefinition'] = 'PropertyDefinition';
}

"""Import declaration."""
obj ImportDeclaration(Node) {
    has specifiers:
        list[ImportSpecifier | ImportDefaultSpecifier | ImportNamespaceSpecifier] = [],
        source: (Literal | None) = None,
        `type: TypingLiteral['ImportDeclaration'] = 'ImportDeclaration';
}

"""Import specifier."""
obj ImportSpecifier(Node) {
    has imported: (Identifier | None) = None,
        local: (Identifier | None) = None,
        `type: TypingLiteral['ImportSpecifier'] = 'ImportSpecifier';
}

"""Import default specifier."""
obj ImportDefaultSpecifier(Node) {
    has local: (Identifier | None) = None,
        `type: TypingLiteral['ImportDefaultSpecifier'] = 'ImportDefaultSpecifier';
}

"""Import namespace specifier."""
obj ImportNamespaceSpecifier(Node) {
    has local: (Identifier | None) = None,
        `type: TypingLiteral['ImportNamespaceSpecifier'] = 'ImportNamespaceSpecifier';
}

"""Export named declaration."""
obj ExportNamedDeclaration(Node) {
    has declaration: Declaration | Expression | None = None,
        specifiers: list[ExportSpecifier] = [],
        source: (Literal | None) = None,
        `type: TypingLiteral['ExportNamedDeclaration'] = 'ExportNamedDeclaration';
}

"""Export specifier."""
obj ExportSpecifier(Node) {
    has exported: (Identifier | None) = None,
        local: (Identifier | None) = None,
        `type: TypingLiteral['ExportSpecifier'] = 'ExportSpecifier';
}

# === JSX nodes (ESTree-JSX) ==================================================
# Mirror the ESTree-JSX spec (https://github.com/facebook/jsx/blob/main/AST.md),
# named with the `Jsx` casing used throughout this codebase (`uni.JsxElement`,
# `EsJsxProcessor`, `JsxExpression`) rather than the spec's all-caps `JSX` prefix:
# the unparser dispatches on `gen_{pascal_to_snake(type)}`, and a consecutive-caps
# `JSX` prefix would mangle the method name (`j_s_x_element`). These print as JSX
# *text* via `es_unparse` (Solid's `lower_view` path, Branch 3) and are never
# handed to a real ESTree consumer, so the internal `Jsx` casing is harmless.
"""JSX identifier — a tag or attribute name (`div`, `className`, `Foo`)."""
obj JsxIdentifier(Node) {
    has name: str = '',
        `type: TypingLiteral['JsxIdentifier'] = 'JsxIdentifier';
}

"""JSX member expression — a dotted component name (`Foo.Bar`, `a.b.c`)."""
obj JsxMemberExpression(Node) {
    has object: (JsxMemberExpression | JsxIdentifier | None) = None,
        property: (JsxIdentifier | None) = None,
        `type: TypingLiteral['JsxMemberExpression'] = 'JsxMemberExpression';
}

"""JSX empty expression — the contents of an empty container `{}` (e.g. a bare
JSX comment). Emitted as nothing."""
obj JsxEmptyExpression(Node) {
    has `type: TypingLiteral['JsxEmptyExpression'] = 'JsxEmptyExpression';
}

"""JSX expression container — `{expr}` in attribute-value or child position."""
obj JsxExpressionContainer(Node) {
    has expression: (Expression | JsxEmptyExpression | None) = None,
        `type: TypingLiteral['JsxExpressionContainer'] = 'JsxExpressionContainer';
}

"""JSX spread attribute — `{...obj}`."""
obj JsxSpreadAttribute(Node) {
    has argument: (Expression | None) = None,
        `type: TypingLiteral['JsxSpreadAttribute'] = 'JsxSpreadAttribute';
}

"""JSX attribute — `name`, `name="x"`, or `name={expr}`. A value-less attribute
(`disabled`) carries `value = None`."""
obj JsxAttribute(Node) {
    has name: (JsxIdentifier | None) = None,
        value: (Literal | JsxExpressionContainer | JsxElement | None) = None,
        `type: TypingLiteral['JsxAttribute'] = 'JsxAttribute';
}

"""JSX opening element — `<tag …>` or `<tag … />` (self-closing)."""
obj JsxOpeningElement(Node) {
    has name: (JsxIdentifier | JsxMemberExpression | None) = None,
        attributes: list[(JsxAttribute | JsxSpreadAttribute)] = [],
        selfClosing: bool = False,
        `type: TypingLiteral['JsxOpeningElement'] = 'JsxOpeningElement';
}

"""JSX closing element — `</tag>`."""
obj JsxClosingElement(Node) {
    has name: (JsxIdentifier | JsxMemberExpression | None) = None,
        `type: TypingLiteral['JsxClosingElement'] = 'JsxClosingElement';
}

"""JSX text — literal character data between tags. `raw` (if set) is emitted
verbatim; otherwise `value` is."""
obj JsxText(Node) {
    has value: str = '',
        raw: (str | None) = None,
        `type: TypingLiteral['JsxText'] = 'JsxText';
}

"""JSX element — an opening element, children, and (unless self-closing) a
closing element."""
obj JsxElement(Node) {
    has openingElement: (JsxOpeningElement | None) = None,
        children: list[JsxText | JsxExpressionContainer | JsxElement | JsxFragment] = [],
        closingElement: (JsxClosingElement | None) = None,
        `type: TypingLiteral['JsxElement'] = 'JsxElement';
}

"""JSX fragment — `<>…</>`."""
obj JsxFragment(Node) {
    has children: list[JsxText | JsxExpressionContainer | JsxElement | JsxFragment] = [],
        `type: TypingLiteral['JsxFragment'] = 'JsxFragment';
}

"""Represents slice operation info (e.g., arr[start:stop])."""
obj SliceInfo {
    has start: (Node | None) = None,
        stop: (Node | None) = None;
}

"""Represents index operation info (e.g., arr[index])."""
obj IndexInfo {
    has value: (Node | None) = None;
}

glob Statement = ExpressionStatement | BlockStatement | ReturnStatement | BreakStatement | ContinueStatement | IfStatement | SwitchStatement | ThrowStatement | TryStatement | WhileStatement | ForStatement | ForOfStatement | FunctionDeclaration | VariableDeclaration | ClassDeclaration,
     Expression = (
         Identifier | Literal | ThisExpression | ArrayExpression | ObjectExpression | FunctionExpression | ArrowFunctionExpression | UnaryExpression | BinaryExpression | AssignmentExpression | LogicalExpression | MemberExpression | ConditionalExpression | CallExpression | NewExpression | AwaitExpression | TemplateLiteral | JsxElement | JsxFragment
     ),
     Pattern = Identifier | ArrayPattern | ObjectPattern | AssignmentPattern | RestElement,
     Declaration = FunctionDeclaration | VariableDeclaration | ClassDeclaration,
     ModuleDeclaration = ImportDeclaration | ExportNamedDeclaration;

def es_node_to_dict(nd: Node) -> dict[str, any];
