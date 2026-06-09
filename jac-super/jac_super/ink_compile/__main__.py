"""CLI entry for jac-super's internal Ink compiler."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from jac_super.ink_compile.compile import CompileError, compile_ink_app


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Compile Jac client code to an Ink terminal app (jac-super internal)"
    )
    parser.add_argument("filename", help="Path to .jac entry file")
    parser.add_argument(
        "--out",
        default=".jac/tui",
        help="Output directory (default: .jac/tui)",
    )
    parser.add_argument(
        "--entry",
        default="",
        help="Exported function to run (default: app or first export)",
    )
    args = parser.parse_args(argv)

    try:
        compile_ink_app(
            Path(args.filename),
            Path(args.out),
            entry=args.entry,
        )
    except CompileError as exc:
        sys.stderr.write(f"{exc}\n")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
