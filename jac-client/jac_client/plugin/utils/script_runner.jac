"""Script runner for executing package.json scripts and node_modules/.bin commands.

Replaces `bun run <script>` and `bun x <cmd>` functionality.
"""

"""Run a script defined in package.json.

Reads the 'scripts' section of package.json and executes the named script
with node_modules/.bin prepended to PATH.
Returns the subprocess result.
"""
def run_script(
    script_name: str,
    package_json_path: object,
    cwd: (object | None) = None,
    check: bool = False,
    capture_output: bool = False,
    text: bool = True,
    timeout: (int | None) = None
) -> object;

"""Run a binary from node_modules/.bin/.

Finds the binary in the given node_modules directory and executes it
with the provided arguments. Uses Node.js to run if needed.
Returns the subprocess CompletedProcess or Popen depending on popen mode.
"""
def run_bin(
    bin_name: str,
    args: list[str],
    node_modules_dir: object,
    cwd: (object | None) = None,
    check: bool = False,
    capture_output: bool = False,
    text: bool = True,
    timeout: (int | None) = None,
    as_popen: bool = False,
    stdout: object = None,
    stderr: object = None
) -> object;
