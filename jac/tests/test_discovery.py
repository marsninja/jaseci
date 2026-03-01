"""Validate that pytest discovers the expected number of tests.

This acts as a canary: if test discovery drops (e.g. because package
markers like __init__.py were removed incorrectly), this test will fail
and report exactly how many tests went missing.
"""

import subprocess
import sys

EXPECTED_MIN_TESTS = 3900


def test_test_discovery_count() -> None:
    """Ensure pytest collects at least EXPECTED_MIN_TESTS tests."""
    result = subprocess.run(
        [sys.executable, "-m", "pytest", "--collect-only", "-q"],
        capture_output=True,
        text=True,
        cwd=str(__import__("pathlib").Path(__file__).resolve().parent.parent),
    )
    # Last non-empty line looks like "3918 tests collected in 5.12s"
    for line in reversed(result.stdout.splitlines()):
        line = line.strip()
        if "tests collected" in line or "test collected" in line:
            count = int(line.split()[0])
            assert count >= EXPECTED_MIN_TESTS, (
                f"Only {count} tests discovered (expected >= {EXPECTED_MIN_TESTS}). "
                "Test discovery may be broken."
            )
            return
    raise AssertionError(
        f"Could not parse test count from pytest output:\n{result.stdout}\n{result.stderr}"
    )
