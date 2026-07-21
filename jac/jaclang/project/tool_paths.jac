"""Single source of truth for where installed CLI tools live.

Both `jac install` (which *writes* tools into these locations) and `jac x`
(which *resolves* tools from them) consult this module, so the install target
and the run-time search path can never drift apart.

Two orthogonal axes:

* scope    -- "project" (this project's ``.jac/``) or "global" (jac-owned,
              shared across every project).
* ecosystem -- "python" (pip / venv, ``console_scripts`` entry points) or
              "node" (bun / npm, ``node_modules/.bin`` shims).

Python "global" is the site-packages of the interpreter jac runs under -- pip
installs there and ``site.getsitepackages()`` reads it back, so there is no
jac-owned directory to manage. Node has no such ambient global, so jac owns one
under ``jac_global_prefix()`` (``~/.jac`` by default, override with
``JAC_GLOBAL_DIR``); its layout mirrors a project's ``.jac/client`` so the same
``node_modules/.bin`` derivation works for both scopes.
"""

import os;
import site;
import from pathlib { Path }
import from jaclang.project.config { JacConfig, get_config }
import from jaclang.project.pyvenv { get_venv_site_packages }


"""Root of the jac-owned global tool store (honors ``JAC_GLOBAL_DIR``)."""
def jac_global_prefix -> Path {
    env_override = os.environ.get("JAC_GLOBAL_DIR");
    if env_override {
        return Path(env_override).expanduser();
    }
    return Path.home() / ".jac";
}


# ---------------------------------------------------------------------------
# Python (pip / venv)
# ---------------------------------------------------------------------------

"""Site-packages of the active project's venv, or None outside a project."""
def python_project_site(config: JacConfig | None = None) -> Path | None {
    config = config if config is not None else get_config();
    if config is None {
        return None;
    }
    return get_venv_site_packages(config.get_venv_dir());
}


"""Site-packages of the interpreter jac runs under (the global python site)."""
def python_global_site -> Path | None {
    try {
        globals_ = site.getsitepackages();
    } except (AttributeError, IndexError, OSError) {
        return None;
    }
    return Path(globals_[0]) if globals_ else None;
}


# ---------------------------------------------------------------------------
# Node (bun / npm)
# ---------------------------------------------------------------------------

"""Install root for node packages at ``scope``, or None if unavailable.

project -> ``<project>/.jac/client`` (shared with the client bundler)
global  -> ``<jac_global_prefix>/npm``
"""
def node_root(scope: str, config: JacConfig | None = None) -> Path | None {
    if scope == "global" {
        return jac_global_prefix() / "npm";
    }
    config = config if config is not None else get_config();
    if config is None {
        return None;
    }
    return config.get_client_dir();
}


"""``node_modules/.bin`` for a node install root (see :func:`node_root`)."""
def node_bin_dir(scope: str, config: JacConfig | None = None) -> Path | None {
    base_dir = node_root(scope, config);
    return (base_dir / "node_modules" / ".bin") if base_dir is not None else None;
}
