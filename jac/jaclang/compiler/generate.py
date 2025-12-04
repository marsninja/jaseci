"""Parser generation utilities - standalone module with no circular dependencies."""

import os
import shutil
import sys


def generate_static_parser(force: bool = False) -> None:
    """Generate static parser for Jac."""
    from jaclang.vendor.lark.tools import standalone

    cur_dir = os.path.dirname(__file__)
    if force or not os.path.exists(os.path.join(cur_dir, "larkparse", "jac_parser.py")):
        if os.path.exists(os.path.join(cur_dir, "larkparse")):
            shutil.rmtree(os.path.join(cur_dir, "larkparse"))
        os.makedirs(os.path.join(cur_dir, "larkparse"), exist_ok=True)
        with open(os.path.join(cur_dir, "larkparse", "__init__.py"), "w"):
            pass
        save_argv = sys.argv
        sys.argv = [
            "lark",
            os.path.join(cur_dir, "jac.lark"),
            "-o",
            os.path.join(cur_dir, "larkparse", "jac_parser.py"),
            "-c",
        ]
        standalone.main()
        sys.argv = save_argv


def generate_ts_static_parser(force: bool = False) -> None:
    """Generate static parser for TypeScript/JavaScript."""
    from jaclang.vendor.lark.tools import standalone

    cur_dir = os.path.dirname(__file__)
    ts_parser_path = os.path.join(cur_dir, "larkparse", "ts_parser.py")

    if force or not os.path.exists(ts_parser_path):
        os.makedirs(os.path.join(cur_dir, "larkparse"), exist_ok=True)
        # Ensure __init__.py exists
        init_path = os.path.join(cur_dir, "larkparse", "__init__.py")
        if not os.path.exists(init_path):
            with open(init_path, "w"):
                pass

        save_argv = sys.argv
        sys.argv = [
            "lark",
            os.path.join(cur_dir, "ts.lark"),
            "-o",
            ts_parser_path,
            "-c",
        ]
        standalone.main()
        sys.argv = save_argv


if __name__ == "__main__":
    generate_static_parser(force=True)
    generate_ts_static_parser(force=True)
    print("Parser generated.")
