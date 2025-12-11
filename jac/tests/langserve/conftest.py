"""Pytest configuration for langserve tests.

NOTE: These tests have state isolation issues when run together in the same process.
The type checking system maintains global state that can pollute between tests.

In CI, these tests are run as separate pytest invocations which provides isolation.
When running locally, you may see flaky failures. To ensure reliability:

1. Run tests individually: pytest tests/langserve/test_server.py::test_name
2. Or run each test file separately: pytest tests/langserve/test_server.py

The tests pass reliably when run with process isolation.
"""
