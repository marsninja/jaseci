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

"""A mock distribution for testing distinfo tracking."""
obj MockDist {
    has _name: str = "mock-dist",
        _version: str = "1.0.0",
        metadata: dict[str, str] by postinit;

    def postinit -> None {
        self.metadata = {"Name": self._name, "Version": self._version};
    }
}

"""A mock entry point that tracks whether load() was called."""
obj MockEntryPoint {
    has group: str = "jac",
        name: str = "mock_plugin",
        load_count: int = 0,
        _plugin_class: (type | None) = None,
        _should_fail: bool = False,
        dist: (MockDist | None) = None;

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

# ---------------------------------------------------------------------------
# Test 7: list_all_plugins shows both loaded and lazy plugins
# ---------------------------------------------------------------------------
test "list_all_plugins includes loaded and pending lazy plugins" {
    class CoreImpl {
        @_hookimpl
        static def get_mtir -> None {
            return None;
        }
    }

    class LazyPlugin {
        @_hookimpl
        static def get_mtir -> str {
            return "lazy_result";
        }
    }

    dist = MockDist(_name="test-pkg", _version="2.0.0");
    ep = MockEntryPoint(name="lazy_ep", _plugin_class=LazyPlugin, dist=dist);

    pm = PluginManager("test");
    pm.register(CoreImpl);
    pm.register_lazy_entrypoint(ep, hook_names=["get_mtir"]);

    # Before triggering: list_all_plugins should show both.
    all_plugins = pm.list_all_plugins();
    names = [n for (n, _, _) in all_plugins];
    assert "CoreImpl" in names , "Core plugin should be listed";
    assert "lazy_ep" in names , "Lazy plugin should be listed";

    # The lazy entry should have dist info but no plugin object.
    for (name, plugin, dist_info) in all_plugins {
        if name == "lazy_ep" {
            assert plugin is None , "Lazy plugin should not be loaded yet";
            assert dist_info is not None , "Lazy plugin should have dist info";
            assert dist_info.project_name == "test-pkg";
            assert dist_info.version == "2.0.0";
        }
    }

    # After triggering: lazy plugin should be loaded.
    pm.hook.get_mtir();
    all_after = pm.list_all_plugins();
    for (name, plugin, dist_info) in all_after {
        if name == "lazy_ep" {
            assert plugin is not None , "Lazy plugin should be loaded now";
            assert dist_info is not None , "Dist info should persist after load";
            assert dist_info.project_name == "test-pkg";
        }
    }
}

# ---------------------------------------------------------------------------
# Test 8: list_plugin_distinfo populated for eager and lazy paths
# ---------------------------------------------------------------------------
test "list_plugin_distinfo tracks distribution info" {
    class CoreImpl {
        @_hookimpl
        static def get_mtir -> None {
            return None;
        }
    }

    class EagerPlugin {
        @_hookimpl
        static def get_console -> str {
            return "eager";
        }
    }

    class LazyPlugin {
        @_hookimpl
        static def get_mtir -> str {
            return "lazy";
        }
    }

    eager_dist = MockDist(_name="eager-pkg", _version="1.0.0");
    lazy_dist = MockDist(_name="lazy-pkg", _version="2.0.0");
    ep_eager = MockEntryPoint(
        name="eager_ep", _plugin_class=EagerPlugin, dist=eager_dist
    );
    ep_lazy = MockEntryPoint(name="lazy_ep", _plugin_class=LazyPlugin, dist=lazy_dist);

    pm = PluginManager("test");
    pm.register(CoreImpl);

    # Eager load (no manifest).
    pm.register_lazy_entrypoint(ep_eager, hook_names=None);
    # Lazy load (with manifest).
    pm.register_lazy_entrypoint(ep_lazy, hook_names=["get_mtir"]);

    # Eager plugin should already have distinfo.
    distinfo = pm.list_plugin_distinfo();
    eager_names = [d.project_name for (_, d) in distinfo];
    assert "eager-pkg" in eager_names , "Eager plugin should have distinfo";
    assert "lazy-pkg" not in eager_names , "Lazy plugin should not have distinfo yet";

    # Trigger lazy hook.
    pm.hook.get_mtir();

    # Now both should have distinfo.
    distinfo_after = pm.list_plugin_distinfo();
    all_names = [d.project_name for (_, d) in distinfo_after];
    assert "eager-pkg" in all_names , "Eager plugin distinfo should persist";
    assert "lazy-pkg" in all_names , "Lazy plugin should now have distinfo";
}
