"""PyCore Parser module - Jac parsing infrastructure.

This module contains the bootstrap-critical parser infrastructure:
- jac_parser: Main Jac parser using Lark
- jac.lark: Grammar file
- larkparse/: Generated Lark parsers
"""

from jaclang.pycore.parser.jac_parser import JacParser

__all__ = ["JacParser"]
