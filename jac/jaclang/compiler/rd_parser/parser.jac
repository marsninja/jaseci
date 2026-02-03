# Handwritten recursive descent parser core for the Jac language.
#
# Provides JacRDParserCore with token primitives, error recovery,
# and module/top-level parsing. Delegates to parser_exprs.jac and
# parser_stmts.jac for expression and statement parsing.
import os;

import from jaclang.pycore.unitree {
    UniNode,
    Token as UniToken,
    Name as UniName,
    String as UniString,
    Source as UniSource,
    Module as UniModule,
    EmptyToken as UniEmptyToken,
    SpecialVarRef as UniSpecialVarRef,
    Expr,
    ElementStmt,
    CodeBlockStmt,
    ContextAwareNode,
    ModuleCode as UniModuleCode,
    ClientBlock as UniClientBlock,
    ServerBlock as UniServerBlock,
    NativeBlock as UniNativeBlock,
    GlobalVars as UniGlobalVars,
    Test as UniTest,
    PyInlineCode as UniPyInlineCode,
    Import as UniImport,
    SubTag,
    Archetype as UniArchetype,
    Ability as UniAbility,
    ImplDef as UniImplDef,
    SemDef as UniSemDef
}

import from jaclang.pycore.constant { Tokens as Tok, CodeContext }

import from jaclang.compiler.rd_parser.lexer {
    JacLexer,
    EOF_NAME,
    KEYWORD_MAP,
    BUILTIN_TYPE_MAP,
    SPECIAL_REF_TOKENS
}

import from jaclang.compiler.rd_parser.ast_builder {
    KidCollector,
    is_eof_token,
    is_name_token,
    is_special_ref_token,
    wrap_special_ref,
    make_empty_token,
    AUGMENTED_ASSIGN_OPS,
    COMPARISON_OPS,
    ARCH_TYPE_TOKENS,
    UNARY_PREFIX_OPS,
    STATEMENT_START_TOKENS,
    TOPLEVEL_SYNC_TOKENS,
    STMT_SYNC_TOKENS,
    EXPR_SYNC_TOKENS,
    AUTO_INSERT_TOKENS
}

import from jaclang.compiler.rd_parser.parser_exprs {
    parse_expression as _expr_impl,
    parse_atomic_chain as _atomic_chain_impl,
    parse_pipe as _pipe_impl
}

import from jaclang.compiler.rd_parser.parser_stmts {
    parse_statement as _stmt_impl,
    parse_code_block as _code_block_impl,
    parse_code_block_with_kids as _code_block_kids_impl,
    parse_else_stmt as _else_stmt_impl
}

import from jaclang.compiler.rd_parser.parser_defs {
    parse_import_stmt as _import_stmt_impl,
    parse_archetype as _archetype_impl,
    parse_enum_def as _enum_impl,
    parse_ability as _ability_impl,
    parse_global_var as _global_var_impl,
    parse_impl_def as _impl_def_impl,
    parse_sem_def as _sem_def_impl,
    parse_has_stmt as _has_stmt_impl,
    parse_func_signature as _func_sig_impl,
    parse_event_clause as _event_clause_impl,
    parse_access_tag as _access_tag_impl,
    parse_type_tag as _type_tag_impl
}

import from jaclang.compiler.rd_parser.parser_edges {
    parse_edge_ref_chain as _edge_ref_chain_impl,
    parse_connect_op as _connect_op_impl,
    parse_disconnect_op as _disconnect_op_impl,
    parse_filter_compare_list as _filter_compare_list_impl
}

import from jaclang.compiler.rd_parser.parser_patterns {
    parse_match_stmt as _match_stmt_impl,
    parse_switch_stmt as _switch_stmt_impl
}

import from jaclang.compiler.rd_parser.parser_fstring { parse_fstring as _fstring_impl }

import from jaclang.compiler.rd_parser.parser_jsx {
    parse_jsx_element as _jsx_element_impl
}

# ── Parser Core ──────────────────────────────────────────────────────────────
obj JacRDParserCore {
    # Recursive descent parser for Jac.
    # Produces uni.Module ASTs compatible with the existing compilation pipeline.
    has source: str,
        orig_src: UniSource,
        mod_path: str,
        lexer: JacLexer,
        node_list: list = [],
        node_ids: set = set(),
        errors_had: list = [],
        warnings_had: list = [],
        current_collector: KidCollector | None = None;

    def init(source: str, orig_src: UniSource, mod_path: str) {
        self.source = source;
        self.orig_src = orig_src;
        self.mod_path = mod_path;
        self.lexer = JacLexer(source=source, orig_src=orig_src);
        self.node_list = [];
        self.node_ids = set();
        self.errors_had = [];
        self.warnings_had = [];
        self.current_collector = None;
    }

    # ── Node registration ────────────────────────────────────────────────
    def register_node(nd: UniNode) -> UniNode {
        # Register an AST node in the node list.
        node_id = id(nd);
        if node_id not in self.node_ids {
            self.node_ids.add(node_id);
            self.node_list.append(nd);
        }
        return nd;
    }

    # ── Error logging ────────────────────────────────────────────────────
    def log_error(msg: str, tok: UniToken | None = None) {
        self.errors_had.append({"msg": msg, "token": tok});
    }

    def log_warning(msg: str, tok: UniToken | None = None) {
        self.warnings_had.append({"msg": msg, "token": tok});
    }

    # ── Token consumption primitives ─────────────────────────────────────
    def peek(offset: int = 0) -> UniToken {
        # Look at the next token without consuming it.
        return self.lexer.peek(offset);
    }

    def advance -> UniToken {
        # Consume and return the next token.
        tok = self.lexer.next_token();
        self.register_node(tok);
        return tok;
    }

    def expect(tok_type: str) -> UniToken {
        # Consume a token of the expected type. On mismatch, try error recovery.
        peeked = self.peek();
        if peeked.name == tok_type {
            return self.advance();
        }
        # Auto-insert missing tokens
        if tok_type in AUTO_INSERT_TOKENS {
            self.log_error(f"Expected '{tok_type}', inserting missing token", peeked);
            return self._synthesize_token(tok_type);
        }
        # Unexpected token
        self.log_error(
            f"Expected '{tok_type}', got '{peeked.name}' ('{peeked.value}')", peeked
        );
        return self._synthesize_token(tok_type);
    }

    def match_tok(tok_type: str) -> UniToken | None {
        # If next token matches, consume and return it. Otherwise return None.
        if self.peek().name == tok_type {
            return self.advance();
        }
        return None;
    }

    def match_any(*tok_types: str) -> UniToken | None {
        # If next token matches any of the types, consume and return it.
        peeked_name = self.peek().name;
        for tt in tok_types {
            if peeked_name == tt {
                return self.advance();
            }
        }
        return None;
    }

    def check(tok_type: str) -> bool {
        return self.peek().name == tok_type;
    }

    def check_any(*tok_types: str) -> bool {
        peeked_name = self.peek().name;
        for tt in tok_types {
            if peeked_name == tt {
                return True;
            }
        }
        return False;
    }

    def at_end -> bool {
        return is_eof_token(self.peek());
    }

    # ── Error recovery helpers ───────────────────────────────────────────
    def _synthesize_token(tok_type: str) -> UniToken {
        tok = UniToken(
            orig_src=self.orig_src,
            name=tok_type,
            value="",
            line=self.lexer.line,
            end_line=self.lexer.line,
            col_start=self.lexer.col,
            col_end=self.lexer.col,
            pos_start=self.lexer.pos,
            pos_end=self.lexer.pos
        );
        self.register_node(tok);
        return tok;
    }

    def synchronize(sync_tokens: set) {
        while not self.at_end() {
            if self.peek().name in sync_tokens {
                return;
            }
            self.advance();
        }
    }

    # ── Named reference parsing ──────────────────────────────────────────
    def parse_named_ref -> UniName {
        tok = self.peek();
        if is_name_token(tok) {
            name_tok = self.advance();
            if is_special_ref_token(name_tok) {
                ref = wrap_special_ref(name_tok);
                self.register_node(ref);
                return ref;
            }
            # If the token is a keyword being used as an identifier (e.g. 'has'
            # tokenized as KW_HAS), convert it from UniToken to UniName so
            # downstream AST nodes (like Ability) that require Name nodes work.
            if not isinstance(name_tok, UniName) {
                name_nd = UniName(
                    orig_src=self.orig_src,
                    name=Tok.NAME.value,
                    value=name_tok.value,
                    line=name_tok.loc.first_line,
                    end_line=name_tok.loc.last_line,
                    col_start=name_tok.loc.col_start,
                    col_end=name_tok.loc.col_end,
                    pos_start=name_tok.loc.pos_start,
                    pos_end=name_tok.loc.pos_end
                );
                self.register_node(name_nd);
                return name_nd;
            }
            return name_tok;
        }
        self.log_error(f"Expected identifier, got '{tok.name}'", tok);
        return self._synthesize_name();
    }

    def _synthesize_name -> UniName {
        nd = UniName(
            orig_src=self.orig_src,
            name=Tok.NAME.value,
            value="__missing__",
            line=self.lexer.line,
            end_line=self.lexer.line,
            col_start=self.lexer.col,
            col_end=self.lexer.col,
            pos_start=self.lexer.pos,
            pos_end=self.lexer.pos
        );
        self.register_node(nd);
        return nd;
    }

    # ── Delegated methods (expression/statement parsing) ─────────────────
    def parse_expression -> Expr {
        return _expr_impl(self);
    }

    def parse_atomic_chain -> Expr {
        return _atomic_chain_impl(self);
    }

    def parse_pipe_expr -> Expr {
        return _pipe_impl(self);
    }

    def parse_statement -> any {
        return _stmt_impl(self);
    }

    def parse_code_block -> list {
        return _code_block_impl(self);
    }

    def parse_code_block_with_kids -> tuple {
        return _code_block_kids_impl(self);
    }

    # ── Module-level parsing ─────────────────────────────────────────────
    def parse_module -> UniModule {
        # Parse the entire module.
        doc = None;
        body: list = [];
        kids: list = [];

        # Check for module docstring
        if self.check(Tok.STRING.value) {
            peek_1 = self.peek(1);
            if is_eof_token(peek_1)
            or peek_1.name in TOPLEVEL_SYNC_TOKENS
            or peek_1.name == Tok.STRING.value {
                doc = self.advance();
                kids.append(doc);
            }
        }

        # Parse top-level statements
        while not self.at_end() {
            stmt_doc = None;
            if self.check(Tok.STRING.value) {
                peek_1 = self.peek(1);
                if not is_eof_token(peek_1)
                and (
                    peek_1.name in TOPLEVEL_SYNC_TOKENS
                    or peek_1.name == Tok.DECOR_OP.value
                    or peek_1.name == Tok.KW_ASYNC.value
                ) {
                    stmt_doc = self.advance();
                }
            }

            stmt = self.parse_toplevel_stmt();
            if stmt is not None {
                if stmt_doc is not None and stmt?.doc {
                    stmt.doc = stmt_doc;
                    stmt.add_kids_left([stmt_doc]);
                }
                if isinstance(stmt, list) {
                    for s in stmt {
                        body.append(s);
                        kids.append(s);
                    }
                } else {
                    body.append(stmt);
                    kids.append(stmt);
                }
            } elif stmt_doc is not None {
                body.append(stmt_doc);
                kids.append(stmt_doc);
            } else {
                if not self.at_end() {
                    self.log_error(
                        f"Unexpected token '{self.peek().value}'", self.peek()
                    );
                    self.advance();
                }
            }
        }

        mod_name = self.mod_path.split(os.sep)[-1].removesuffix(".jac");

        if len(kids) == 0 {
            kids = [UniEmptyToken(self.orig_src)];
        }

        mod = UniModule(
            name=mod_name,
            source=self.orig_src,
            doc=doc,
            body=body,
            terminals=self.lexer.terminals,
            kid=kids
        );
        self.register_node(mod);
        return mod;
    }

    def parse_toplevel_stmt -> ElementStmt | list | None {
        context_tok = self.match_any(
            Tok.KW_CLIENT.value, Tok.KW_SERVER.value, Tok.KW_NATIVE.value
        );

        if context_tok is not None {
            if context_tok.name == Tok.KW_CLIENT.value {
                context = CodeContext.CLIENT;
            } elif context_tok.name == Tok.KW_SERVER.value {
                context = CodeContext.SERVER;
            } else {
                context = CodeContext.NATIVE;
            }
            if self.check(Tok.LBRACE.value) {
                return self._parse_context_block(context_tok, context);
            }
            stmt = self.parse_onelang_stmt();
            if stmt is not None and isinstance(stmt, ContextAwareNode) {
                stmt.code_context = context;
                stmt.add_kids_left([context_tok]);
            }
            return stmt;
        }

        if self.check(Tok.PYNLINE.value) {
            return self.parse_py_code_block();
        }

        return self.parse_onelang_stmt();
    }

    def _parse_context_block(context_tok: UniToken, context: str) -> ElementStmt {
        lbrace = self.expect(Tok.LBRACE.value);
        elements: list = [];
        kids: list = [context_tok, lbrace];

        while not self.at_end() and not self.check(Tok.RBRACE.value) {
            elem = self.parse_onelang_stmt();
            if elem is not None {
                if isinstance(elem, ContextAwareNode) {
                    elem.code_context = context;
                }
                elements.append(elem);
                kids.append(elem);
            } else {
                if not self.at_end() and not self.check(Tok.RBRACE.value) {
                    self.advance();
                }
            }
        }

        rbrace = self.expect(Tok.RBRACE.value);
        kids.append(rbrace);

        if context_tok.name == Tok.KW_CLIENT.value {
            result = UniClientBlock(body=elements, kid=kids);
        } elif context_tok.name == Tok.KW_SERVER.value {
            result = UniServerBlock(body=elements, kid=kids);
        } else {
            result = UniNativeBlock(body=elements, kid=kids);
        }
        self.register_node(result);
        return result;
    }

    def parse_onelang_stmt -> ElementStmt | None {
        tok = self.peek();

        if tok.name in [Tok.KW_IMPORT.value, Tok.KW_INCLUDE.value] {
            return self.parse_import_stmt();
        }
        if tok.name == Tok.DECOR_OP.value {
            return self.parse_decorated_def();
        }
        if tok.name == Tok.KW_ASYNC.value {
            peek1 = self.peek(1);
            if peek1.name in ARCH_TYPE_TOKENS {
                return self.parse_archetype();
            }
            return self.parse_ability();
        }
        if tok.name in ARCH_TYPE_TOKENS {
            return self.parse_archetype();
        }
        if tok.name == Tok.KW_ENUM.value {
            return self.parse_enum();
        }
        if tok.name in [
            Tok.KW_DEF.value,
            Tok.KW_CAN.value,
            Tok.KW_OVERRIDE.value,
            Tok.KW_STATIC.value
        ] {
            return self.parse_ability();
        }
        if tok.name == Tok.KW_GLOBAL.value {
            return self.parse_global_var();
        }
        if tok.name == Tok.KW_WITH.value {
            peek1 = self.peek(1);
            if peek1.name == Tok.KW_ENTRY.value {
                return self.parse_free_code();
            }
        }
        if tok.name == Tok.KW_TEST.value {
            return self.parse_test();
        }
        if tok.name == Tok.KW_IMPL.value {
            return self.parse_impl_def();
        }
        if tok.name == Tok.KW_SEM.value {
            return self.parse_sem_def();
        }
        if tok.name == Tok.PYNLINE.value {
            return self.parse_py_code_block();
        }
        return None;
    }

    def parse_decorated_def -> ElementStmt {
        decorators = self.parse_decorators();
        tok = self.peek();
        if tok.name == Tok.KW_ASYNC.value {
            peek1 = self.peek(1);
            if peek1.name in ARCH_TYPE_TOKENS {
                return self.parse_archetype(decorators=decorators);
            }
            return self.parse_ability(decorators=decorators);
        }
        if tok.name in ARCH_TYPE_TOKENS {
            return self.parse_archetype(decorators=decorators);
        }
        if tok.name == Tok.KW_ENUM.value {
            return self.parse_enum(decorators=decorators);
        }
        if tok.name in [
            Tok.KW_DEF.value,
            Tok.KW_CAN.value,
            Tok.KW_OVERRIDE.value,
            Tok.KW_STATIC.value
        ] {
            return self.parse_ability(decorators=decorators);
        }
        self.log_error("Expected declaration after decorator", tok);
        return None;
    }

    def parse_decorators -> list {
        decorators: list = [];
        while self.check(Tok.DECOR_OP.value) {
            self.advance();
            expr = self.parse_atomic_chain();
            decorators.append(expr);
        }
        return decorators;
    }

    # ── Concrete top-level construct parsers ─────────────────────────────
    def parse_py_code_block -> UniPyInlineCode {
        pyinline = self.expect(Tok.PYNLINE.value);
        nd = UniPyInlineCode(code=pyinline, kid=[pyinline]);
        self.register_node(nd);
        return nd;
    }

    def parse_test -> UniTest {
        test_tok = self.expect(Tok.KW_TEST.value);
        name = None;
        if is_name_token(self.peek()) {
            name = self.advance();
        }
        if name is None {
            name = test_tok;
        }
        block = self.parse_code_block_with_kids();
        body = block[0];
        kids: list = [test_tok];
        if name is not test_tok {
            kids.append(name);
        }
        kids.extend(block[1]);
        nd = UniTest(
            name=name,
            body=[
                s
                for s in body
                if isinstance(s, CodeBlockStmt)
            ],
            kid=kids
        );
        self.register_node(nd);
        return nd;
    }

    def parse_free_code -> UniModuleCode {
        with_tok = self.expect(Tok.KW_WITH.value);
        entry_tok = self.expect(Tok.KW_ENTRY.value);
        kids: list = [with_tok, entry_tok];

        name = None;
        if self.check(Tok.COLON.value) {
            colon = self.advance();
            kids.append(colon);
            name = self.parse_named_ref();
            kids.append(name);
        }

        block = self.parse_code_block_with_kids();
        body = block[0];
        kids.extend(block[1]);

        nd = UniModuleCode(
            name=name,
            body=[
                s
                for s in body
                if isinstance(s, CodeBlockStmt)
            ],
            kid=kids
        );
        self.register_node(nd);
        return nd;
    }

    # ── Delegation methods to parser_defs.jac ────────────────────────────
    def parse_import_stmt -> UniImport {
        return _import_stmt_impl(self);
    }

    def parse_archetype(decorators: list = []) -> UniArchetype {
        return _archetype_impl(self, decorators=decorators);
    }

    def parse_enum(decorators: list = []) -> any {
        return _enum_impl(self, decorators=decorators);
    }

    def parse_ability(decorators: list = []) -> UniAbility {
        return _ability_impl(self, decorators=decorators);
    }

    def parse_global_var -> UniGlobalVars {
        return _global_var_impl(self);
    }

    def parse_impl_def -> UniImplDef {
        return _impl_def_impl(self);
    }

    def parse_sem_def -> UniSemDef {
        return _sem_def_impl(self);
    }

    def parse_has_stmt -> any {
        return _has_stmt_impl(self);
    }

    def parse_func_signature -> any {
        return _func_sig_impl(self);
    }

    def parse_fstring -> any {
        return _fstring_impl(self);
    }

    def parse_jsx_element -> any {
        return _jsx_element_impl(self);
    }

    def parse_edge_ref_chain -> any {
        return _edge_ref_chain_impl(self);
    }

    def parse_disconnect_op -> any {
        return _disconnect_op_impl(self);
    }

    def parse_connect_op -> any {
        return _connect_op_impl(self);
    }

    def parse_filter_compare_list -> list {
        return _filter_compare_list_impl(self);
    }

    def parse_match_stmt -> any {
        return _match_stmt_impl(self);
    }

    def parse_switch_stmt -> any {
        return _switch_stmt_impl(self);
    }
}
