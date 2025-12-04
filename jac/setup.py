"""Setup script with custom build hook for parser generation."""

from setuptools import setup
from setuptools.command.build_py import build_py


class BuildPyWithParser(build_py):
    """Custom build_py command that generates parsers before building."""

    def run(self) -> None:
        """Generate static parsers, then run the standard build_py."""
        from jaclang.compiler import generate_static_parser, generate_ts_static_parser

        generate_static_parser(force=True)
        generate_ts_static_parser(force=True)
        super().run()


setup(cmdclass={"build_py": BuildPyWithParser})
