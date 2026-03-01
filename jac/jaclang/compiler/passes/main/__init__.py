"""Collection of passes for Jac IR."""

from jaclang.compiler.passes.main.cfg_build_pass import CFGBuildPass  # noqa: F401
from jaclang.compiler.passes.main.mtir_gen_pass import MTIRGenPass  # noqa: F401
from jaclang.compiler.passes.main.pyast_load_pass import PyastBuildPass  # noqa: F401
from jaclang.compiler.passes.main.pyjac_ast_link_pass import (
    PyJacAstLinkPass,  # noqa: F401
)
from jaclang.compiler.passes.main.sem_def_match_pass import (
    SemDefMatchPass,  # noqa: F401
)
from jaclang.compiler.passes.main.static_analysis_pass import (
    StaticAnalysisPass,  # noqa: F401
)
from jaclang.compiler.passes.main.type_checker_pass import TypeCheckPass  # noqa: F401

__all__ = [
    "CFGBuildPass",
    "MTIRGenPass",
    "PyastBuildPass",
    "PyJacAstLinkPass",
    "SemDefMatchPass",
    "StaticAnalysisPass",
    "TypeCheckPass",
]
