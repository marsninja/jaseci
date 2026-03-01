"""Test discovery canary.

Validates that pytest discovers the expected number of tests.
Only runs during full-suite invocations (``pytest -x jac`` or ``pytest``).
Reads collection metadata exported by conftest.py.
"""

import os;

glob EXPECTED_MIN_TESTS = 3900;

test "test discovery count" {
    args = os.environ.get("_JAC_TEST_ARGS", "");
    if args not in ["", "jac"] {
        return;
    }
    count = int(os.environ.get("_JAC_TEST_COUNT", "0"));
    assert count >= EXPECTED_MIN_TESTS , f"Only {count} tests discovered (expected >= {EXPECTED_MIN_TESTS}). Test discovery may be broken.";
}
