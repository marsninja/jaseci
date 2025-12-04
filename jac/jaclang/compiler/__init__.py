"""Jac compiler tools."""

import logging
import os
import sys

# Add vendor directory to sys.path for lark (needed for unpickling parser data)
_vendor_dir = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "vendor"))
if _vendor_dir not in sys.path:
    sys.path.insert(0, _vendor_dir)

try:
    from jaclang.compiler.larkparse import jac_parser as jac_lark

    jac_lark.logger.setLevel(logging.DEBUG)

    TOKEN_MAP = {
        x.name: x.pattern.value
        for x in jac_lark.Lark_StandAlone().parser.lexer_conf.terminals
    }
except (ModuleNotFoundError, ImportError) as e:
    print(f"Warning: Parser not loaded: {e}", file=sys.stderr)
    TOKEN_MAP = {}

# fmt: off
TOKEN_MAP.update(
    {
        "CARROW_L": "<++", "CARROW_R": "++>", "GLOBAL_OP": "global",
        "NONLOCAL_OP": "nonlocal", "WALKER_OP": ":walker:", "NODE_OP": ":node:",
        "EDGE_OP": ":edge:", "CLASS_OP": ":class:", "OBJECT_OP": ":obj:",
        "TYPE_OP": "`", "ABILITY_OP": ":can:", "NULL_OK": "?",
        "KW_OR": "|", "ARROW_BI": "<-->", "ARROW_L": "<--",
        "ARROW_R": "-->", "ARROW_L_P1": "<-:", "ARROW_R_P2": ":->",
        "ARROW_L_P2": ":<-", "ARROW_R_P1": "->:", "CARROW_BI": "<++>",
        "CARROW_L_P1": "<+:", "RSHIFT_EQ": ">>=", "ELLIPSIS": "...",
        "CARROW_R_P2": ":+>", "CARROW_L_P2": ":<+", "CARROW_R_P1": "+>:",
        "PIPE_FWD": "|>", "PIPE_BKWD": "<|", "A_PIPE_FWD": ":>",
        "A_PIPE_BKWD": "<:", "DOT_FWD": ".>", "STAR_POW": "**",
        "STAR_MUL": "*", "FLOOR_DIV": "//", "DIV": "/",
        "PYNLINE": "::py::", "ADD_EQ": "+=", "SUB_EQ": "-=",
        "STAR_POW_EQ": "**=", "MUL_EQ": "*=", "FLOOR_DIV_EQ": "//=",
        "DIV_EQ": "/=", "MOD_EQ": "%=", "BW_AND_EQ": "&=",
        "BW_OR_EQ": "|=", "BW_XOR_EQ": "^=", "BW_NOT_EQ": "~=",
        "LSHIFT_EQ": "<<=",
    }
)
# fmt: on

__all__ = ["jac_lark", "TOKEN_MAP"]
