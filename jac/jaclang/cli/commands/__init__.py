"""CLI command modules organized by functional group.

This Python module bridges .jac command modules for Python imports.
The actual implementations are in .jac files which are compiled by the
JacMetaImporter when imported.
"""

# mypy: disable-error-code=attr-defined

# Import command modules from .jac files
# These are automatically compiled and registered when imported
from jaclang.cli.commands import analysis as analysis  # noqa: F401,PLC0414
from jaclang.cli.commands import config as config  # noqa: F401,PLC0414
from jaclang.cli.commands import execution as execution  # noqa: F401,PLC0414
from jaclang.cli.commands import project as project  # noqa: F401,PLC0414
from jaclang.cli.commands import tools as tools  # noqa: F401,PLC0414
from jaclang.cli.commands import transform as transform  # noqa: F401,PLC0414

__all__ = ["analysis", "config", "execution", "project", "tools", "transform"]
