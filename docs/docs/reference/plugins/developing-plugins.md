# Building Jac Plugins

Jac has a plugin system that lets you extend the compiler, runtime, and CLI. Plugins are standard Python packages that register hook implementations via entry points. Plugins can be written in Jac or Python.

## Quick Start: CLI Command Plugin

The simplest plugin adds a new `jac` CLI command. Here's a complete example:

### Project Structure

```
my-jac-plugin/
├── pyproject.toml
└── my_jac_plugin/
    ├── __init__.py
    └── commands.jac
```

### pyproject.toml

```toml
[project]
name = "my-jac-plugin"
version = "0.1.0"
description = "My custom Jac CLI plugin"
dependencies = ["jaclang"]

[project.entry-points."jac"]
my_commands = "my_jac_plugin.commands:JacCmd"

[tool.jac.hooks]
my_commands = "create_cmd"

[tool.jac.commands.hello]
help = "Say hello from my plugin"
group = "tools"
args = [
    {name = "name", kind = "positional", default = "world", help = "Name to greet"}
]

[tool.jac.meta]
name = "my-jac-plugin"
description = "A custom Jac plugin"

[build-system]
requires = ["setuptools>=61.0"]
build-backend = "setuptools.build_meta"
```

### commands.jac

```jac
import from jaclang.jac0core.runtime { hookimpl }
import from jaclang.cli.registry { get_registry }
import from jaclang.cli.command { Arg, ArgKind, CommandPriority }

class JacCmd {
    @hookimpl
    static def create_cmd -> None {
        registry = get_registry();

        @registry.command(
            name="hello",
            help="Say hello from my plugin",
            args=[Arg.create("name", kind=ArgKind.POSITIONAL, default="world", help="Name to greet")],
            group="tools",
            priority=CommandPriority.PLUGIN,
            source="my-jac-plugin"
        )
        def hello(name: str = "world") -> int {
            print(f"Hello, {name}!");
            return 0;
        }
    }
}
```

### Install and Test

```bash
pip install -e .
jac hello Alice    # → Hello, Alice!
jac --version      # Shows "my-jac-plugin" under Plugins Detected
jac plugins list   # Lists your plugin with its distribution
```

## Plugin Anatomy

### Entry Points

Every plugin registers one or more entry points under the `"jac"` group in `pyproject.toml`:

```toml
[project.entry-points."jac"]
entry_name = "module.path:ClassName"
```

Each entry point maps a name to a class containing `@hookimpl`-decorated static methods.

### Hook Manifest (Lazy Loading)

The `[tool.jac.hooks]` section declares which hooks each entry point implements. This enables **lazy loading** -- the plugin module is not imported until one of its hooks is actually called:

```toml
[tool.jac.hooks]
my_runtime = "get_mtir,call_llm"
my_commands = "create_cmd"
my_config = "get_plugin_metadata,get_config_schema"
```

Without this section, the plugin loads eagerly at startup (backwards compatible but slower).

### Multiple Entry Points

A plugin can have multiple entry points for different concerns. This is the recommended pattern -- it keeps each module focused and ensures only the needed code loads. Here's how `byllm` does it:

```toml
[project.entry-points."jac"]
byllm = "byllm.plugin:JacRuntime"
byllm_plugin_config = "byllm.plugin_config:JacByllmPluginConfig"

[tool.jac.hooks]
byllm = "get_mtir,call_llm,by,by_operator,default_llm"
byllm_plugin_config = "get_plugin_metadata,get_config_schema,on_config_loaded,validate_config"
```

And here's `jac-client` with three entry points:

```toml
[project.entry-points."jac"]
serve = "jac_client.plugin.client:JacClient"
cli = "jac_client.plugin.cli:JacCmd"
plugin_config = "jac_client.plugin.plugin_config:JacClientPluginConfig"

[tool.jac.hooks]
serve = "get_client_bundle_builder,build_client_bundle,send_static_file,render_page,get_client_js,format_build_error"
cli = "create_cmd"
plugin_config = "get_plugin_metadata,get_config_schema,register_dependency_type,register_project_template"
```

## Available Hooks

Hooks are defined on `JacRuntimeInterface` in `jaclang/jac0core/runtime.jac`. The most commonly used categories:

### CLI Hooks

| Hook | Purpose |
|------|---------|
| `create_cmd()` | Register new CLI commands |

### Plugin Configuration Hooks

| Hook | Purpose |
|------|---------|
| `get_plugin_metadata()` | Return plugin name, version, description |
| `get_config_schema()` | Define config options for `jac.toml` |
| `on_config_loaded(config)` | React to config changes |
| `validate_config(config)` | Validate plugin configuration |
| `register_dependency_type()` | Register custom dependency types (e.g., npm) |
| `register_project_template()` | Register templates for `jac create --use` |

### Runtime Hooks

| Hook | Purpose |
|------|---------|
| `create_server()` | Provide custom server implementation |
| `create_j_context()` | Provide custom execution context |
| `get_user_manager()` | Provide user management |
| `store()` | Provide storage backend |
| `get_console()` | Override console output |
| `get_mtir()` | Provide MTIR for meaning-typed programming |
| `call_llm()` | Invoke LLM models |
| `default_llm()` | Return default LLM model |
| `by()` | Decorator for `by llm()` syntax |
| `by_operator()` | LLM-guided routing operator |

### Hook Dispatch

Hooks use **first-result** dispatch -- the first non-`None` return value wins. The core `JacRuntimeImpl` provides default implementations for all hooks. Your plugin's implementation takes priority over the defaults.

## Plugin Configuration

### Metadata

Return plugin info so `jac plugins list` can display it. Here's how `byllm` does it:

```jac
class JacByllmPluginConfig {
    @hookimpl
    static def get_plugin_metadata -> dict[str, Any] {
        return {
            "name": "byllm",
            "version": "0.4.8",
            "description": "byLLM - Easy to use APIs for LLM providers with Jaclang"
        };
    }
}
```

### Config Schema

Define options that users set in `jac.toml` under `[plugins.<section>]`. Here's a real example from `byllm`:

```jac
class JacByllmPluginConfig {
    @hookimpl
    static def get_config_schema -> dict[str, Any] {
        return {
            "section": "byllm",
            "options": {
                "model": {
                    "type": "dict",
                    "nested": {
                        "default_model": {"type": "string", "default": "gpt-4o-mini"},
                        "api_key": {"type": "string"},
                        "verbose": {"type": "bool", "default": False}
                    }
                },
                "call_params": {
                    "type": "dict",
                    "nested": {
                        "temperature": {"type": "float", "default": 0.7},
                        "max_tokens": {"type": "int", "default": 0}
                    }
                },
                "system_prompt": {"type": "string", "default": ""}
            }
        };
    }
}
```

Users then configure in `jac.toml`:

```toml
[plugins.byllm]
system_prompt = "You are a helpful assistant."

[plugins.byllm.model]
default_model = "gpt-4o"
api_key = "sk-..."

[plugins.byllm.call_params]
temperature = 0.5
```

## CLI Commands

### Registering New Commands

Use `@registry.command()` inside `create_cmd` to add new CLI commands:

```jac
class JacCmd {
    @hookimpl
    static def create_cmd -> None {
        registry = get_registry();

        @registry.command(
            name="deploy",
            help="Deploy application to cloud",
            args=[
                Arg.create("target", kind=ArgKind.POSITIONAL, help="Deployment target"),
                Arg.create("region", default="us-east-1", help="Cloud region"),
                Arg.create("dry-run", kind=ArgKind.FLAG, short="n", help="Preview without deploying")
            ],
            group="deployment",
            priority=CommandPriority.PLUGIN,
            source="my-plugin"
        )
        def deploy(target: str, region: str = "us-east-1", dry_run: bool = False) -> int {
            print(f"Deploying to {target} in {region}");
            return 0;
        }
    }
}
```

### Extending Existing Commands

Add flags to built-in commands without replacing them. Here's how `jac-scale` extends the `start` command:

```jac
class JacCmd {
    @hookimpl
    static def create_cmd -> None {
        registry = get_registry();

        registry.extend_command(
            "start",
            args=[
                Arg.create("scale", typ=bool, help="Deploy to target platform"),
                Arg.create("build", typ=bool, help="Build Docker image"),
                Arg.create("target", typ=str, default="kubernetes")
            ],
            pre_hook=_scale_pre_hook,
            source="jac-scale"
        );
    }
}
```

And `jac-client` extends `add` and `remove` with `--npm` support:

```jac
registry.extend_command(
    command_name="add",
    args=[Arg.create("npm", kind=ArgKind.FLAG, help="Add npm packages")],
    pre_hook=_handle_npm_add,
    source="jac-client"
);
```

### Declarative CLI Commands

Instead of loading your plugin just to register commands, declare them in TOML metadata. The commands appear in `jac --help` without importing your code:

```toml
[tool.jac.commands.deploy]
help = "Deploy application to cloud"
group = "deployment"
args = [
    {name = "target", kind = "positional", help = "Deployment target"},
    {name = "region", default = "us-east-1", help = "Cloud region"},
    {name = "dry-run", kind = "flag", short = "n", help = "Preview without deploying"},
]
```

Your plugin only loads when the user actually runs `jac deploy`.

## Runtime Hooks

Plugins can override core runtime behavior. Here's how `jac-scale` provides a custom execution context and server:

```jac
class JacScalePlugin {
    @hookimpl
    static def create_j_context(user_root: (str | None)) -> ExecutionContext {
        ctx = JScaleExecutionContext();
        if user_root is not None {
            ctx.set_user_root(user_root);
        }
        return ctx;
    }

    @hookimpl
    static def create_server(
        jac_server: JacServer, host: str, port: int
    ) -> JFastApiServer {
        return JFastApiServer([]);
    }

    @hookimpl
    static def store(
        base_path: str = "./storage", create_dirs: bool = True
    ) -> Storage {
        import from .factories.storage_factory { StorageFactory }
        return StorageFactory.get_default(base_path, create_dirs);
    }
}
```

And here's how `byllm` implements LLM hooks:

```jac
class JacRuntime {
    @hookimpl
    static def get_mtir(caller: Callable, args: dict, call_params: dict) -> object {
        import from byllm.mtir { MTIR }
        return MTIR(caller, args, call_params, fetch_mtir(caller)).runtime;
    }

    @hookimpl
    static def call_llm(model: Model, mt_run: MTRuntime) -> object {
        return model.invoke(mt_run=mt_run);
    }

    @hookimpl
    static def default_llm -> object {
        # Returns the model configured in jac.toml [plugins.byllm.model]
        ...
    }
}
```

## Custom Dependency Types

Register package managers beyond pip. Here's how `jac-client` registers npm:

```jac
class JacClientPluginConfig {
    @hookimpl
    static def register_dependency_type -> dict[str, Any] {
        return {
            "name": "npm",
            "dev_name": "npm.dev",
            "cli_flag": "--npm",
            "install_dir": ".jac/client/configs",
            "install_handler": _npm_install_handler,
            "install_all_handler": _npm_install_all_handler,
            "remove_handler": _npm_remove_handler
        };
    }
}
```

Users manage dependencies with: `jac add --npm react react-dom`

## Project Templates

Register templates for `jac create`. Here's how `jac-client` registers multiple templates:

```jac
class JacClientPluginConfig {
    @hookimpl
    static def register_project_template -> list[dict[str, Any]] {
        templates: list[dict[str, Any]] = [];
        for template_name in ["client", "fullstack"] {
            template = _load_template(template_name);
            if template {
                templates.append(template);
            }
        }
        return templates;
    }
}
```

Users create projects with: `jac create myapp --use client`

## Disabling Plugins

Users can disable plugins via environment variable or `jac.toml`:

```bash
# Disable specific plugins
export JAC_DISABLED_PLUGINS="my-plugin,other-plugin"

# Disable all external plugins
export JAC_DISABLED_PLUGINS="*"
```

Or in `jac.toml`:

```toml
[plugins]
disabled = ["my-plugin"]
```

Manage via CLI:

```bash
jac plugins disable my-plugin
jac plugins enable my-plugin
jac plugins disabled          # List disabled plugins
```

## Testing

### Testing Without External Plugins

Use the `without_plugins()` context manager to isolate tests:

```jac
import from jaclang.jac0core.runtime { without_plugins }

test "my feature works without plugins" {
    with without_plugins() {
        # Only core JacRuntimeImpl is active
        result = do_something();
        assert result == expected;
    }
}
```

### Testing Your Plugin

Create a `PluginManager` instance and register your plugin directly:

```jac
import from jaclang.jac0core.plugin { PluginManager }

test "my hook works" {
    pm = PluginManager("test");
    pm.register(CoreImpl);       # Register a minimal core
    pm.register(MyPlugin);       # Register your plugin

    result = pm.hook.my_hook();
    assert result == expected;
}
```

## Writing Plugins in Python

While Jac is recommended, plugins can also be written in Python. The key difference is that Python uses `@staticmethod` and `@hookimpl` as separate decorators:

### commands.py

```python
from jaclang.jac0core.runtime import hookimpl
from jaclang.cli.registry import get_registry
from jaclang.cli.command import Arg, ArgKind, CommandPriority


class JacCmd:
    @staticmethod
    @hookimpl
    def create_cmd() -> None:
        registry = get_registry()

        @registry.command(
            name="hello",
            help="Say hello from my plugin",
            args=[
                Arg.create("name", kind=ArgKind.POSITIONAL,
                           default="world", help="Name to greet"),
            ],
            group="tools",
            priority=CommandPriority.PLUGIN,
            source="my-jac-plugin",
        )
        def hello(name: str = "world") -> int:
            print(f"Hello, {name}!")
            return 0
```

Note the decorator difference: Python uses `@staticmethod @hookimpl` while Jac uses `@hookimpl static def`.

## Best Practices

1. **Use lazy loading** --Always include `[tool.jac.hooks]` in your `pyproject.toml`. This keeps `import jaclang` fast.

2. **Declare commands in TOML** --Use `[tool.jac.commands]` so commands appear in `jac --help` without importing your plugin.

3. **Split entry points by concern** --Separate runtime hooks, CLI hooks, and config hooks into different entry points so only the needed code loads. See how `byllm` and `jac-client` split their entry points.

4. **Provide metadata** --Implement `get_plugin_metadata()` and `get_config_schema()` so your plugin integrates with `jac plugins list` and `jac.toml`.

5. **Handle missing dependencies gracefully** --Wrap optional imports in try/except so the plugin system stays robust.

6. **Use `source` in commands** --Set the `source` parameter in `registry.command()` so `jac plugins list` can show which commands your plugin provides.

## Real-World Plugin Examples

These production plugins in the Jaseci repository serve as excellent references:

| Plugin | Description | Source |
|--------|-------------|--------|
| **byllm** | LLM integration (`call_llm`, `get_mtir`, `by` syntax) | [jac-byllm/](https://github.com/Jaseci-Labs/jaseci/tree/main/jac-byllm) |
| **jac-client** | Full-stack web with Vite bundling, npm deps, project templates | [jac-client/](https://github.com/Jaseci-Labs/jaseci/tree/main/jac-client) |
| **jac-scale** | Kubernetes deployment, custom server/context/storage | [jac-scale/](https://github.com/Jaseci-Labs/jaseci/tree/main/jac-scale) |
| **jac-mcp** | Model Context Protocol server for AI-assisted Jac development | [jac-mcp/](https://github.com/Jaseci-Labs/jaseci/tree/main/jac-mcp) |
| **cmd-show** | Simple CLI command example (Python) | [jac/examples/plugins/cmd_show/](https://github.com/Jaseci-Labs/jaseci/tree/main/jac/examples/plugins/cmd_show) |

Key files to study in each plugin:

- `pyproject.toml` --Entry points and `[tool.jac.hooks]` manifest
- `plugin.jac` --Runtime hook implementations (`@hookimpl static def`)
- `plugin_config.jac` --Metadata, config schema, dependency types, templates
- `cli.jac` --CLI command registration and extensions
