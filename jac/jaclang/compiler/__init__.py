"""Jac compiler tools and parser generation utilities."""

import os
import sys

_vendor_dir = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "vendor"))
if _vendor_dir not in sys.path:
    sys.path.insert(0, _vendor_dir)

_cur_dir = os.path.dirname(__file__)
_pycore_dir = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "pycore"))


def generate_ts_static_parser(force: bool = False) -> None:
    """Generate static parser for TypeScript/JavaScript."""
    from lark.tools import standalone

    lark_ts_parser_path = os.path.join(_pycore_dir, "lark_ts_parser.py")
    if force or not os.path.exists(lark_ts_parser_path):
        sys.argv, save = (
            [
                "lark",
                os.path.join(_cur_dir, "ts.lark"),
                "-o",
                lark_ts_parser_path,
                "-c",
            ],
            sys.argv,
        )
        standalone.main()
        sys.argv = save


# Auto-generate TS parser if missing (for developer setup)
_lark_ts_parser_path = os.path.join(_pycore_dir, "lark_ts_parser.py")
if not os.path.exists(_lark_ts_parser_path):
    print("TS parser not present, generating for developer setup...", file=sys.stderr)
    try:
        generate_ts_static_parser(force=True)
    except Exception as e:
        print(f"Warning: Could not generate TS parser: {e}", file=sys.stderr)

__all__ = [
    "generate_ts_static_parser",
]
