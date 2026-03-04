"""Node.js runtime manager for jac-client.

Ensures a Node.js runtime is available, either from the system PATH
or from the nodejs-wheel pip package.
Replaces bun_installer.jac.
"""

"""Check if Node.js is available, using nodejs-wheel or system node.

Returns True if node is available, False otherwise.
"""
def ensure_node_available -> bool;

"""Get the path to the Node.js binary.

Returns the full path to node, or None if not found.
"""
def get_node_path -> (str | None);
