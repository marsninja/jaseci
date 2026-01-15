"""Command line interface tool for the Jac Client.

This module extends the core `create` command to add the --cl flag for
client-side (frontend) project setup. When --cl is used, it delegates to
the core create command with template="client".
"""

import sys;
import from jaclang.cli.registry { get_registry }
import from jaclang.cli.command { Arg, HookContext }
import from jaclang.pycore.runtime { hookimpl }

"""Jac CLI extensions for client-side development."""
class JacCmd {
    """Create Jac CLI cmds."""
    @hookimpl
    static def create_cmd -> None {
        """Extend core create command to add --cl flag for client-side setup.""";
        registry = get_registry();

        # Extend the core 'create' command with --cl flag
        # This is a shorthand for --template client
        registry.extend_command(
            command_name="create",
            args=[
                Arg.create(
                    "cl",
                    typ=bool,
                    default=False,
                    help="Use the client template (shorthand for --template client)",
                    short="c"
                ),

            ],
            pre_hook=_handle_client_create,
            source="jac-client"
        );
    }
}

"""Pre-hook to handle --cl flag for client-side project creation."""
def _handle_client_create(ctx: HookContext) -> None {
    # Check if --cl flag is set
    cl_flag = ctx.get_arg("cl", False);
    if not cl_flag {
        # Let core create command run normally
        return;
    }

    # Check if template is already set to something other than default
    template = ctx.get_arg("template", "default");
    if template != "default" {
        # User explicitly set --template, respect that over --cl
        return;
    }

    # --cl is set, delegate to core create with template="client"
    # Use Python's importlib to import the compiled Jac module
    import importlib;
    project_module = importlib.import_module("jaclang.cli.commands.project");
    create_fn = getattr(project_module, "create");

    name = ctx.get_arg("name", "");
    force = ctx.get_arg("force", False);
    list_templates = ctx.get_arg("list_templates", False);

    try {
        result = create_fn(
            name=name, force=force, template="client", list_templates=list_templates
        );
        # Cancel core handler since we called create ourselves
        ctx.set_data("cancel_execution", True);
        ctx.set_data("cancel_return_code", result);
    } except SystemExit as e {
        ctx.set_data("cancel_execution", True);
        ctx.set_data("cancel_return_code", e.code if e.code is not None else 1);
    } except Exception as e {
        print(f"Error creating client project: {e}", file=sys.stderr);
        ctx.set_data("cancel_execution", True);
        ctx.set_data("cancel_return_code", 1);
    }
}
