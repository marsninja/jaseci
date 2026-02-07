"""Bootstrap parser for the Jac bootstrap compiler (Layer 1).

Recursive-descent parser for the expanded Jac subset needed by the bootstrap
compiler. Produces bootstrap AST nodes. Handles: obj, enum, impl, can/def,
glob, import, has, decorators, *args, **kwargs, comprehensions, try/except,
with, multiple inheritance, assert, del, lambda, slices, etc.

Written using ONLY the Layer 0 subset so the seed compiler can compile it.
""";

import from jaclang.bootstrap.bootstrap_ast {
    AstNode, ModuleNode, ClassNode, FuncNode, ParamNode, FieldNode,
    ImplNode, GlobNode, ImportNode, ImportName, EnumMemberNode,
    IfNode, ElifNode, WhileNode, ForNode, ReturnNode, BreakNode,
    ContinueNode, AssignNode, AugAssignNode, AnnAssignNode, ExprStmtNode,
    TryNode, ExceptHandler, WithNode, WithItem, AssertNode, DeleteNode,
    PassNode, NameNode, ConstNode, FStringNode, FStringPart,
    BinOpNode, UnaryOpNode, BoolOpNode, CompareNode,
    CallNode, KeywordArg, AttrNode, SubscriptNode, TernaryNode,
    TupleNode, ListNode, DictNode, SetNode,
    ListCompNode, DictCompNode, ComprehensionGen,
    TypeNode, UnionTypeNode, DecoratorNode,
    StarExpr, DblStarExpr, WalrusNode, LambdaNode, SliceNode,
    BootstrapToken
}
import from jaclang.bootstrap.bootstrap_lexer { BootstrapLexer }

# =============================================================================
# Parser
# =============================================================================

obj BootstrapParser {
    has tokens: list[BootstrapToken] = [],
        pos: int = 0,
        filename: str = "<bootstrap>";

    # -------------------------------------------------------------------------
    # Token Helpers
    # -------------------------------------------------------------------------

    def current() -> BootstrapToken {
        if self.pos < len(self.tokens) {
            return self.tokens[self.pos];
        }
        return BootstrapToken(kind="EOF", value="", line=0, col=0);
    }

    def at_end() -> bool {
        return self.current().kind == "EOF";
    }

    def check(kind: str) -> bool {
        return self.current().kind == kind;
    }

    def check_value(kind: str, value: str) -> bool {
        t = self.current();
        return t.kind == kind and t.value == value;
    }

    def advance() -> BootstrapToken {
        tok = self.current();
        self.pos = self.pos + 1;
        return tok;
    }

    def expect(kind: str) -> BootstrapToken {
        tok = self.current();
        if tok.kind != kind {
            self.error(f"Expected {kind}, got {tok.kind} ({tok.value})");
        }
        self.pos = self.pos + 1;
        return tok;
    }

    def match(kind: str) -> BootstrapToken | None {
        if self.current().kind == kind {
            return self.advance();
        }
        return None;
    }

    def match_value(kind: str, value: str) -> BootstrapToken | None {
        t = self.current();
        if t.kind == kind and t.value == value {
            return self.advance();
        }
        return None;
    }

    def peek_kind(offset: int) -> str {
        p = self.pos + offset;
        if p < len(self.tokens) {
            return self.tokens[p].kind;
        }
        return "EOF";
    }

    def error(msg: str) -> None {
        tok = self.current();
        raise_msg = f"{self.filename}:{tok.line}:{tok.col}: {msg}";
        print(raise_msg);
        x: list[int] = [];
        y = x[999999];
    }

    # -------------------------------------------------------------------------
    # Module Parsing
    # -------------------------------------------------------------------------

    def parse_module(source: str, filename: str) -> ModuleNode {
        lex = BootstrapLexer(source=source, filename=filename);
        self.tokens = lex.tokenize();
        self.pos = 0;
        self.filename = filename;
        body = self.parse_module_body();
        return ModuleNode(kind="module", name=filename, path=filename, body=body);
    }

    def parse_module_body() -> list[AstNode] {
        stmts: list[AstNode] = [];
        while not self.at_end() {
            # Decorators
            decorators: list[AstNode] = [];
            while self.check("AT") {
                decorators.append(self.parse_decorator());
            }

            if self.check("KW_OBJ") or self.check("KW_NODE") or self.check("KW_EDGE") or self.check("KW_WALKER") {
                stmts.append(self.parse_obj(decorators));
            } elif self.check("KW_ENUM") {
                stmts.append(self.parse_enum(decorators));
            } elif self.check("KW_IMPL") {
                stmts.append(self.parse_impl());
            } elif self.check("KW_DEF") or self.check("KW_CAN") {
                stmts.append(self.parse_function(decorators, False));
            } elif self.check("KW_GLOB") {
                items = self.parse_glob();
                for item in items {
                    stmts.append(item);
                }
            } elif self.check("KW_IMPORT") {
                stmts.append(self.parse_import());
            } elif self.check("KW_CLASS") {
                stmts.append(self.parse_class(decorators));
            } elif len(decorators) > 0 {
                self.error("Decorators not followed by declaration");
            } else {
                stmts.append(self.parse_stmt());
            }
        }
        return stmts;
    }

    # -------------------------------------------------------------------------
    # Decorators
    # -------------------------------------------------------------------------

    def parse_decorator() -> DecoratorNode {
        tok = self.expect("AT");
        expr = self.parse_expr();
        return DecoratorNode(kind="decorator", expr=expr, line=tok.line, col=tok.col);
    }

    # -------------------------------------------------------------------------
    # Object Parsing (obj / node / edge / walker)
    # -------------------------------------------------------------------------

    def parse_obj(decorators: list[AstNode]) -> ClassNode {
        tok = self.advance();
        name = self.expect("NAME").value;
        bases: list[AstNode] = [];
        if self.match("LPAREN") is not None {
            while not self.check("RPAREN") and not self.at_end() {
                bases.append(self.parse_type_expr());
                if self.match("COMMA") is None {
                    break;
                }
            }
            self.expect("RPAREN");
        }
        self.expect("LBRACE");
        body = self.parse_class_body();
        self.expect("RBRACE");
        return ClassNode(
            kind="obj", name=name, bases=bases, body=body,
            decorators=decorators, is_enum=False,
            line=tok.line, col=tok.col
        );
    }

    def parse_class_body() -> list[AstNode] {
        stmts: list[AstNode] = [];
        while not self.check("RBRACE") and not self.at_end() {
            decorators: list[AstNode] = [];
            while self.check("AT") {
                decorators.append(self.parse_decorator());
            }
            if self.check("KW_HAS") {
                items = self.parse_has();
                for item in items {
                    stmts.append(item);
                }
            } elif self.check("KW_DEF") or self.check("KW_CAN") {
                stmts.append(self.parse_function(decorators, True));
            } elif self.check("KW_PASS") {
                self.advance();
                self.match("SEMI");
                stmts.append(PassNode(kind="pass"));
            } else {
                stmts.append(self.parse_stmt());
            }
        }
        return stmts;
    }

    # -------------------------------------------------------------------------
    # Class Parsing (Python-style)
    # -------------------------------------------------------------------------

    def parse_class(decorators: list[AstNode]) -> ClassNode {
        tok = self.expect("KW_CLASS");
        name = self.expect("NAME").value;
        bases: list[AstNode] = [];
        if self.match("LPAREN") is not None {
            while not self.check("RPAREN") and not self.at_end() {
                bases.append(self.parse_type_expr());
                if self.match("COMMA") is None {
                    break;
                }
            }
            self.expect("RPAREN");
        }
        self.expect("LBRACE");
        body = self.parse_class_body();
        self.expect("RBRACE");
        return ClassNode(
            kind="class", name=name, bases=bases, body=body,
            decorators=decorators, is_enum=False,
            line=tok.line, col=tok.col
        );
    }

    # -------------------------------------------------------------------------
    # Field Parsing (has)
    # -------------------------------------------------------------------------

    def parse_has() -> list[AstNode] {
        tok = self.expect("KW_HAS");
        fields: list[AstNode] = [];
        is_static = False;
        while True {
            fname = self.expect("NAME").value;
            self.expect("COLON");
            ftype = self.parse_type_expr();
            default: AstNode | None = None;
            if self.match("EQ") is not None {
                default = self.parse_expr();
            }
            fields.append(FieldNode(
                kind="field", name=fname, type_ann=ftype,
                default=default, is_static=is_static,
                line=tok.line, col=tok.col
            ));
            if self.match("COMMA") is None {
                break;
            }
        }
        self.expect("SEMI");
        return fields;
    }

    # -------------------------------------------------------------------------
    # Enum Parsing
    # -------------------------------------------------------------------------

    def parse_enum(decorators: list[AstNode]) -> ClassNode {
        tok = self.expect("KW_ENUM");
        name = self.expect("NAME").value;
        bases: list[AstNode] = [];
        if self.match("LPAREN") is not None {
            while not self.check("RPAREN") and not self.at_end() {
                bases.append(self.parse_type_expr());
                if self.match("COMMA") is None {
                    break;
                }
            }
            self.expect("RPAREN");
        }
        self.expect("LBRACE");
        body: list[AstNode] = [];
        while not self.check("RBRACE") and not self.at_end() {
            mname = self.expect("NAME").value;
            mval: AstNode | None = None;
            if self.match("EQ") is not None {
                mval = self.parse_expr();
            }
            body.append(EnumMemberNode(kind="enum_member", name=mname, value=mval));
            self.match("COMMA");
        }
        self.expect("RBRACE");
        return ClassNode(
            kind="enum", name=name, bases=bases, body=body,
            decorators=decorators, is_enum=True,
            line=tok.line, col=tok.col
        );
    }

    # -------------------------------------------------------------------------
    # Impl Parsing
    # -------------------------------------------------------------------------

    def parse_impl() -> ImplNode {
        tok = self.expect("KW_IMPL");
        target = self.expect("NAME").value;
        # Single-method form: impl Foo.bar(...) { ... }
        if self.check("DOT") and self.peek_kind(1) == "NAME" and self.peek_kind(2) == "LPAREN" {
            self.advance();
            mname = self.expect("NAME").value;
            func = self.parse_function_after_name(mname, [], True);
            return ImplNode(
                kind="impl", target=target,
                methods=[func],
                line=tok.line, col=tok.col
            );
        }
        # Block form: impl Foo { ... }
        self.expect("LBRACE");
        methods: list[AstNode] = [];
        while not self.check("RBRACE") and not self.at_end() {
            decorators: list[AstNode] = [];
            while self.check("AT") {
                decorators.append(self.parse_decorator());
            }
            if self.check("KW_DEF") or self.check("KW_CAN") {
                methods.append(self.parse_function(decorators, True));
            } else {
                self.error("Expected def/can inside impl block");
            }
        }
        self.expect("RBRACE");
        return ImplNode(
            kind="impl", target=target, methods=methods,
            line=tok.line, col=tok.col
        );
    }

    # -------------------------------------------------------------------------
    # Function / Method Parsing
    # -------------------------------------------------------------------------

    def parse_function(decorators: list[AstNode], is_method: bool) -> FuncNode {
        tok = self.advance();
        name = self.expect("NAME").value;
        return self.parse_function_after_name(name, decorators, is_method);
    }

    def parse_function_after_name(name: str, decorators: list[AstNode], is_method: bool) -> FuncNode {
        tok = self.current();
        self.expect("LPAREN");
        params = self.parse_params();
        self.expect("RPAREN");
        ret_type: AstNode | None = None;
        if self.match("ARROW") is not None {
            ret_type = self.parse_type_expr();
        }
        # Abstract (no body, just semicolon)
        if self.match("SEMI") is not None {
            return FuncNode(
                kind="func", name=name, params=params,
                return_type=ret_type, body=[],
                decorators=decorators, is_abstract=True,
                has_self=is_method,
                line=tok.line, col=tok.col
            );
        }
        self.expect("LBRACE");
        body = self.parse_block();
        self.expect("RBRACE");
        return FuncNode(
            kind="func", name=name, params=params,
            return_type=ret_type, body=body,
            decorators=decorators, is_abstract=False,
            has_self=is_method,
            line=tok.line, col=tok.col
        );
    }

    def parse_params() -> list[AstNode] {
        params: list[AstNode] = [];
        while not self.check("RPAREN") and not self.at_end() {
            is_star = False;
            is_dstar = False;
            if self.match("STAR") is not None {
                is_star = True;
            } elif self.match("DSTAR") is not None {
                is_dstar = True;
            }
            pname = self.expect("NAME").value;
            ptype: AstNode | None = None;
            pdefault: AstNode | None = None;
            if self.match("COLON") is not None {
                ptype = self.parse_type_expr();
            }
            if self.match("EQ") is not None {
                pdefault = self.parse_expr();
            }
            params.append(ParamNode(
                kind="param", name=pname, type_ann=ptype,
                default=pdefault, is_star=is_star, is_dstar=is_dstar
            ));
            if self.match("COMMA") is None {
                break;
            }
        }
        return params;
    }

    # -------------------------------------------------------------------------
    # Import Parsing
    # -------------------------------------------------------------------------

    def parse_import() -> ImportNode {
        tok = self.expect("KW_IMPORT");
        if self.match("KW_FROM") is not None {
            module = self.parse_dotted_name();
            self.expect("LBRACE");
            names: list[AstNode] = [];
            while not self.check("RBRACE") and not self.at_end() {
                n = self.expect("NAME").value;
                alias: str | None = None;
                if self.match("KW_AS") is not None {
                    alias = self.expect("NAME").value;
                }
                names.append(ImportName(kind="import_name", name=n, alias=alias));
                self.match("COMMA");
            }
            self.expect("RBRACE");
            return ImportNode(kind="import", module=module, names=names, is_from=True,
                              line=tok.line, col=tok.col);
        }
        module = self.parse_dotted_name();
        self.expect("SEMI");
        return ImportNode(kind="import", module=module, names=[], is_from=False,
                          line=tok.line, col=tok.col);
    }

    # -------------------------------------------------------------------------
    # Glob Parsing
    # -------------------------------------------------------------------------

    def parse_glob() -> list[AstNode] {
        tok = self.expect("KW_GLOB");
        stmts: list[AstNode] = [];
        while True {
            name = self.expect("NAME").value;
            type_ann: AstNode | None = None;
            value: AstNode | None = None;
            if self.match("COLON") is not None {
                type_ann = self.parse_type_expr();
            }
            if self.match("EQ") is not None {
                value = self.parse_expr();
            }
            stmts.append(GlobNode(
                kind="glob", name=name, type_ann=type_ann, value=value,
                line=tok.line, col=tok.col
            ));
            if self.match("COMMA") is None {
                break;
            }
        }
        self.expect("SEMI");
        return stmts;
    }

    # -------------------------------------------------------------------------
    # Statement Parsing
    # -------------------------------------------------------------------------

    def parse_block() -> list[AstNode] {
        stmts: list[AstNode] = [];
        while not self.check("RBRACE") and not self.at_end() {
            stmts.append(self.parse_stmt());
        }
        return stmts;
    }

    def parse_stmt() -> AstNode {
        if self.check("KW_IF") {
            return self.parse_if();
        }
        if self.check("KW_WHILE") {
            return self.parse_while();
        }
        if self.check("KW_FOR") {
            return self.parse_for();
        }
        if self.check("KW_RETURN") {
            return self.parse_return();
        }
        if self.check("KW_BREAK") {
            tok = self.advance();
            self.expect("SEMI");
            return BreakNode(kind="break", line=tok.line, col=tok.col);
        }
        if self.check("KW_CONTINUE") {
            tok = self.advance();
            self.expect("SEMI");
            return ContinueNode(kind="continue", line=tok.line, col=tok.col);
        }
        if self.check("KW_TRY") {
            return self.parse_try();
        }
        if self.check("KW_WITH") {
            return self.parse_with();
        }
        if self.check("KW_ASSERT") {
            return self.parse_assert();
        }
        if self.check("KW_DEL") {
            return self.parse_delete();
        }
        if self.check("KW_PASS") {
            tok = self.advance();
            self.match("SEMI");
            return PassNode(kind="pass", line=tok.line, col=tok.col);
        }
        if self.check("KW_RAISE") {
            return self.parse_raise();
        }
        return self.parse_expr_or_assign();
    }

    # -------------------------------------------------------------------------
    # Control Flow
    # -------------------------------------------------------------------------

    def parse_if() -> IfNode {
        tok = self.expect("KW_IF");
        test = self.parse_expr();
        self.expect("LBRACE");
        body = self.parse_block();
        self.expect("RBRACE");
        elif_branches: list[AstNode] = [];
        else_body: list[AstNode] = [];
        while self.match("KW_ELIF") is not None {
            etest = self.parse_expr();
            self.expect("LBRACE");
            ebody = self.parse_block();
            self.expect("RBRACE");
            elif_branches.append(ElifNode(kind="elif", test=etest, body=ebody));
        }
        if self.match("KW_ELSE") is not None {
            self.expect("LBRACE");
            else_body = self.parse_block();
            self.expect("RBRACE");
        }
        return IfNode(kind="if", test=test, body=body,
                       elif_branches=elif_branches, else_body=else_body,
                       line=tok.line, col=tok.col);
    }

    def parse_while() -> WhileNode {
        tok = self.expect("KW_WHILE");
        test = self.parse_expr();
        self.expect("LBRACE");
        body = self.parse_block();
        self.expect("RBRACE");
        return WhileNode(kind="while", test=test, body=body,
                          line=tok.line, col=tok.col);
    }

    def parse_for() -> ForNode {
        tok = self.expect("KW_FOR");
        target: AstNode | None = None;
        if self.match("LPAREN") is not None {
            elts: list[AstNode] = [];
            while not self.check("RPAREN") and not self.at_end() {
                t = self.expect("NAME");
                elts.append(NameNode(kind="name", name=t.value, line=t.line, col=t.col));
                self.match("COMMA");
            }
            self.expect("RPAREN");
            target = TupleNode(kind="tuple", elts=elts, line=tok.line, col=tok.col);
        } else {
            t = self.expect("NAME");
            target = NameNode(kind="name", name=t.value, line=t.line, col=t.col);
        }
        self.expect("KW_IN");
        iter_expr = self.parse_expr();
        self.expect("LBRACE");
        body = self.parse_block();
        self.expect("RBRACE");
        return ForNode(kind="for", target=target, iter=iter_expr, body=body,
                        line=tok.line, col=tok.col);
    }

    def parse_return() -> ReturnNode {
        tok = self.expect("KW_RETURN");
        value: AstNode | None = None;
        if not self.check("SEMI") {
            value = self.parse_expr();
        }
        self.expect("SEMI");
        return ReturnNode(kind="return", value=value, line=tok.line, col=tok.col);
    }

    # -------------------------------------------------------------------------
    # Try / Except / With
    # -------------------------------------------------------------------------

    def parse_try() -> TryNode {
        tok = self.expect("KW_TRY");
        self.expect("LBRACE");
        body = self.parse_block();
        self.expect("RBRACE");
        handlers: list[AstNode] = [];
        while self.match("KW_EXCEPT") is not None {
            exc_type: AstNode | None = None;
            exc_name: str | None = None;
            if not self.check("LBRACE") {
                exc_type = self.parse_expr();
                if self.match("KW_AS") is not None {
                    exc_name = self.expect("NAME").value;
                }
            }
            self.expect("LBRACE");
            hbody = self.parse_block();
            self.expect("RBRACE");
            handlers.append(ExceptHandler(
                kind="except", exc_type=exc_type, name=exc_name, body=hbody
            ));
        }
        else_body: list[AstNode] = [];
        if self.match("KW_ELSE") is not None {
            self.expect("LBRACE");
            else_body = self.parse_block();
            self.expect("RBRACE");
        }
        finally_body: list[AstNode] = [];
        if self.match("KW_FINALLY") is not None {
            self.expect("LBRACE");
            finally_body = self.parse_block();
            self.expect("RBRACE");
        }
        return TryNode(kind="try", body=body, handlers=handlers,
                        else_body=else_body, finally_body=finally_body,
                        line=tok.line, col=tok.col);
    }

    def parse_with() -> WithNode {
        tok = self.expect("KW_WITH");
        items: list[AstNode] = [];
        while True {
            ctx = self.parse_expr();
            var: AstNode | None = None;
            if self.match("KW_AS") is not None {
                t = self.expect("NAME");
                var = NameNode(kind="name", name=t.value, line=t.line, col=t.col);
            }
            items.append(WithItem(kind="with_item", context=ctx, var=var));
            if self.match("COMMA") is None {
                break;
            }
        }
        self.expect("LBRACE");
        body = self.parse_block();
        self.expect("RBRACE");
        return WithNode(kind="with", items=items, body=body,
                         line=tok.line, col=tok.col);
    }

    # -------------------------------------------------------------------------
    # Assert / Delete / Raise
    # -------------------------------------------------------------------------

    def parse_assert() -> AssertNode {
        tok = self.expect("KW_ASSERT");
        test = self.parse_expr();
        msg: AstNode | None = None;
        if self.match("COMMA") is not None {
            msg = self.parse_expr();
        }
        self.expect("SEMI");
        return AssertNode(kind="assert", test=test, msg=msg,
                           line=tok.line, col=tok.col);
    }

    def parse_delete() -> DeleteNode {
        tok = self.expect("KW_DEL");
        targets: list[AstNode] = [];
        targets.append(self.parse_expr());
        while self.match("COMMA") is not None {
            targets.append(self.parse_expr());
        }
        self.expect("SEMI");
        return DeleteNode(kind="del", targets=targets,
                           line=tok.line, col=tok.col);
    }

    def parse_raise() -> AstNode {
        tok = self.expect("KW_RAISE");
        value: AstNode | None = None;
        if not self.check("SEMI") {
            value = self.parse_expr();
        }
        self.expect("SEMI");
        return ExprStmtNode(kind="raise", value=value,
                             line=tok.line, col=tok.col);
    }

    # -------------------------------------------------------------------------
    # Assignment / Expression Statement
    # -------------------------------------------------------------------------

    def parse_expr_or_assign() -> AstNode {
        tok = self.current();
        expr = self.parse_expr();

        # Type-annotated assignment
        if self.check("COLON") and expr.kind == "name" {
            self.advance();
            type_ann = self.parse_type_expr();
            value: AstNode | None = None;
            if self.match("EQ") is not None {
                value = self.parse_expr();
            }
            self.expect("SEMI");
            return AnnAssignNode(kind="ann_assign", target=expr,
                                  type_ann=type_ann, value=value,
                                  line=tok.line, col=tok.col);
        }

        # Simple assignment
        if self.match("EQ") is not None {
            value = self.parse_expr();
            self.expect("SEMI");
            return AssignNode(kind="assign", target=expr, value=value,
                               line=tok.line, col=tok.col);
        }

        # Augmented assignment
        if self.check("PLUS_EQ") {
            self.advance();
            value = self.parse_expr();
            self.expect("SEMI");
            return AugAssignNode(kind="aug_assign", target=expr, op="+=", value=value,
                                  line=tok.line, col=tok.col);
        }
        if self.check("MINUS_EQ") {
            self.advance();
            value = self.parse_expr();
            self.expect("SEMI");
            return AugAssignNode(kind="aug_assign", target=expr, op="-=", value=value,
                                  line=tok.line, col=tok.col);
        }
        if self.check("STAR_EQ") {
            self.advance();
            value = self.parse_expr();
            self.expect("SEMI");
            return AugAssignNode(kind="aug_assign", target=expr, op="*=", value=value,
                                  line=tok.line, col=tok.col);
        }
        if self.check("SLASH_EQ") {
            self.advance();
            value = self.parse_expr();
            self.expect("SEMI");
            return AugAssignNode(kind="aug_assign", target=expr, op="/=", value=value,
                                  line=tok.line, col=tok.col);
        }

        # Expression statement
        self.expect("SEMI");
        return ExprStmtNode(kind="expr_stmt", value=expr,
                             line=tok.line, col=tok.col);
    }

    # -------------------------------------------------------------------------
    # Expression Parsing (Precedence Climbing)
    # -------------------------------------------------------------------------

    def parse_expr() -> AstNode {
        return self.parse_ternary();
    }

    def parse_ternary() -> AstNode {
        expr = self.parse_or();
        if self.match("KW_IF") is not None {
            test = self.parse_or();
            self.expect("KW_ELSE");
            orelse = self.parse_ternary();
            return TernaryNode(kind="ternary", test=test, body=expr, orelse=orelse);
        }
        return expr;
    }

    def parse_or() -> AstNode {
        left = self.parse_and();
        while self.match("KW_OR") is not None {
            right = self.parse_and();
            vals: list[AstNode] = [];
            vals.append(left);
            vals.append(right);
            left = BoolOpNode(kind="bool_op", op="or", values=vals);
        }
        return left;
    }

    def parse_and() -> AstNode {
        left = self.parse_not();
        while self.match("KW_AND") is not None {
            right = self.parse_not();
            vals: list[AstNode] = [];
            vals.append(left);
            vals.append(right);
            left = BoolOpNode(kind="bool_op", op="and", values=vals);
        }
        return left;
    }

    def parse_not() -> AstNode {
        if self.match("KW_NOT") is not None {
            operand = self.parse_not();
            return UnaryOpNode(kind="unary_op", op="not", operand=operand);
        }
        return self.parse_comparison();
    }

    # -------------------------------------------------------------------------
    # Comparison and Arithmetic
    # -------------------------------------------------------------------------

    def parse_comparison() -> AstNode {
        left = self.parse_bitor();
        ops: list[str] = [];
        comparators: list[AstNode] = [];
        while True {
            op = self.match_cmp_op();
            if op == "" {
                break;
            }
            ops.append(op);
            comparators.append(self.parse_bitor());
        }
        if len(ops) > 0 {
            return CompareNode(kind="compare", left=left,
                                ops=ops, comparators=comparators);
        }
        return left;
    }

    def match_cmp_op() -> str {
        if self.match("EQEQ") is not None {
            return "==";
        }
        if self.match("NEQ") is not None {
            return "!=";
        }
        if self.match("LTE") is not None {
            return "<=";
        }
        if self.match("GTE") is not None {
            return ">=";
        }
        if self.match("LT") is not None {
            return "<";
        }
        if self.match("GT") is not None {
            return ">";
        }
        if self.check("KW_NOT") and self.peek_kind(1) == "KW_IN" {
            self.advance();
            self.advance();
            return "not in";
        }
        if self.match("KW_IN") is not None {
            return "in";
        }
        if self.check("KW_IS") {
            self.advance();
            if self.match("KW_NOT") is not None {
                return "is not";
            }
            return "is";
        }
        return "";
    }

    def parse_bitor() -> AstNode {
        left = self.parse_addition();
        while self.match("PIPE") is not None {
            right = self.parse_addition();
            left = BinOpNode(kind="bin_op", left=left, op="|", right=right);
        }
        return left;
    }

    def parse_addition() -> AstNode {
        left = self.parse_multiplication();
        while True {
            if self.match("PLUS") is not None {
                right = self.parse_multiplication();
                left = BinOpNode(kind="bin_op", left=left, op="+", right=right);
            } elif self.match("MINUS") is not None {
                right = self.parse_multiplication();
                left = BinOpNode(kind="bin_op", left=left, op="-", right=right);
            } else {
                break;
            }
        }
        return left;
    }

    def parse_multiplication() -> AstNode {
        left = self.parse_unary();
        while True {
            if self.match("STAR") is not None {
                right = self.parse_unary();
                left = BinOpNode(kind="bin_op", left=left, op="*", right=right);
            } elif self.match("SLASH") is not None {
                right = self.parse_unary();
                left = BinOpNode(kind="bin_op", left=left, op="/", right=right);
            } elif self.match("DSLASH") is not None {
                right = self.parse_unary();
                left = BinOpNode(kind="bin_op", left=left, op="//", right=right);
            } elif self.match("PERCENT") is not None {
                right = self.parse_unary();
                left = BinOpNode(kind="bin_op", left=left, op="%", right=right);
            } else {
                break;
            }
        }
        return left;
    }

    def parse_unary() -> AstNode {
        if self.match("MINUS") is not None {
            operand = self.parse_unary();
            return UnaryOpNode(kind="unary_op", op="-", operand=operand);
        }
        if self.match("PLUS") is not None {
            return self.parse_unary();
        }
        if self.match("TILDE") is not None {
            operand = self.parse_unary();
            return UnaryOpNode(kind="unary_op", op="~", operand=operand);
        }
        return self.parse_postfix();
    }

    # -------------------------------------------------------------------------
    # Postfix and Atom
    # -------------------------------------------------------------------------

    def parse_postfix() -> AstNode {
        expr = self.parse_atom();
        while True {
            if self.match("DOT") is not None {
                attr = self.expect("NAME").value;
                expr = AttrNode(kind="attr", value=expr, attr=attr);
            } elif self.match("LBRACKET") is not None {
                index = self.parse_slice_or_index();
                self.expect("RBRACKET");
                expr = SubscriptNode(kind="subscript", value=expr, index=index);
            } elif self.match("LPAREN") is not None {
                expr = self.parse_call_args(expr);
            } else {
                break;
            }
        }
        return expr;
    }

    def parse_slice_or_index() -> AstNode {
        if self.check("COLON") {
            return self.parse_slice(None);
        }
        first = self.parse_expr();
        if self.check("COLON") {
            return self.parse_slice(first);
        }
        return first;
    }

    def parse_slice(lower: AstNode | None) -> AstNode {
        self.expect("COLON");
        upper: AstNode | None = None;
        if not self.check("RBRACKET") and not self.check("COLON") {
            upper = self.parse_expr();
        }
        step: AstNode | None = None;
        if self.match("COLON") is not None {
            if not self.check("RBRACKET") {
                step = self.parse_expr();
            }
        }
        return SliceNode(kind="slice", lower=lower, upper=upper, step=step);
    }

    def parse_call_args(func: AstNode) -> CallNode {
        args: list[AstNode] = [];
        kwargs: list[AstNode] = [];
        while not self.check("RPAREN") and not self.at_end() {
            # **kwargs
            if self.match("DSTAR") is not None {
                val = self.parse_expr();
                kwargs.append(KeywordArg(kind="kwarg", name=None, value=DblStarExpr(kind="dblstar", value=val)));
                if self.match("COMMA") is None {
                    break;
                }
                continue;
            }
            # *args
            if self.match("STAR") is not None {
                val = self.parse_expr();
                args.append(StarExpr(kind="star", value=val));
                if self.match("COMMA") is None {
                    break;
                }
                continue;
            }
            # Check for keyword argument: name=expr
            if self.check("NAME") and self.peek_kind(1) == "EQ" {
                kw_name = self.advance().value;
                self.advance();
                kw_val = self.parse_expr();
                kwargs.append(KeywordArg(kind="kwarg", name=kw_name, value=kw_val));
            } else {
                args.append(self.parse_expr());
            }
            if self.match("COMMA") is None {
                break;
            }
        }
        self.expect("RPAREN");
        return CallNode(kind="call", func=func, args=args, kwargs=kwargs);
    }

    def parse_atom() -> AstNode {
        tok = self.current();

        if tok.kind == "INT" {
            self.advance();
            return ConstNode(kind="const", value=tok.value, const_type="int",
                              line=tok.line, col=tok.col);
        }
        if tok.kind == "FLOAT" {
            self.advance();
            return ConstNode(kind="const", value=tok.value, const_type="float",
                              line=tok.line, col=tok.col);
        }
        if tok.kind == "STRING" {
            self.advance();
            return ConstNode(kind="const", value=tok.value, const_type="str",
                              line=tok.line, col=tok.col);
        }
        if tok.kind == "FSTRING" {
            self.advance();
            return self.parse_fstring_parts(tok);
        }
        if tok.kind == "KW_TRUE" {
            self.advance();
            return ConstNode(kind="const", value="True", const_type="bool",
                              line=tok.line, col=tok.col);
        }
        if tok.kind == "KW_FALSE" {
            self.advance();
            return ConstNode(kind="const", value="False", const_type="bool",
                              line=tok.line, col=tok.col);
        }
        if tok.kind == "KW_NONE" {
            self.advance();
            return ConstNode(kind="const", value="None", const_type="none",
                              line=tok.line, col=tok.col);
        }
        if tok.kind == "KW_SELF" {
            self.advance();
            return NameNode(kind="name", name="self", line=tok.line, col=tok.col);
        }
        if tok.kind == "NAME" {
            self.advance();
            return NameNode(kind="name", name=tok.value, line=tok.line, col=tok.col);
        }
        if tok.kind == "KW_LAMBDA" {
            return self.parse_lambda();
        }

        # Parenthesized expression or tuple
        if tok.kind == "LPAREN" {
            self.advance();
            if self.check("RPAREN") {
                self.advance();
                return TupleNode(kind="tuple", elts=[], line=tok.line, col=tok.col);
            }
            first = self.parse_expr();
            if self.match("COMMA") is not None {
                elts: list[AstNode] = [];
                elts.append(first);
                while not self.check("RPAREN") and not self.at_end() {
                    elts.append(self.parse_expr());
                    if self.match("COMMA") is None {
                        break;
                    }
                }
                self.expect("RPAREN");
                return TupleNode(kind="tuple", elts=elts, line=tok.line, col=tok.col);
            }
            self.expect("RPAREN");
            return first;
        }

        # List literal or list comprehension
        if tok.kind == "LBRACKET" {
            return self.parse_list_or_comp();
        }

        # Dict/set literal or comprehension
        if tok.kind == "LBRACE" {
            return self.parse_dict_or_set();
        }

        # Star expression
        if tok.kind == "STAR" {
            self.advance();
            val = self.parse_unary();
            return StarExpr(kind="star", value=val, line=tok.line, col=tok.col);
        }

        self.error(f"Unexpected token: {tok.kind} {tok.value}");
        return AstNode(kind="error");
    }

    # -------------------------------------------------------------------------
    # List / Comprehension Parsing
    # -------------------------------------------------------------------------

    def parse_list_or_comp() -> AstNode {
        tok = self.expect("LBRACKET");
        if self.check("RBRACKET") {
            self.advance();
            return ListNode(kind="list", elts=[], line=tok.line, col=tok.col);
        }
        first = self.parse_expr();
        # Comprehension: [expr for x in y]
        if self.check("KW_FOR") {
            gens = self.parse_comprehension_generators();
            self.expect("RBRACKET");
            return ListCompNode(kind="list_comp", elt=first, generators=gens,
                                 line=tok.line, col=tok.col);
        }
        # Regular list
        elts: list[AstNode] = [];
        elts.append(first);
        while self.match("COMMA") is not None {
            if self.check("RBRACKET") {
                break;
            }
            elts.append(self.parse_expr());
        }
        self.expect("RBRACKET");
        return ListNode(kind="list", elts=elts, line=tok.line, col=tok.col);
    }

    # -------------------------------------------------------------------------
    # Dict / Set / Comprehension Parsing
    # -------------------------------------------------------------------------

    def parse_dict_or_set() -> AstNode {
        tok = self.expect("LBRACE");
        if self.check("RBRACE") {
            self.advance();
            return DictNode(kind="dict", keys=[], values=[], line=tok.line, col=tok.col);
        }
        first = self.parse_expr();
        # Dict: {key: value, ...}
        if self.match("COLON") is not None {
            first_val = self.parse_expr();
            # Dict comprehension
            if self.check("KW_FOR") {
                gens = self.parse_comprehension_generators();
                self.expect("RBRACE");
                return DictCompNode(kind="dict_comp", key=first, value=first_val,
                                     generators=gens, line=tok.line, col=tok.col);
            }
            keys: list[AstNode] = [];
            values: list[AstNode] = [];
            keys.append(first);
            values.append(first_val);
            while self.match("COMMA") is not None {
                if self.check("RBRACE") {
                    break;
                }
                keys.append(self.parse_expr());
                self.expect("COLON");
                values.append(self.parse_expr());
            }
            self.expect("RBRACE");
            return DictNode(kind="dict", keys=keys, values=values,
                             line=tok.line, col=tok.col);
        }
        # Set: {a, b, c}
        elts: list[AstNode] = [];
        elts.append(first);
        while self.match("COMMA") is not None {
            if self.check("RBRACE") {
                break;
            }
            elts.append(self.parse_expr());
        }
        self.expect("RBRACE");
        return SetNode(kind="set", elts=elts, line=tok.line, col=tok.col);
    }

    # -------------------------------------------------------------------------
    # Comprehension Generators
    # -------------------------------------------------------------------------

    def parse_comprehension_generators() -> list[AstNode] {
        gens: list[AstNode] = [];
        while self.match("KW_FOR") is not None {
            target: AstNode | None = None;
            if self.match("LPAREN") is not None {
                telts: list[AstNode] = [];
                while not self.check("RPAREN") and not self.at_end() {
                    t = self.expect("NAME");
                    telts.append(NameNode(kind="name", name=t.value));
                    self.match("COMMA");
                }
                self.expect("RPAREN");
                target = TupleNode(kind="tuple", elts=telts);
            } else {
                t = self.expect("NAME");
                target = NameNode(kind="name", name=t.value);
            }
            self.expect("KW_IN");
            iter_expr = self.parse_or();
            ifs: list[AstNode] = [];
            while self.match("KW_IF") is not None {
                ifs.append(self.parse_or());
            }
            gens.append(ComprehensionGen(
                kind="comp_gen", target=target, iter=iter_expr, ifs=ifs
            ));
        }
        return gens;
    }

    # -------------------------------------------------------------------------
    # Lambda
    # -------------------------------------------------------------------------

    def parse_lambda() -> LambdaNode {
        tok = self.expect("KW_LAMBDA");
        params = self.parse_params();
        self.expect("COLON");
        body = self.parse_expr();
        return LambdaNode(kind="lambda", params=params, body=body,
                           line=tok.line, col=tok.col);
    }

    # -------------------------------------------------------------------------
    # F-String Parsing
    # -------------------------------------------------------------------------

    def parse_fstring_parts(tok: BootstrapToken) -> FStringNode {
        raw = tok.value;
        inner = raw[2:len(raw) - 1];
        parts: list[AstNode] = [];
        i = 0;
        text_chars: list[str] = [];

        while i < len(inner) {
            ch = inner[i];
            if ch == "{" and i + 1 < len(inner) and inner[i + 1] == "{" {
                text_chars.append("{");
                i = i + 2;
            } elif ch == "}" and i + 1 < len(inner) and inner[i + 1] == "}" {
                text_chars.append("}");
                i = i + 2;
            } elif ch == "{" {
                if len(text_chars) > 0 {
                    txt = "";
                    for c in text_chars {
                        txt = txt + c;
                    }
                    parts.append(FStringPart(kind="fstr_part", is_expr=False, text=txt));
                    text_chars = [];
                }
                depth = 1;
                start = i + 1;
                i = i + 1;
                while i < len(inner) and depth > 0 {
                    if inner[i] == "{" {
                        depth = depth + 1;
                    } elif inner[i] == "}" {
                        depth = depth - 1;
                    }
                    i = i + 1;
                }
                expr_str = inner[start:i - 1];
                sub_lex = BootstrapLexer(source=expr_str, filename=tok.value);
                sub_tokens = sub_lex.tokenize();
                sub_parser = BootstrapParser(tokens=sub_tokens, pos=0, filename=tok.value);
                expr_node = sub_parser.parse_expr();
                parts.append(FStringPart(kind="fstr_part", is_expr=True, expr=expr_node));
            } else {
                text_chars.append(ch);
                i = i + 1;
            }
        }
        if len(text_chars) > 0 {
            txt = "";
            for c in text_chars {
                txt = txt + c;
            }
            parts.append(FStringPart(kind="fstr_part", is_expr=False, text=txt));
        }
        return FStringNode(kind="fstring", parts=parts, line=tok.line, col=tok.col);
    }

    # -------------------------------------------------------------------------
    # Type Expression Parsing
    # -------------------------------------------------------------------------

    def parse_type_expr() -> AstNode {
        left = self.parse_type_atom();
        if self.match("PIPE") is not None {
            types: list[AstNode] = [];
            types.append(left);
            types.append(self.parse_type_atom());
            while self.match("PIPE") is not None {
                types.append(self.parse_type_atom());
            }
            return UnionTypeNode(kind="union_type", types=types);
        }
        return left;
    }

    def parse_type_atom() -> AstNode {
        tok = self.current();
        if tok.kind == "KW_NONE" {
            self.advance();
            return NameNode(kind="name", name="None", line=tok.line, col=tok.col);
        }
        if tok.kind != "NAME" {
            self.error("Expected type name");
            return AstNode(kind="error");
        }
        name = self.parse_dotted_name();
        if self.match("LBRACKET") is not None {
            args: list[AstNode] = [];
            while not self.check("RBRACKET") and not self.at_end() {
                args.append(self.parse_type_expr());
                self.match("COMMA");
            }
            self.expect("RBRACKET");
            return TypeNode(kind="type", name=name, args=args);
        }
        return NameNode(kind="name", name=name, line=tok.line, col=tok.col);
    }

    # -------------------------------------------------------------------------
    # Helpers
    # -------------------------------------------------------------------------

    def expect_name_or_keyword() -> BootstrapToken {
        # Accept NAME or any keyword token as an identifier.
        # Needed for import paths like "import from enum { ... }"
        # where "enum" is a keyword but also a valid Python module name.
        tok = self.current();
        if tok.kind == "NAME" or tok.kind.startswith("KW_") {
            self.pos = self.pos + 1;
            return tok;
        }
        self.error(f"Expected NAME or keyword, got {tok.kind} ({tok.value})");
        return tok;
    }

    def parse_dotted_name() -> str {
        parts: list[str] = [];
        parts.append(self.expect_name_or_keyword().value);
        while self.check("DOT") {
            next_kind = self.peek_kind(1);
            if next_kind != "NAME" and not next_kind.startswith("KW_") {
                break;
            }
            self.advance();
            parts.append(self.expect_name_or_keyword().value);
        }
        result = "";
        i = 0;
        while i < len(parts) {
            if i > 0 {
                result = result + ".";
            }
            result = result + parts[i];
            i = i + 1;
        }
        return result;
    }
}
