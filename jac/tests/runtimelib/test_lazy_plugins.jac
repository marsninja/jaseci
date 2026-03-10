"""Tests for lazy plugin loading.

Verifies that external plugins are NOT imported at startup and only load
when a hook they implement is actually called.

Tests exercise the real PluginManager.register_lazy_entrypoint() API
with mock entry points to verify lazy loading contracts.
"""

import sys;
import jaclang.jac0core.plugin as pluggy;
import from jaclang.jac0core.plugin { HookCaller, HookimplMarker, PluginManager }

# ---------------------------------------------------------------------------
# Test helpers — only mocks, no implementation
# ---------------------------------------------------------------------------
glob _hookimpl = HookimplMarker("test");

"""A mock entry point that tracks whether load() was called."""
obj MockEntryPoint {
    has group: str = "jac",
        name: str = "mock_plugin",
        load_count: int = 0,
        _plugin_class: (type | None) = None,
        _should_fail: bool = False;

    def load -> (type | None) {
        if self._should_fail {
            raise ImportError(f"Mock failure loading {self.name}");
        }
        self.load_count += 1;
        return self._plugin_class;
    }
}

# ---------------------------------------------------------------------------
# Test 1: Nothing loads at startup
# ---------------------------------------------------------------------------
test "no external plugins loaded at startup" {
    class CoreImpl {
        @_hookimpl
        static def get_mtir -> None {
            return None;
        }

        @_hookimpl
        static def get_console -> str {
            return "core_console";
        }
    }

    class LLMPlugin {
        @_hookimpl
        static def get_mtir -> str {
            return "llm_result";
        }
    }

    ep = MockEntryPoint(name="byllm_mock", _plugin_class=LLMPlugin);

    pm = PluginManager("test");
    pm.register(CoreImpl);

    # This is the API that needs to be implemented.
    # It should record the EP as pending without calling ep.load().
    pm.register_lazy_entrypoint(ep, hook_names=["get_mtir"]);

    # The PM should only have CoreImpl registered — not the plugin.
    registered_names = [name for (name, _) in pm.list_name_plugin()];
    assert "byllm_mock" not in registered_names , "Plugin should not be registered at startup";
    assert ep.load_count == 0 , "Plugin module should not have been imported";
}

# ---------------------------------------------------------------------------
# Test 2: Hook call loads only the right plugin
# ---------------------------------------------------------------------------
test "hook triggers exactly the relevant plugin" {
    class CoreImpl {
        @_hookimpl
        static def get_mtir -> None {
            return None;
        }

        @_hookimpl
        static def get_console -> None {
            return None;
        }

        @_hookimpl
        static def create_server -> None {
            return None;
        }
    }

    class PluginA {
        @_hookimpl
        static def get_mtir -> str {
            return "from_a";
        }
    }

    class PluginB {
        @_hookimpl
        static def get_console -> str {
            return "from_b";
        }
    }

    class PluginC {
        @_hookimpl
        static def create_server -> str {
            return "from_c";
        }
    }

    ep_a = MockEntryPoint(name="plugin_a", _plugin_class=PluginA);
    ep_b = MockEntryPoint(name="plugin_b", _plugin_class=PluginB);
    ep_c = MockEntryPoint(name="plugin_c", _plugin_class=PluginC);

    pm = PluginManager("test");
    pm.register(CoreImpl);
    pm.register_lazy_entrypoint(ep_a, hook_names=["get_mtir"]);
    pm.register_lazy_entrypoint(ep_b, hook_names=["get_console"]);
    pm.register_lazy_entrypoint(ep_c, hook_names=["create_server"]);

    # Call get_mtir — only plugin_a should load.
    result = pm.hook.get_mtir();
    assert ep_a.load_count == 1 , "plugin_a should have loaded";
    assert ep_b.load_count == 0 , "plugin_b should NOT have loaded";
    assert ep_c.load_count == 0 , "plugin_c should NOT have loaded";
    assert result == "from_a" , "Should return plugin_a's result";

    # Call get_mtir again — no double load.
    result2 = pm.hook.get_mtir();
    assert ep_a.load_count == 1 , "plugin_a should not reload";
    assert result2 == "from_a";

    # Call get_console — only plugin_b loads now.
    result3 = pm.hook.get_console();
    assert ep_b.load_count == 1 , "plugin_b should have loaded";
    assert ep_c.load_count == 0 , "plugin_c should still NOT have loaded";
    assert result3 == "from_b";
}

# ---------------------------------------------------------------------------
# Test 3: Disabled plugin never loads
# ---------------------------------------------------------------------------
test "disabled plugins stay unloaded even when hook fires" {
    class CoreImpl {
        @_hookimpl
        static def get_mtir -> None {
            return None;
        }
    }

    class BlockedPlugin {
        @_hookimpl
        static def get_mtir -> str {
            return "should_never_see_this";
        }
    }

    ep = MockEntryPoint(name="blocked", _plugin_class=BlockedPlugin);

    pm = PluginManager("test");
    pm.register(CoreImpl);
    pm.register_lazy_entrypoint(ep, hook_names=["get_mtir"], disabled=["blocked"]);

    # Call the hook — disabled plugin should be skipped.
    result = pm.hook.get_mtir();
    assert ep.load_count == 0 , "Disabled plugin must never be loaded";
    assert result is None , "Should fall through to core impl returning None";
}

# ---------------------------------------------------------------------------
# Test 4: CLI commands work without plugin imports
# ---------------------------------------------------------------------------
test "cli help available but plugins not imported" {
    class CoreImpl {
        @_hookimpl
        static def create_server -> None {
            return None;
        }
    }

    class ScalePlugin {
        @_hookimpl
        static def create_server -> str {
            return "scale_server";
        }
    }

    ep = MockEntryPoint(name="scale", _plugin_class=ScalePlugin);

    # Simulated command metadata (would come from pyproject.toml entry points).
    # This part is pure data — no plugin import needed.
    command_metadata = [{"name": "start --scale", "help": "Deploy to Kubernetes"}];
    help_entries = [cmd["help"] for cmd in command_metadata];
    assert "Deploy to Kubernetes" in help_entries;
    assert ep.load_count == 0 , "Plugin must not load for help text";

    # User invokes the command — NOW the plugin loads via lazy hook.
    pm = PluginManager("test");
    pm.register(CoreImpl);
    pm.register_lazy_entrypoint(ep, hook_names=["create_server"]);

    result = pm.hook.create_server();
    assert ep.load_count == 1 , "Plugin should load when command executes";
    assert result == "scale_server";
}

# ---------------------------------------------------------------------------
# Test 5: Legacy plugin without manifest falls back to eager load
# ---------------------------------------------------------------------------
test "plugin without hook manifest falls back to eager load" {
    class CoreImpl {
        @_hookimpl
        static def get_console -> None {
            return None;
        }
    }

    class LegacyPlugin {
        @_hookimpl
        static def get_console -> str {
            return "legacy_console";
        }
    }

    # Legacy EP has no hook_names — register_lazy_entrypoint with
    # hook_names=None should fall back to eager loading.
    ep = MockEntryPoint(name="legacy", _plugin_class=LegacyPlugin);

    pm = PluginManager("test");
    pm.register(CoreImpl);
    pm.register_lazy_entrypoint(ep, hook_names=None);

    # Should have loaded eagerly since no manifest.
    assert ep.load_count == 1 , "Legacy plugin should load eagerly";
    registered_names = [name for (name, _) in pm.list_name_plugin()];
    assert "legacy" in registered_names , "Legacy plugin should be registered";

    # Hooks should work normally.
    result = pm.hook.get_console();
    assert "legacy_console" in result;
}

# ---------------------------------------------------------------------------
# Test 6: Broken plugin doesn't crash, others still work
# ---------------------------------------------------------------------------
test "broken plugin does not crash and others still work" {
    class CoreImpl {
        @_hookimpl
        static def get_mtir -> None {
            return None;
        }

        @_hookimpl
        static def get_console -> None {
            return None;
        }
    }

    class GoodPlugin {
        @_hookimpl
        static def get_console -> str {
            return "good_console";
        }
    }

    ep_bad = MockEntryPoint(name="broken_plugin", _plugin_class=None, _should_fail=True);
    ep_good = MockEntryPoint(name="good_plugin", _plugin_class=GoodPlugin);

    pm = PluginManager("test");
    pm.register(CoreImpl);
    pm.register_lazy_entrypoint(ep_bad, hook_names=["get_mtir"]);
    pm.register_lazy_entrypoint(ep_good, hook_names=["get_console"]);

    # Call the broken plugin's hook — should not crash.
    result_bad = pm.hook.get_mtir();
    assert result_bad is None , "Should fall through to core impl on failure";
    assert ep_bad.load_count == 0 , "Broken plugin load() should have raised";

    # The good plugin should still work fine.
    result_good = pm.hook.get_console();
    assert ep_good.load_count == 1 , "Good plugin should load normally";
    assert result_good == "good_console";
}
