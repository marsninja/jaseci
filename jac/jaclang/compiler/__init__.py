"""Jac compiler tools and parser generation utilities."""

import logging
import os
import shutil
import sys

_vendor_dir = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "vendor"))
if _vendor_dir not in sys.path:
    sys.path.insert(0, _vendor_dir)

_cur_dir = os.path.dirname(__file__)
_pycore_dir = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "pycore"))


def generate_static_parser(force: bool = False) -> None:
    """Generate static parser for Jac."""
    from lark.tools import standalone

    larkparse_dir = os.path.join(_pycore_dir, "parser", "larkparse")
    if force or not os.path.exists(os.path.join(larkparse_dir, "jac_parser.py")):
        if os.path.exists(larkparse_dir):
            shutil.rmtree(larkparse_dir)
        os.makedirs(larkparse_dir, exist_ok=True)
        open(os.path.join(larkparse_dir, "__init__.py"), "w").close()
        sys.argv, save = (
            [
                "lark",
                os.path.join(_pycore_dir, "parser", "jac.lark"),
                "-o",
                os.path.join(larkparse_dir, "jac_parser.py"),
                "-c",
            ],
            sys.argv,
        )
        standalone.main()
        sys.argv = save


def generate_ts_static_parser(force: bool = False) -> None:
    """Generate static parser for TypeScript/JavaScript."""
    from lark.tools import standalone

    larkparse_dir = os.path.join(_pycore_dir, "parser", "larkparse")
    ts_parser_path = os.path.join(larkparse_dir, "ts_parser.py")
    if force or not os.path.exists(ts_parser_path):
        os.makedirs(larkparse_dir, exist_ok=True)
        init_path = os.path.join(larkparse_dir, "__init__.py")
        if not os.path.exists(init_path):
            open(init_path, "w").close()
        sys.argv, save = (
            ["lark", os.path.join(_cur_dir, "ts.lark"), "-o", ts_parser_path, "-c"],
            sys.argv,
        )
        standalone.main()
        sys.argv = save


def gen_all_parsers() -> None:
    """Generate all parsers."""
    generate_static_parser(force=True)
    generate_ts_static_parser(force=True)
    print("Parsers generated.")


# Check if larkparse exists and generate if needed
_larkparse_dir = os.path.join(_pycore_dir, "parser", "larkparse")
if not os.path.exists(os.path.join(_larkparse_dir, "jac_parser.py")):
    print("Parser not present, generating for developer setup...", file=sys.stderr)
    try:
        gen_all_parsers()
    except Exception as e:
        print(f"Warning: Could not generate parser: {e}", file=sys.stderr)

# Import from pycore/parser - these are canonical exports.
# This needs to remain after the parser generation check above.
from jaclang.pycore.parser import TOKEN_MAP, jac_lark  # noqa: E402

if jac_lark:
    jac_lark.logger.setLevel(logging.DEBUG)

__all__ = [
    "jac_lark",
    "TOKEN_MAP",
    "generate_static_parser",
    "generate_ts_static_parser",
    "gen_all_parsers",
]

if __name__ == "__main__":
    gen_all_parsers()
