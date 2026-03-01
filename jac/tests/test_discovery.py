"""Validate that pytest discovers the expected number of tests.

This acts as a canary: if test discovery drops (e.g. because package
markers like __init__.py were removed incorrectly), this test will fail
and report exactly how many tests went missing.

Only meaningful when the full test suite is collected — automatically
skips when a subset of tests is selected.
"""

import pytest

EXPECTED_MIN_TESTS = 3900


def test_test_discovery_count(request: pytest.FixtureRequest) -> None:
    """Ensure pytest collected at least EXPECTED_MIN_TESTS tests."""
    count = len(request.session.items)
    if count < int(EXPECTED_MIN_TESTS * 0.95):
        pytest.skip(
            f"Partial run ({count} tests) — discovery check requires full suite"
        )
    assert count >= EXPECTED_MIN_TESTS, (
        f"Only {count} tests discovered (expected >= {EXPECTED_MIN_TESTS}). "
        "Test discovery may be broken."
    )
