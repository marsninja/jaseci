"""Constants across the project.""";

import from enum { Enum, IntEnum, IntFlag, StrEnum }


# =============================================================================
# Symbol Types
# =============================================================================


enum SymbolType {
    MODULE = "module",
    MOD_VAR = "mod_var",
    VAR = "variable",
    IMM_VAR = "immutable",
    ABILITY = "ability",
    OBJECT_ARCH = "object",
    NODE_ARCH = "node",
    EDGE_ARCH = "edge",
    WALKER_ARCH = "walker",
    ENUM_ARCH = "enum",
    TEST = "test",
    TYPE = "type",
    IMPL = "impl",
    SEM = "sem",
    HAS_VAR = "field",
    METHOD = "method",
    CONSTRUCTOR = "constructor",
    ENUM_MEMBER = "enum_member",
    NUMBER = "number",
    STRING = "string",
    BOOL = "bool",
    SEQUENCE = "sequence",
    NULL = "null",
    UNKNOWN = "unknown"
}

impl SymbolType {
    def __str__() -> str {
        return self.value;
    }
}


# =============================================================================
# LSP Semantic Token Types
# =============================================================================


enum JacSemTokenType(IntEnum) {
    NAMESPACE = 0,
    TYPE = 1,
    CLASS = 2,
    ENUM = 3,
    INTERFACE = 4,
    STRUCT = 5,
    TYPE_PARAMETER = 6,
    PARAMETER = 7,
    VARIABLE = 8,
    PROPERTY = 9,
    ENUM_MEMBER = 10,
    EVENT = 11,
    FUNCTION = 12,
    METHOD = 13,
    MACRO = 14,
    KEYWORD = 15,
    MODIFIER = 16,
    COMMENT = 17,
    STRING = 18,
    NUMBER = 19,
    REGEXP = 20,
    OPERATOR = 21
}

impl JacSemTokenType {
    @staticmethod
    def as_str_list() -> list[str] {
        return [i.name.lower() for i in JacSemTokenType];
    }
}


# =============================================================================
# LSP Semantic Token Modifiers
# =============================================================================


enum JacSemTokenModifier(IntFlag) {
    DECLARATION = 1,
    DEFINITION = 2,
    READONLY = 4,
    STATIC = 8,
    DEPRECATED = 16,
    ABSTRACT = 32,
    ASYNC = 64,
    MODIFICATION = 128,
    DOCUMENTATION = 256,
    DEFAULT_LIBRARY = 512
}

impl JacSemTokenModifier {
    @staticmethod
    def as_str_list() -> list[str] {
        return [i.name.lower() for i in JacSemTokenModifier if i.name];
    }
}


# =============================================================================
# Token Constants
# =============================================================================


enum Constants(StrEnum) {
    HERE = "here",
    ROOT = "root",
    VISITOR = "visitor",
    JAC_CHECK = "_check",
    SUPER_ROOT_UUID = "00000000-0000-0000-0000-000000000000"
}

impl Constants {
    def __str__() -> str {
        return self.value;
    }
}


# =============================================================================
# Code Context
# =============================================================================


enum CodeContext {
    SERVER = "server",
    CLIENT = "client",
    NATIVE = "native"
}

impl CodeContext {
    def __str__() -> str {
        return self.value;
    }

    @property
    def is_server() -> bool {
        return self == CodeContext.SERVER;
    }

    @property
    def is_client() -> bool {
        return self == CodeContext.CLIENT;
    }

    @property
    def is_native() -> bool {
        return self == CodeContext.NATIVE;
    }
}


# =============================================================================
# Edge Direction
# =============================================================================


enum EdgeDir {
    IN = 1,
    OUT = 2,
    ANY = 3
}


# =============================================================================
# Symbol Access
# =============================================================================


enum SymbolAccess {
    PRIVATE = "private",
    PUBLIC = "public",
    PROTECTED = "protected"
}

impl SymbolAccess {
    def __str__() -> str {
        return self.value;
    }
}


# =============================================================================
# Jac Lexer Tokens
# =============================================================================


enum Tokens(str, Enum) {
    FLOAT = "FLOAT",
    STRING = "STRING",
    PYNLINE = "PYNLINE",
    BOOL = "BOOL",
    INT = "INT",
    HEX = "HEX",
    BIN = "BIN",
    OCT = "OCT",
    NULL = "NULL",
    NAME = "NAME",
    KWESC_NAME = "KWESC_NAME",
    TYP_STRING = "TYP_STRING",
    TYP_INT = "TYP_INT",
    TYP_FLOAT = "TYP_FLOAT",
    TYP_LIST = "TYP_LIST",
    TYP_TUPLE = "TYP_TUPLE",
    TYP_SET = "TYP_SET",
    TYP_DICT = "TYP_DICT",
    TYP_BOOL = "TYP_BOOL",
    TYP_BYTES = "TYP_BYTES",
    TYP_ANY = "TYP_ANY",
    TYP_TYPE = "TYP_TYPE",
    KW_ABSTRACT = "KW_ABSTRACT",
    KW_OBJECT = "KW_OBJECT",
    KW_CLASS = "KW_CLASS",
    KW_ENUM = "KW_ENUM",
    KW_NODE = "KW_NODE",
    KW_VISIT = "KW_VISIT",
    KW_SPAWN = "KW_SPAWN",
    KW_WITH = "KW_WITH",
    KW_LAMBDA = "KW_LAMBDA",
    KW_ENTRY = "KW_ENTRY",
    KW_EXIT = "KW_EXIT",
    KW_IMPORT = "KW_IMPORT",
    KW_INCLUDE = "KW_INCLUDE",
    KW_FROM = "KW_FROM",
    KW_AS = "KW_AS",
    KW_EDGE = "KW_EDGE",
    KW_WALKER = "KW_WALKER",
    KW_ASYNC = "KW_ASYNC",
    KW_AWAIT = "KW_AWAIT",
    KW_FLOW = "KW_FLOW",
    KW_WAIT = "KW_WAIT",
    KW_TEST = "KW_TEST",
    KW_ASSERT = "KW_ASSERT",
    COLON = "COLON",
    PIPE_FWD = "PIPE_FWD",
    PIPE_BKWD = "PIPE_BKWD",
    DOT_FWD = "DOT_FWD",
    DOT_BKWD = "DOT_BKWD",
    LBRACE = "LBRACE",
    RBRACE = "RBRACE",
    SEMI = "SEMI",
    EQ = "EQ",
    ADD_EQ = "ADD_EQ",
    SUB_EQ = "SUB_EQ",
    MUL_EQ = "MUL_EQ",
    STAR_POW_EQ = "STAR_POW_EQ",
    FLOOR_DIV_EQ = "FLOOR_DIV_EQ",
    DIV_EQ = "DIV_EQ",
    MOD_EQ = "MOD_EQ",
    BW_AND_EQ = "BW_AND_EQ",
    BW_OR_EQ = "BW_OR_EQ",
    BW_XOR_EQ = "BW_XOR_EQ",
    LSHIFT_EQ = "LSHIFT_EQ",
    RSHIFT_EQ = "RSHIFT_EQ",
    WALRUS_EQ = "WALRUS_EQ",
    MATMUL_EQ = "MATMUL_EQ",
    KW_AND = "KW_AND",
    KW_OR = "KW_OR",
    KW_IF = "KW_IF",
    KW_ELIF = "KW_ELIF",
    KW_ELSE = "KW_ELSE",
    KW_FOR = "KW_FOR",
    KW_TO = "KW_TO",
    KW_BY = "KW_BY",
    KW_WHILE = "KW_WHILE",
    KW_CONTINUE = "KW_CONTINUE",
    KW_BREAK = "KW_BREAK",
    KW_DISENGAGE = "KW_DISENGAGE",
    KW_YIELD = "KW_YIELD",
    KW_SKIP = "KW_SKIP",
    KW_REPORT = "KW_REPORT",
    KW_RETURN = "KW_RETURN",
    KW_DELETE = "KW_DELETE",
    KW_TRY = "KW_TRY",
    KW_EXCEPT = "KW_EXCEPT",
    KW_FINALLY = "KW_FINALLY",
    KW_RAISE = "KW_RAISE",
    ELLIPSIS = "ELLIPSIS",
    DOT = "DOT",
    NOT = "NOT",
    EE = "EE",
    LT = "LT",
    GT = "GT",
    LTE = "LTE",
    GTE = "GTE",
    NE = "NE",
    KW_IN = "KW_IN",
    KW_IS = "KW_IS",
    KW_NIN = "KW_NIN",
    KW_ISN = "KW_ISN",
    KW_PRIV = "KW_PRIV",
    KW_PUB = "KW_PUB",
    KW_PROT = "KW_PROT",
    KW_HAS = "KW_HAS",
    KW_GLOBAL = "KW_GLOBAL",
    COMMA = "COMMA",
    KW_CAN = "KW_CAN",
    KW_DEF = "KW_DEF",
    KW_STATIC = "KW_STATIC",
    KW_OVERRIDE = "KW_OVERRIDE",
    KW_MATCH = "KW_MATCH",
    KW_SWITCH = "KW_SWITCH",
    KW_CASE = "KW_CASE",
    KW_DEFAULT = "KW_DEFAULT",
    KW_CLIENT = "KW_CLIENT",
    KW_SERVER = "KW_SERVER",
    KW_NATIVE = "KW_NATIVE",
    PLUS = "PLUS",
    MINUS = "MINUS",
    STAR_MUL = "STAR_MUL",
    FLOOR_DIV = "FLOOR_DIV",
    DIV = "DIV",
    MOD = "MOD",
    BW_AND = "BW_AND",
    BW_OR = "BW_OR",
    BW_XOR = "BW_XOR",
    BW_NOT = "BW_NOT",
    LSHIFT = "LSHIFT",
    RSHIFT = "RSHIFT",
    STAR_POW = "STAR_POW",
    LPAREN = "LPAREN",
    RPAREN = "RPAREN",
    LSQUARE = "LSQUARE",
    RSQUARE = "RSQUARE",
    ARROW_L = "ARROW_L",
    ARROW_R = "ARROW_R",
    ARROW_BI = "ARROW_BI",
    ARROW_L_P1 = "ARROW_L_P1",
    ARROW_L_P2 = "ARROW_L_P2",
    ARROW_R_P1 = "ARROW_R_P1",
    ARROW_R_P2 = "ARROW_R_P2",
    CARROW_L = "CARROW_L",
    CARROW_R = "CARROW_R",
    CARROW_BI = "CARROW_BI",
    CARROW_L_P1 = "CARROW_L_P1",
    CARROW_L_P2 = "CARROW_L_P2",
    CARROW_R_P1 = "CARROW_R_P1",
    CARROW_R_P2 = "CARROW_R_P2",
    GLOBAL_OP = "GLOBAL_OP",
    NONLOCAL_OP = "NONLOCAL_OP",
    KW_HERE = "KW_HERE",
    KW_VISITOR = "KW_VISITOR",
    KW_SELF = "KW_SELF",
    KW_PROPS = "KW_PROPS",
    KW_INIT = "KW_INIT",
    KW_SUPER = "KW_SUPER",
    KW_ROOT = "KW_ROOT",
    KW_POST_INIT = "KW_POST_INIT",
    KW_IMPL = "KW_IMPL",
    KW_SEM = "KW_SEM",
    TYPE_OP = "TYPE_OP",
    A_PIPE_FWD = "A_PIPE_FWD",
    A_PIPE_BKWD = "A_PIPE_BKWD",
    RETURN_HINT = "RETURN_HINT",
    NULL_OK = "NULL_OK",
    DECOR_OP = "DECOR_OP",
    JSX_TEXT = "JSX_TEXT",
    JSX_OPEN_START = "JSX_OPEN_START",
    JSX_SELF_CLOSE = "JSX_SELF_CLOSE",
    JSX_TAG_END = "JSX_TAG_END",
    JSX_CLOSE_START = "JSX_CLOSE_START",
    JSX_FRAG_OPEN = "JSX_FRAG_OPEN",
    JSX_FRAG_CLOSE = "JSX_FRAG_CLOSE",
    JSX_NAME = "JSX_NAME",
    COMMENT = "COMMENT",
    WS = "WS",
    F_DQ_START = "F_DQ_START",
    F_SQ_START = "F_SQ_START",
    F_TDQ_START = "F_TDQ_START",
    F_TSQ_START = "F_TSQ_START",
    RF_DQ_START = "RF_DQ_START",
    RF_SQ_START = "RF_SQ_START",
    RF_TDQ_START = "RF_TDQ_START",
    RF_TSQ_START = "RF_TSQ_START",
    F_DQ_END = "F_DQ_END",
    F_SQ_END = "F_SQ_END",
    F_TDQ_END = "F_TDQ_END",
    F_TSQ_END = "F_TSQ_END",
    F_TEXT_DQ = "F_TEXT_DQ",
    F_TEXT_SQ = "F_TEXT_SQ",
    F_TEXT_TDQ = "F_TEXT_TDQ",
    F_TEXT_TSQ = "F_TEXT_TSQ",
    RF_TEXT_DQ = "RF_TEXT_DQ",
    RF_TEXT_SQ = "RF_TEXT_SQ",
    RF_TEXT_TDQ = "RF_TEXT_TDQ",
    RF_TEXT_TSQ = "RF_TEXT_TSQ",
    D_LBRACE = "D_LBRACE",
    D_RBRACE = "D_RBRACE",
    CONV = "CONV",
    F_FORMAT_TEXT = "F_FORMAT_TEXT"
}

impl Tokens {
    def __str__() -> str {
        return self.value;
    }
}


# =============================================================================
# Delimiter Map
# =============================================================================


glob DELIM_MAP: dict = {
    Tokens.COMMA: ",",
    Tokens.EQ: "=",
    Tokens.DECOR_OP: "@",
    Tokens.WS: "\n",
    Tokens.SEMI: ";",
    Tokens.COLON: ":",
    Tokens.LBRACE: "{",
    Tokens.RBRACE: "}",
    Tokens.LSQUARE: "[",
    Tokens.RSQUARE: "]",
    Tokens.LPAREN: "(",
    Tokens.RPAREN: ")",
    Tokens.RETURN_HINT: "->",
    Tokens.DOT: "."
};


# =============================================================================
# Colors
# =============================================================================


glob colors: list[str] = [
    "#FFE9E9",
    "#F0FFF0",
    "#F5E5FF",
    "#FFFFE0",
    "#D2FEFF",
    "#E8FFD7",
    "#FFDEAD",
    "#FFF0F5",
    "#F5FFFA",
    "#FFC0CB",
    "#7FFFD4",
    "#C0C0C0",
    "#ADD8E6",
    "#FFFAF0",
    "#f4f3f7",
    "#f5efff",
    "#b5d7fd",
    "#ffc0cb",
    "#FFC0CB",
    "#e1d4c0",
    "#FCDFFF",
    "#F0FFFF",
    "#F0F8FF",
    "#F8F8FF",
    "#F0FFFF"
];


# =============================================================================
# TypeScript/JavaScript Parser Constants
# =============================================================================


enum TsTokens(str, Enum) {
    NUMBER = "NUMBER",
    STRING = "STRING",
    TEMPLATE_STRING = "TEMPLATE_STRING",
    TEMPLATE_HEAD = "TEMPLATE_HEAD",
    TEMPLATE_MIDDLE = "TEMPLATE_MIDDLE",
    TEMPLATE_TAIL = "TEMPLATE_TAIL",
    REGEX = "REGEX",
    TRUE = "TRUE",
    FALSE = "FALSE",
    NULL = "NULL",
    UNDEFINED = "UNDEFINED",
    NAME = "NAME",
    PRIVATE_NAME = "PRIVATE_NAME",
    KW_VAR = "KW_VAR",
    KW_CONST = "KW_CONST",
    KW_FUNCTION = "KW_FUNCTION",
    KW_CLASS = "KW_CLASS",
    KW_INTERFACE = "KW_INTERFACE",
    KW_TYPE = "KW_TYPE",
    KW_ENUM = "KW_ENUM",
    KW_NAMESPACE = "KW_NAMESPACE",
    KW_MODULE = "KW_MODULE",
    KW_DECLARE = "KW_DECLARE",
    KW_EXTENDS = "KW_EXTENDS",
    KW_IMPLEMENTS = "KW_IMPLEMENTS",
    KW_STATIC = "KW_STATIC",
    KW_PUBLIC = "KW_PUBLIC",
    KW_PRIVATE = "KW_PRIVATE",
    KW_PROTECTED = "KW_PROTECTED",
    KW_READONLY = "KW_READONLY",
    KW_ABSTRACT = "KW_ABSTRACT",
    KW_OVERRIDE = "KW_OVERRIDE",
    KW_CONSTRUCTOR = "KW_CONSTRUCTOR",
    KW_GET = "KW_GET",
    KW_SET = "KW_SET",
    KW_IF = "KW_IF",
    KW_ELSE = "KW_ELSE",
    KW_SWITCH = "KW_SWITCH",
    KW_CASE = "KW_CASE",
    KW_DEFAULT = "KW_DEFAULT",
    KW_FOR = "KW_FOR",
    KW_WHILE = "KW_WHILE",
    KW_DO = "KW_DO",
    KW_BREAK = "KW_BREAK",
    KW_CONTINUE = "KW_CONTINUE",
    KW_RETURN = "KW_RETURN",
    KW_THROW = "KW_THROW",
    KW_TRY = "KW_TRY",
    KW_CATCH = "KW_CATCH",
    KW_FINALLY = "KW_FINALLY",
    KW_WITH = "KW_WITH",
    KW_DEBUGGER = "KW_DEBUGGER",
    KW_NEW = "KW_NEW",
    KW_DELETE = "KW_DELETE",
    KW_TYPEOF = "KW_TYPEOF",
    KW_VOID = "KW_VOID",
    KW_IN = "KW_IN",
    KW_OF = "KW_OF",
    KW_INSTANCEOF = "KW_INSTANCEOF",
    KW_ASYNC = "KW_ASYNC",
    KW_AWAIT = "KW_AWAIT",
    KW_YIELD = "KW_YIELD",
    KW_IMPORT = "KW_IMPORT",
    KW_EXPORT = "KW_EXPORT",
    KW_FROM = "KW_FROM",
    KW_AS = "KW_AS",
    KW_THIS = "KW_THIS",
    KW_SUPER = "KW_SUPER",
    KW_ANY = "KW_ANY",
    KW_UNKNOWN = "KW_UNKNOWN",
    KW_NEVER = "KW_NEVER",
    KW_STRING_TYPE = "KW_STRING_TYPE",
    KW_NUMBER_TYPE = "KW_NUMBER_TYPE",
    KW_BOOLEAN_TYPE = "KW_BOOLEAN_TYPE",
    KW_SYMBOL_TYPE = "KW_SYMBOL_TYPE",
    KW_BIGINT_TYPE = "KW_BIGINT_TYPE",
    KW_OBJECT_TYPE = "KW_OBJECT_TYPE",
    KW_KEYOF = "KW_KEYOF",
    KW_INFER = "KW_INFER",
    KW_IS = "KW_IS",
    KW_ASSERTS = "KW_ASSERTS",
    KW_SATISFIES = "KW_SATISFIES",
    LBRACE = "LBRACE",
    RBRACE = "RBRACE",
    LPAREN = "LPAREN",
    RPAREN = "RPAREN",
    LSQUARE = "LSQUARE",
    RSQUARE = "RSQUARE",
    SEMI = "SEMI",
    COMMA = "COMMA",
    COLON = "COLON",
    DOT = "DOT",
    ELLIPSIS = "ELLIPSIS",
    QUESTION = "QUESTION",
    OPTIONAL_CHAIN = "OPTIONAL_CHAIN",
    NULLISH_COALESCE = "NULLISH_COALESCE",
    AT = "AT",
    HASH = "HASH",
    BACKTICK = "BACKTICK",
    ARROW = "ARROW",
    EQ = "EQ",
    ADD_EQ = "ADD_EQ",
    SUB_EQ = "SUB_EQ",
    MUL_EQ = "MUL_EQ",
    DIV_EQ = "DIV_EQ",
    MOD_EQ = "MOD_EQ",
    EXP_EQ = "EXP_EQ",
    AND_EQ = "AND_EQ",
    OR_EQ = "OR_EQ",
    XOR_EQ = "XOR_EQ",
    LSHIFT_EQ = "LSHIFT_EQ",
    RSHIFT_EQ = "RSHIFT_EQ",
    URSHIFT_EQ = "URSHIFT_EQ",
    LOGICAL_AND_EQ = "LOGICAL_AND_EQ",
    LOGICAL_OR_EQ = "LOGICAL_OR_EQ",
    NULLISH_EQ = "NULLISH_EQ",
    EE = "EE",
    NE = "NE",
    EEE = "EEE",
    NEE = "NEE",
    LT = "LT",
    GT = "GT",
    LTE = "LTE",
    GTE = "GTE",
    PLUS = "PLUS",
    MINUS = "MINUS",
    STAR = "STAR",
    SLASH = "SLASH",
    PERCENT = "PERCENT",
    STAR_STAR = "STAR_STAR",
    PLUS_PLUS = "PLUS_PLUS",
    MINUS_MINUS = "MINUS_MINUS",
    BW_AND = "BW_AND",
    BW_OR = "BW_OR",
    BW_XOR = "BW_XOR",
    BW_NOT = "BW_NOT",
    LSHIFT = "LSHIFT",
    RSHIFT = "RSHIFT",
    URSHIFT = "URSHIFT",
    NOT = "NOT",
    AND = "AND",
    OR = "OR",
    JSX_OPEN_START = "JSX_OPEN_START",
    JSX_CLOSE_START = "JSX_CLOSE_START",
    JSX_SELF_CLOSE = "JSX_SELF_CLOSE",
    JSX_TAG_END = "JSX_TAG_END",
    JSX_FRAG_OPEN = "JSX_FRAG_OPEN",
    JSX_FRAG_CLOSE = "JSX_FRAG_CLOSE",
    JSX_NAME = "JSX_NAME",
    JSX_TEXT = "JSX_TEXT",
    COMMENT = "COMMENT",
    MULTILINE_COMMENT = "MULTILINE_COMMENT",
    NEWLINE = "NEWLINE",
    WS = "WS"
}


# =============================================================================
# TypeScript Token Values
# =============================================================================


glob TS_TOKEN_VALUES: dict = {
    TsTokens.KW_VAR: "var",
    TsTokens.KW_CONST: "const",
    TsTokens.KW_FUNCTION: "function",
    TsTokens.KW_CLASS: "class",
    TsTokens.KW_INTERFACE: "interface",
    TsTokens.KW_TYPE: "type",
    TsTokens.KW_ENUM: "enum",
    TsTokens.KW_NAMESPACE: "namespace",
    TsTokens.KW_MODULE: "module",
    TsTokens.KW_DECLARE: "declare",
    TsTokens.KW_EXTENDS: "extends",
    TsTokens.KW_IMPLEMENTS: "implements",
    TsTokens.KW_STATIC: "static",
    TsTokens.KW_PUBLIC: "public",
    TsTokens.KW_PRIVATE: "private",
    TsTokens.KW_PROTECTED: "protected",
    TsTokens.KW_READONLY: "readonly",
    TsTokens.KW_ABSTRACT: "abstract",
    TsTokens.KW_OVERRIDE: "override",
    TsTokens.KW_CONSTRUCTOR: "constructor",
    TsTokens.KW_GET: "get",
    TsTokens.KW_SET: "set",
    TsTokens.KW_IF: "if",
    TsTokens.KW_ELSE: "else",
    TsTokens.KW_SWITCH: "switch",
    TsTokens.KW_CASE: "case",
    TsTokens.KW_DEFAULT: "default",
    TsTokens.KW_FOR: "for",
    TsTokens.KW_WHILE: "while",
    TsTokens.KW_DO: "do",
    TsTokens.KW_BREAK: "break",
    TsTokens.KW_CONTINUE: "continue",
    TsTokens.KW_RETURN: "return",
    TsTokens.KW_THROW: "throw",
    TsTokens.KW_TRY: "try",
    TsTokens.KW_CATCH: "catch",
    TsTokens.KW_FINALLY: "finally",
    TsTokens.KW_WITH: "with",
    TsTokens.KW_DEBUGGER: "debugger",
    TsTokens.KW_NEW: "new",
    TsTokens.KW_DELETE: "delete",
    TsTokens.KW_TYPEOF: "typeof",
    TsTokens.KW_VOID: "void",
    TsTokens.KW_IN: "in",
    TsTokens.KW_OF: "of",
    TsTokens.KW_INSTANCEOF: "instanceof",
    TsTokens.KW_ASYNC: "async",
    TsTokens.KW_AWAIT: "await",
    TsTokens.KW_YIELD: "yield",
    TsTokens.KW_IMPORT: "import",
    TsTokens.KW_EXPORT: "export",
    TsTokens.KW_FROM: "from",
    TsTokens.KW_AS: "as",
    TsTokens.KW_THIS: "this",
    TsTokens.KW_SUPER: "super",
    TsTokens.TRUE: "true",
    TsTokens.FALSE: "false",
    TsTokens.NULL: "null",
    TsTokens.UNDEFINED: "undefined",
    TsTokens.KW_ANY: "any",
    TsTokens.KW_UNKNOWN: "unknown",
    TsTokens.KW_NEVER: "never",
    TsTokens.KW_STRING_TYPE: "string",
    TsTokens.KW_NUMBER_TYPE: "number",
    TsTokens.KW_BOOLEAN_TYPE: "boolean",
    TsTokens.KW_SYMBOL_TYPE: "symbol",
    TsTokens.KW_BIGINT_TYPE: "bigint",
    TsTokens.KW_OBJECT_TYPE: "object",
    TsTokens.KW_KEYOF: "keyof",
    TsTokens.KW_INFER: "infer",
    TsTokens.KW_IS: "is",
    TsTokens.KW_ASSERTS: "asserts",
    TsTokens.KW_SATISFIES: "satisfies",
    TsTokens.LBRACE: "{",
    TsTokens.RBRACE: "}",
    TsTokens.LPAREN: "(",
    TsTokens.RPAREN: ")",
    TsTokens.LSQUARE: "[",
    TsTokens.RSQUARE: "]",
    TsTokens.SEMI: ";",
    TsTokens.COMMA: ",",
    TsTokens.COLON: ":",
    TsTokens.DOT: ".",
    TsTokens.ELLIPSIS: "...",
    TsTokens.QUESTION: "?",
    TsTokens.OPTIONAL_CHAIN: "?.",
    TsTokens.NULLISH_COALESCE: "??",
    TsTokens.AT: "@",
    TsTokens.HASH: "#",
    TsTokens.BACKTICK: "`",
    TsTokens.ARROW: "=>",
    TsTokens.EQ: "=",
    TsTokens.ADD_EQ: "+=",
    TsTokens.SUB_EQ: "-=",
    TsTokens.MUL_EQ: "*=",
    TsTokens.DIV_EQ: "/=",
    TsTokens.MOD_EQ: "%=",
    TsTokens.EXP_EQ: "**=",
    TsTokens.AND_EQ: "&=",
    TsTokens.OR_EQ: "|=",
    TsTokens.XOR_EQ: "^=",
    TsTokens.LSHIFT_EQ: "<<=",
    TsTokens.RSHIFT_EQ: ">>=",
    TsTokens.URSHIFT_EQ: ">>>=",
    TsTokens.LOGICAL_AND_EQ: "&&=",
    TsTokens.LOGICAL_OR_EQ: "||=",
    TsTokens.NULLISH_EQ: "??=",
    TsTokens.EE: "==",
    TsTokens.NE: "!=",
    TsTokens.EEE: "===",
    TsTokens.NEE: "!==",
    TsTokens.LT: "<",
    TsTokens.GT: ">",
    TsTokens.LTE: "<=",
    TsTokens.GTE: ">=",
    TsTokens.PLUS: "+",
    TsTokens.MINUS: "-",
    TsTokens.STAR: "*",
    TsTokens.SLASH: "/",
    TsTokens.PERCENT: "%",
    TsTokens.STAR_STAR: "**",
    TsTokens.PLUS_PLUS: "++",
    TsTokens.MINUS_MINUS: "--",
    TsTokens.BW_AND: "&",
    TsTokens.BW_OR: "|",
    TsTokens.BW_XOR: "^",
    TsTokens.BW_NOT: "~",
    TsTokens.LSHIFT: "<<",
    TsTokens.RSHIFT: ">>",
    TsTokens.URSHIFT: ">>>",
    TsTokens.NOT: "!",
    TsTokens.AND: "&&",
    TsTokens.OR: "||",
    TsTokens.JSX_SELF_CLOSE: "/>",
    TsTokens.JSX_CLOSE_START: "</",
    TsTokens.JSX_FRAG_OPEN: "<>",
    TsTokens.JSX_FRAG_CLOSE: "</>"
};


# =============================================================================
# TypeScript Symbol Types
# =============================================================================


enum TsSymbolType(StrEnum) {
    VARIABLE = "variable",
    FUNCTION = "function",
    CLASS = "class",
    INTERFACE = "interface",
    TYPE_ALIAS = "type_alias",
    ENUM = "enum",
    ENUM_MEMBER = "enum_member",
    NAMESPACE = "namespace",
    METHOD = "method",
    PROPERTY = "property",
    PARAMETER = "parameter",
    TYPE_PARAMETER = "type_parameter",
    GETTER = "getter",
    SETTER = "setter",
    CONSTRUCTOR = "constructor",
    IMPORT = "import",
    EXPORT = "export"
}


# =============================================================================
# TypeScript Modifiers
# =============================================================================


enum TsModifier(StrEnum) {
    PUBLIC = "public",
    PRIVATE = "private",
    PROTECTED = "protected",
    STATIC = "static",
    READONLY = "readonly",
    ABSTRACT = "abstract",
    ASYNC = "async",
    CONST = "const",
    DECLARE = "declare",
    EXPORT = "export",
    DEFAULT = "default",
    OVERRIDE = "override"
}
