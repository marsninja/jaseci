"""Plugin loader for the Jac runtime.

Loads external plugins via setuptools entry points. Designed to be called
explicitly by the CLI or other entry points — never at import time.
"""

glob _plugins_loaded = False;

"""Load all external plugins, respecting disabled list from env/jac.toml.

Safe to call multiple times — subsequent calls are no-ops.
"""
def load_plugins -> None {
    global _plugins_loaded;
    if _plugins_loaded {
        return;
    }
    _plugins_loaded = True;

    import from jaclang.jac0core.runtime { plugin_manager }
    import from jaclang.jac0core.helpers {
        get_disabled_plugins,
        load_plugins_with_disabling
    }

    disabled = get_disabled_plugins();
    if disabled {
        load_plugins_with_disabling(plugin_manager, disabled);
    } else {
        plugin_manager.load_setuptools_entrypoints("jac");
    }
}
