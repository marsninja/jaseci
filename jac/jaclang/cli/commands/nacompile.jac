import from jaclang.cli.command { Arg, ArgKind }
import from jaclang.cli.registry { get_registry }

glob registry = get_registry();

def nacompile(
    filename: str,
    output: str = "",
    scrub: bool = False,
    target: str = "",
    shared: bool = False,
    debug: bool = False
) -> int;
