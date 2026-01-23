#!/usr/bin/env python3
"""
Validate Jac code blocks in documentation markdown files.

Extracts ```jac code blocks from markdown files and runs `jac check` on them.
Reports errors with file:line information for easy debugging.

Usage:
    python validate_docs_code.py [--docs-dir PATH] [--verbose] [--fix]

Exit codes:
    0 - All code blocks pass validation
    1 - One or more code blocks failed validation
    2 - Script error (invalid arguments, missing dependencies)
"""

import argparse
import contextlib
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


@dataclass
class CodeBlock:
    """Represents a code block extracted from a markdown file."""

    content: str
    file_path: str
    line_number: int
    language: str


@dataclass
class ValidationResult:
    """Result of validating a code block."""

    code_block: CodeBlock
    success: bool
    output: str
    error: str


def extract_code_blocks(file_path: Path) -> list[CodeBlock]:
    """Extract all jac code blocks from a markdown file."""
    code_blocks = []

    with open(file_path, encoding="utf-8") as f:
        content = f.read()
        lines = content.split("\n")

    # Pattern to match code blocks: ```jac or ```jac:something
    # Also matches ```jac linenums="1" or similar attributes
    pattern = re.compile(r"^```(jac(?::\w+)?(?:\s+[^\n]*)?)\s*$")

    i = 0
    while i < len(lines):
        match = pattern.match(lines[i])
        if match:
            language = match.group(1).split()[0]  # Get just 'jac' or 'jac:something'
            start_line = i + 1
            block_lines = []
            i += 1

            # Collect lines until closing ```
            while i < len(lines) and not lines[i].startswith("```"):
                block_lines.append(lines[i])
                i += 1

            if block_lines:
                code_blocks.append(
                    CodeBlock(
                        content="\n".join(block_lines),
                        file_path=str(file_path),
                        line_number=start_line,
                        language=language,
                    )
                )
        i += 1

    return code_blocks


def validate_code_block(
    code_block: CodeBlock, verbose: bool = False
) -> ValidationResult:
    """Validate a single code block using jac check."""
    # Skip empty code blocks
    if not code_block.content.strip():
        return ValidationResult(
            code_block=code_block,
            success=True,
            output="(empty block)",
            error="",
        )

    # Skip code blocks that are clearly incomplete/snippets
    # These often have "..." or comments indicating they're partial
    content = code_block.content.strip()

    # Skip blocks that are just comments or have placeholder patterns
    skip_patterns = [
        r"^\s*#.*$",  # Just a comment
        r"^\s*\.\.\.\s*$",  # Just ellipsis
        r"^\s*//.*$",  # Just a C-style comment
    ]

    if any(re.match(p, content) for p in skip_patterns):
        return ValidationResult(
            code_block=code_block,
            success=True,
            output="(skipped: incomplete snippet)",
            error="",
        )

    # Skip blocks containing placeholder patterns like "{ ... }" or "..."
    if re.search(r"\{\s*\.\.\.\s*\}", content) or re.search(
        r"^\s*\.\.\.\s*$", content, re.MULTILINE
    ):
        return ValidationResult(
            code_block=code_block,
            success=True,
            output="(skipped: contains placeholder)",
            error="",
        )

    # Skip blocks that are mostly inline comments (syntax documentation)
    # These are usually showing syntax patterns, not runnable code
    lines = [line.strip() for line in content.split("\n") if line.strip()]
    comment_lines = sum(
        1 for line in lines if line.startswith("#") or line.startswith("//")
    )
    if len(lines) > 0 and comment_lines / len(lines) > 0.4:
        return ValidationResult(
            code_block=code_block,
            success=True,
            output="(skipped: syntax documentation)",
            error="",
        )

    # Skip blocks that don't have any top-level declarations
    # (these are usually syntax examples showing expressions/patterns)
    top_level_patterns = [
        r"^\s*(node|edge|walker|obj|enum|def|can|with\s+entry|import|glob|include)",
        r"^\s*(class|async\s+def)",  # Python-style
    ]
    has_declaration = any(
        re.search(p, content, re.MULTILINE) for p in top_level_patterns
    )
    if not has_declaration:
        return ValidationResult(
            code_block=code_block,
            success=True,
            output="(skipped: no declarations - syntax example)",
            error="",
        )

    # Create a temporary file with the code
    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".jac", delete=False, encoding="utf-8"
    ) as f:
        f.write(code_block.content)
        temp_path = f.name

    try:
        # Run jac check on the temp file
        result = subprocess.run(
            ["jac", "check", temp_path],
            capture_output=True,
            text=True,
            timeout=30,
        )

        success = result.returncode == 0
        output = result.stdout.strip() if result.stdout else ""
        error = result.stderr.strip() if result.stderr else ""

        # Check for actual errors (not just "0 errors" in success message)
        # Look for patterns like "X errors" where X > 0, or "error:" prefix
        if success:
            # Check for non-zero error count like "3 errors" or "1 error"
            error_count_match = re.search(r"(\d+)\s+errors?", output + error)
            if (
                error_count_match
                and int(error_count_match.group(1)) > 0
                or re.search(r"(?m)^\s*error:", output + error, re.IGNORECASE)
            ):
                success = False

        return ValidationResult(
            code_block=code_block,
            success=success,
            output=output,
            error=error,
        )

    except subprocess.TimeoutExpired:
        return ValidationResult(
            code_block=code_block,
            success=False,
            output="",
            error="Validation timed out after 30 seconds",
        )
    except FileNotFoundError:
        return ValidationResult(
            code_block=code_block,
            success=False,
            output="",
            error="jac command not found. Is jaclang installed?",
        )
    finally:
        # Clean up temp file
        with contextlib.suppress(OSError):
            os.unlink(temp_path)


def find_markdown_files(docs_dir: Path) -> list[Path]:
    """Find all markdown files in the docs directory."""
    return sorted(docs_dir.rglob("*.md"))


def format_error_location(result: ValidationResult) -> str:
    """Format the error location for display."""
    return f"{result.code_block.file_path}:{result.code_block.line_number}"


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Validate Jac code blocks in documentation",
    )
    parser.add_argument(
        "--docs-dir",
        type=Path,
        default=Path(__file__).parent.parent / "docs",
        help="Path to the docs directory (default: docs/docs)",
    )
    parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Show verbose output including successful validations",
    )
    parser.add_argument(
        "--file",
        "-f",
        type=Path,
        help="Validate a specific file instead of all docs",
    )
    parser.add_argument(
        "--summary",
        "-s",
        action="store_true",
        help="Show only summary, not individual errors",
    )

    args = parser.parse_args()

    # Determine which files to validate
    if args.file:
        if not args.file.exists():
            print(f"Error: File not found: {args.file}", file=sys.stderr)
            return 2
        markdown_files = [args.file]
    else:
        if not args.docs_dir.exists():
            print(f"Error: Docs directory not found: {args.docs_dir}", file=sys.stderr)
            return 2
        markdown_files = find_markdown_files(args.docs_dir)

    print(f"Validating Jac code blocks in {len(markdown_files)} markdown files...")
    print()

    total_blocks = 0
    passed_blocks = 0
    failed_blocks = 0
    skipped_blocks = 0
    failed_results: list[ValidationResult] = []

    for md_file in markdown_files:
        code_blocks = extract_code_blocks(md_file)

        if not code_blocks:
            continue

        if args.verbose:
            print(f"  {md_file}: {len(code_blocks)} code block(s)")

        for block in code_blocks:
            total_blocks += 1
            result = validate_code_block(block, args.verbose)

            if result.success:
                if "(skipped" in result.output:
                    skipped_blocks += 1
                else:
                    passed_blocks += 1
                if args.verbose:
                    print(f"    ✓ Line {block.line_number}")
            else:
                failed_blocks += 1
                failed_results.append(result)
                if not args.summary:
                    print(f"    ✗ Line {block.line_number}")

    # Print summary
    print()
    print("=" * 60)
    print("VALIDATION SUMMARY")
    print("=" * 60)
    print(f"Total code blocks: {total_blocks}")
    print(f"  Passed:  {passed_blocks}")
    print(f"  Failed:  {failed_blocks}")
    print(f"  Skipped: {skipped_blocks}")
    print()

    # Print failed blocks details
    if failed_results and not args.summary:
        print("FAILED CODE BLOCKS:")
        print("-" * 60)
        for result in failed_results:
            print()
            print(f"Location: {format_error_location(result)}")
            print(f"Language: {result.code_block.language}")
            print()
            print("Code:")
            for i, line in enumerate(
                result.code_block.content.split("\n")[:10], start=1
            ):
                print(f"  {i:3d} | {line}")
            if len(result.code_block.content.split("\n")) > 10:
                print("  ... (truncated)")
            print()
            if result.error:
                print("Error:")
                print(f"  {result.error}")
            if result.output:
                print("Output:")
                for line in result.output.split("\n")[:5]:
                    print(f"  {line}")
            print("-" * 60)

    if failed_blocks > 0:
        print(f"\n❌ {failed_blocks} code block(s) failed validation")
        return 1
    else:
        print("\n✓ All code blocks passed validation")
        return 0


if __name__ == "__main__":
    sys.exit(main())
