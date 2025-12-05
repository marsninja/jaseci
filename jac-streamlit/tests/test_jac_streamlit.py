"""Test Jac Plugins."""

import inspect
import os
import subprocess
from collections.abc import Callable

import pytest
from jaclang_streamlit import AppTest


@pytest.fixture
def fixture_path() -> Callable[[str], str]:
    """Get absolute path to fixture file."""

    def _fixture_path(fixture: str) -> str:
        frame = inspect.currentframe()
        if frame is None or frame.f_back is None:
            raise ValueError("Unable to get the previous stack frame.")
        module = inspect.getmodule(frame.f_back)
        if module is None or module.__file__ is None:
            raise ValueError("Unable to determine the file of the module.")
        fixture_src = module.__file__
        file_path = os.path.join(os.path.dirname(fixture_src), "fixtures", fixture)
        return os.path.abspath(file_path)

    return _fixture_path


def test_streamlit() -> None:
    """Basic test for pass."""
    command_streamlit = "jac streamlit -h"
    command_dot_view = "jac dot_view -h"

    result = subprocess.run(
        command_streamlit, shell=True, capture_output=True, text=True
    )
    dot_result = subprocess.run(
        command_dot_view, shell=True, capture_output=True, text=True
    )

    # Check basic description
    assert "Streamlit the specified .jac file" in result.stdout

    # Check CLI structure
    assert "positional arguments:" in result.stdout
    assert "filename" in result.stdout

    # Dot view command
    assert "View the content of a DOT file" in dot_result.stdout
    assert "positional arguments:" in dot_result.stdout
    assert "filename" in dot_result.stdout


def test_app(fixture_path: Callable[[str], str]) -> None:
    """Test Jac Streamlit App."""
    fixture_abs_path = fixture_path("sample.jac")
    app: AppTest = AppTest.from_jac_file(fixture_abs_path).run()
    assert len(app.exception) == 0
    assert app.get("button")[0].label == "Greet me"

    app.get("text_input")[0].set_value("John Doe")
    app.get("number_input")[0].set_value(42)
    app.get("button")[0].set_value(True).run()
    assert app.success[0].value == "Hello, John Doe! You are 42 years old."
