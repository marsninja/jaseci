"""PyCore Parser module - Jac parsing infrastructure.

This module contains the bootstrap-critical parser infrastructure:
- jac_parser: Main Jac parser using Lark
- jac.lark: Grammar file
- larkparse/: Generated Lark parsers
"""

from jaclang.pycore.parser.jac_parser import TOKEN_MAP, JacParser
from jaclang.pycore.parser.larkparse import jac_parser as jac_lark

__all__ = ["JacParser", "TOKEN_MAP", "jac_lark"]
