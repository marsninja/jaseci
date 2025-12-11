"""Collection of passes for Jac IR.

This module uses lazy imports to enable converting passes to Jac.
Bootstrap-critical passes are loaded eagerly, while analysis passes
that can be deferred are loaded lazily via __getattr__.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

# Bootstrap-critical passes (must remain Python for now)
from ..transform import Alert, BaseTransform, Transform
from .pyast_gen_pass import PyastGenPass
from .pybc_gen_pass import PyBytecodeGenPass
from .sym_tab_build_pass import SymTabBuildPass, UniPass

# Passes that are imported lazily to allow .jac conversion
# These are loaded on first access via __getattr__
_LAZY_PASSES = {
    "JacAnnexPass": ".annex_pass",
    "CFGBuildPass": ".cfg_build_pass",
    "DeclImplMatchPass": ".def_impl_match_pass",
    "JacImportDepsPass": ".import_pass",
    "PyJacAstLinkPass": ".pyjac_ast_link_pass",
    "PyastBuildPass": ".pyast_load_pass",  # py2jac - NOT bootstrap-critical
    "SemDefMatchPass": ".sem_def_match_pass",
    "SemanticAnalysisPass": ".semantic_analysis_pass",
    "TypeCheckPass": ".type_checker_pass",
    "DefUsePass": ".def_use_pass",
}

# Passes that MUST remain Python - used in get_minimal_ir_gen_sched()
# These are needed to compile the .jac passes themselves
_PYTHON_ONLY_PASSES = frozenset(
    {
        "JacAnnexPass",  # Used during parse_str
        "SemanticAnalysisPass",  # In minimal IR schedule
        "DeclImplMatchPass",  # In minimal IR schedule
    }
)

# Cache for lazily loaded passes
_lazy_cache: dict[str, type] = {}

if TYPE_CHECKING:
    from .annex_pass import JacAnnexPass as JacAnnexPass
    from .cfg_build_pass import CFGBuildPass as CFGBuildPass
    from .def_impl_match_pass import DeclImplMatchPass as DeclImplMatchPass
    from .def_use_pass import DefUsePass as DefUsePass
    from .import_pass import JacImportDepsPass as JacImportDepsPass
    from .pyast_load_pass import PyastBuildPass as PyastBuildPass
    from .pyjac_ast_link_pass import PyJacAstLinkPass as PyJacAstLinkPass
    from .sem_def_match_pass import SemDefMatchPass as SemDefMatchPass
    from .semantic_analysis_pass import SemanticAnalysisPass as SemanticAnalysisPass
    from .type_checker_pass import TypeCheckPass as TypeCheckPass


def __getattr__(name: str) -> type:
    """Lazily load passes on first access.

    Supports both Python (.py) and Jac (.jac) modules.
    Jac files are preferred when both exist.
    """
    if name in _lazy_cache:
        return _lazy_cache[name]

    if name in _LAZY_PASSES:
        import importlib
        import importlib.util
        import os
        import sys

        module_name = _LAZY_PASSES[name]
        base_name = module_name.lstrip(".")

        # Check if a .jac file exists
        package_dir = os.path.dirname(__file__)
        jac_file = os.path.join(package_dir, f"{base_name}.jac")
        full_module_name = f"{__name__}.{base_name}"

        # Check if this pass must remain Python (bootstrap requirement)
        use_jac = name not in _PYTHON_ONLY_PASSES and os.path.exists(jac_file)

        if use_jac:
            # Use Jac import mechanism via the meta importer
            from jaclang.meta_importer import JacMetaImporter
            from jaclang.pycore.runtime.runtime import JacRuntime as Jac

            # Create module spec and load
            importer = JacMetaImporter()
            spec = importlib.util.spec_from_file_location(
                full_module_name, jac_file, loader=importer
            )
            if spec and spec.loader:
                module = importlib.util.module_from_spec(spec)
                sys.modules[full_module_name] = module
                Jac.load_module(full_module_name, module)
                spec.loader.exec_module(module)
            else:
                raise ImportError(f"Could not load Jac module: {jac_file}")
        else:
            # Fall back to Python import
            module = importlib.import_module(module_name, package=__name__)

        cls = getattr(module, name)
        _lazy_cache[name] = cls
        return cls

    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")


__all__ = [
    "Alert",
    "BaseTransform",
    "Transform",
    "UniPass",
    "JacAnnexPass",
    "JacImportDepsPass",
    "TypeCheckPass",
    "SymTabBuildPass",
    "SemanticAnalysisPass",
    "DeclImplMatchPass",
    "SemDefMatchPass",
    "PyastBuildPass",
    "PyastGenPass",
    "PyBytecodeGenPass",
    "CFGBuildPass",
    "PyJacAstLinkPass",
    "DefUsePass",
]
