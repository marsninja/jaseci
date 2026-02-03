"""AST construction helpers for the handwritten Jac parser.

Provides:
- KidCollector: Context-like helper for accumulating child nodes in source order.
- Utility functions for building AST nodes with correct kid lists.
"""

import from jaclang.pycore.unitree {
    UniNode,
    Token as UniToken,
    Name as UniName,
    Source as UniSource,
    EmptyToken as UniEmptyToken,
    SpecialVarRef as UniSpecialVarRef
}

import from jaclang.pycore.constant { Tokens as Tok }

import from jaclang.compiler.rd_parser.lexer {
    SPECIAL_REF_TOKENS,
    KEYWORD_MAP,
    BUILTIN_TYPE_MAP,
    EOF_NAME
}

# ── KidCollector ─────────────────────────────────────────────────────────────
obj KidCollector {
    """Collects all tokens and nodes consumed during a grammar production.

    Usage:
        collector = KidCollector();
        collector.start(parser);
        # ... parse sub-productions, each call to parser.advance() or
        # adding a sub-node goes through the collector ...
        nd = SomeASTNode(..., kid=collector.kids);
        collector.stop();
    """
    has kids: list = [],
        parser: any = None,
        prev_collector: any = None;

    def init {
        self.kids = [];
        self.parser = None;
        self.prev_collector = None;
    }

    def start(parser: any) {
        # Begin collecting kids. Saves the parser's current collector.
        self.parser = parser;
        self.prev_collector = parser.current_collector;
        parser.current_collector = self;
    }

    def stop {
        # Stop collecting kids. Restores the parser's previous collector.
        if self.parser is not None {
            self.parser.current_collector = self.prev_collector;
        }
    }

    def add(node: any) {
        # Add a node or token to the kid list.
        if node is not None {
            self.kids.append(nd);
        }
    }

    def add_many(nodes: list) {
        # Add multiple nodes to the kid list.
        for node in nodes {
            if node is not None {
                self.kids.append(nd);
            }
        }
    }
}

# ── Helper Functions ─────────────────────────────────────────────────────────
def is_eof_token(
    tok: UniToken
) -> bool {
    # Check if a token is the EOF sentinel.
    return tok.name == EOF_NAME;
}

# Build the set of token names accepted as identifiers in named_ref context.
# Includes NAME, KWESC_NAME, all KW_* keyword tokens (which are alphabetic words),
# but excludes BOOL (True/False) and NULL (None) since those are literals.
# This mirrors Lark's contextual lexer which resolves keyword-vs-name ambiguity
# based on parser state — since parse_named_ref is only called when a name is
# explicitly expected, any keyword token (e.g. KW_HAS for 'has') should be accepted.
def _build_name_token_set -> set {
    s: set = {Tok.NAME.value,Tok.KWESC_NAME.value};
    # Add all keyword-mapped token names (except literals)
    for (word, tok_enum) in KEYWORD_MAP.items() {
        tok_name = tok_enum.value;
        if tok_name not in [Tok.BOOL.value, Tok.NULL.value] {
            s.add(tok_name);
        }
    }
    # Add all builtin type token names (set, list, dict, int, etc.)
    for (word, tok_enum) in BUILTIN_TYPE_MAP.items() {
        s.add(tok_enum.value);
    }
    return s;
}

glob _NAME_TOKEN_SET: set = _build_name_token_set();

def is_name_token(tok: UniToken) -> bool {
    # Check if a token can serve as a Name in named_ref position.
    return tok.name in _NAME_TOKEN_SET;
}

def is_special_ref_token(tok: UniToken) -> bool {
    # Check if a token is a special variable reference.
    return tok.name in SPECIAL_REF_TOKENS;
}

def wrap_special_ref(name_tok: UniName) -> UniSpecialVarRef {
    # Wrap a Name token as a SpecialVarRef if it's a special reference keyword.
    return UniSpecialVarRef(var=name_tok);
}

def make_empty_token(orig_src: UniSource) -> UniEmptyToken {
    # Create an empty token for error recovery.
    return UniEmptyToken(orig_src=orig_src);
}

# ── Token Type Check Helpers ─────────────────────────────────────────────────
glob AUGMENTED_ASSIGN_OPS:
         set = {Tok.ADD_EQ.value,Tok.SUB_EQ.value,Tok.MUL_EQ.value,Tok.STAR_POW_EQ.value,Tok.FLOOR_DIV_EQ.value,Tok.DIV_EQ.value,Tok.MOD_EQ.value,Tok.BW_AND_EQ.value,Tok.BW_OR_EQ.value,Tok.BW_XOR_EQ.value,Tok.LSHIFT_EQ.value,Tok.RSHIFT_EQ.value,Tok.MATMUL_EQ.value},
     COMPARISON_OPS: set = {Tok.EE.value,Tok.NE.value,Tok.LT.value,Tok.GT.value,Tok.LTE.value,Tok.GTE.value,Tok.KW_IS.value,Tok.KW_ISN.value,Tok.KW_IN.value,Tok.KW_NIN.value},
     ARCH_TYPE_TOKENS: set = {Tok.KW_OBJECT.value,Tok.KW_CLASS.value,Tok.KW_NODE.value,Tok.KW_EDGE.value,Tok.KW_WALKER.value},
     UNARY_PREFIX_OPS: set = {Tok.MINUS.value,Tok.PLUS.value,Tok.BW_NOT.value},
     STATEMENT_START_TOKENS: set = {Tok.KW_IF.value,Tok.KW_WHILE.value,Tok.KW_FOR.value,Tok.KW_TRY.value,Tok.KW_WITH.value,Tok.KW_MATCH.value,Tok.KW_SWITCH.value,Tok.KW_RETURN.value,Tok.KW_YIELD.value,Tok.KW_RAISE.value,Tok.KW_ASSERT.value,Tok.KW_DELETE.value,Tok.KW_REPORT.value,Tok.KW_BREAK.value,Tok.KW_CONTINUE.value,Tok.KW_SKIP.value,Tok.KW_VISIT.value,Tok.KW_DISENGAGE.value,Tok.GLOBAL_OP.value,Tok.NONLOCAL_OP.value,Tok.KW_IMPORT.value,Tok.KW_INCLUDE.value,Tok.KW_HAS.value,Tok.KW_ASYNC.value,Tok.SEMI.value,Tok.RETURN_HINT.value},
     TOPLEVEL_SYNC_TOKENS: set = {Tok.KW_IMPORT.value,Tok.KW_INCLUDE.value,Tok.KW_OBJECT.value,Tok.KW_CLASS.value,Tok.KW_NODE.value,Tok.KW_EDGE.value,Tok.KW_WALKER.value,Tok.KW_ENUM.value,Tok.KW_DEF.value,Tok.KW_CAN.value,Tok.KW_IMPL.value,Tok.KW_SEM.value,Tok.KW_TEST.value,Tok.KW_GLOBAL.value,Tok.KW_CLIENT.value,Tok.KW_SERVER.value,Tok.KW_NATIVE.value,Tok.DECOR_OP.value,Tok.KW_WITH.value,Tok.KW_ASYNC.value},
     STMT_SYNC_TOKENS: set = {Tok.RBRACE.value,Tok.SEMI.value,Tok.KW_IF.value,Tok.KW_FOR.value,Tok.KW_WHILE.value,Tok.KW_TRY.value,Tok.KW_WITH.value,Tok.KW_RETURN.value,Tok.KW_RAISE.value,Tok.KW_IMPORT.value},
     EXPR_SYNC_TOKENS: set = {Tok.SEMI.value,Tok.RPAREN.value,Tok.RBRACE.value,Tok.RSQUARE.value,Tok.COMMA.value,Tok.COLON.value},
     AUTO_INSERT_TOKENS: set = {Tok.SEMI.value,Tok.COMMA.value,Tok.COLON.value,Tok.RPAREN.value,Tok.RBRACE.value,Tok.RSQUARE.value,Tok.RETURN_HINT.value},
     EDGE_OP_TOKENS: set = {Tok.ARROW_R.value,Tok.ARROW_L.value,Tok.ARROW_BI.value,Tok.ARROW_R_P1.value,Tok.ARROW_L_P1.value,Tok.ARROW_R_P2.value,Tok.ARROW_L_P2.value},
     CONNECT_OP_TOKENS: set = {Tok.CARROW_R.value,Tok.CARROW_L.value,Tok.CARROW_BI.value,Tok.CARROW_R_P1.value,Tok.CARROW_L_P1.value,Tok.CARROW_R_P2.value,Tok.CARROW_L_P2.value},
     ALL_EDGE_CONNECT_TOKENS: set = EDGE_OP_TOKENS | CONNECT_OP_TOKENS,
     EDGE_CONNECT_START_TOKENS: set = {Tok.ARROW_R.value,Tok.ARROW_L.value,Tok.ARROW_BI.value,Tok.ARROW_R_P1.value,Tok.ARROW_L_P1.value,Tok.CARROW_R.value,Tok.CARROW_L.value,Tok.CARROW_BI.value,Tok.CARROW_R_P1.value,Tok.CARROW_L_P1.value},
     CONNECT_OP_START_TOKENS: set = {Tok.CARROW_R.value,Tok.CARROW_L.value,Tok.CARROW_BI.value,Tok.CARROW_R_P1.value,Tok.CARROW_L_P1.value};
# Tokens that can START an edge or connect operator (excludes P2 closing tokens)

# Tokens that can START a connect operator only (excludes edge ops and P2 closing tokens)
