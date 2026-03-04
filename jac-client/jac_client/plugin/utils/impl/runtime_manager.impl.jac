"""Implementation of Node.js runtime manager."""

"""Check if Node.js is available, using nodejs-wheel or system node."""
impl ensure_node_available -> bool {
    import shutil;
    import subprocess;
    import from jaclang.cli.console { console }

    # 1. Check if node is already in PATH
    if shutil.which("node") {
        return True;
    }

    # 2. Try nodejs-wheel pip package
    try {
        import nodejs.node;
        # nodejs-wheel provides node binary, add its location to PATH
        import os;
        node_dir = os.path.dirname(nodejs.node.__file__);
        # The binary is exposed via the package entry point
        bin_dir = os.path.join(os.path.dirname(node_dir), "bin");
        if os.path.exists(bin_dir) {
            os.environ["PATH"] = f"{bin_dir}:{os.environ.get('PATH', '')}";
            if shutil.which("node") {
                return True;
            }
        }
        # Try the nodejs package's own path resolution
        try {
            import nodejs;
            node_path = getattr(nodejs, 'node_path', None);
            if node_path and os.path.exists(node_path) {
                node_bin_dir = os.path.dirname(node_path);
                os.environ["PATH"] = f"{node_bin_dir}:{os.environ.get('PATH', '')}";
                return True;
            }
        } except Exception {
            ;
        }
    } except ImportError {
        ;  # nodejs-wheel not installed
    }

    # 3. Check common Node.js installation paths
    import os;
    common_paths = [
        os.path.expanduser("~/.nvm/versions/node"),
        "/usr/local/bin/node",
        "/usr/bin/node"
    ];

    for path in common_paths {
        if path.endswith("/node") and os.path.exists(path) {
            bin_dir = os.path.dirname(path);
            os.environ["PATH"] = f"{bin_dir}:{os.environ.get('PATH', '')}";
            return True;
        }
        # For nvm, find the latest installed version
        if "nvm" in path and os.path.isdir(path) {
            try {
                versions = sorted(os.listdir(path), reverse=True);
                for v in versions {
                    node_bin = os.path.join(path, v, "bin", "node");
                    if os.path.exists(node_bin) {
                        bin_dir = os.path.dirname(node_bin);
                        os.environ["PATH"] = f"{bin_dir}:{os.environ.get('PATH', '')}";
                        return True;
                    }
                }
            } except Exception {
                ;
            }
        }
    }

    # 4. Node not found - prompt to install nodejs-wheel
    console.error("\n  Node.js is required but not found.");
    console.error("  Install it via: pip install nodejs-wheel");
    console.error("  Or install Node.js from: https://nodejs.org\n");

    try {
        response = input("  Install nodejs-wheel via pip now? [Y/n]: ").strip().lower();
    } except (EOFError, KeyboardInterrupt) {
        console.error("");
        return False;
    }
    if response and response not in ('y', 'yes', '') {
        return False;
    }

    console.print("\n  Installing nodejs-wheel...");
    try {
        result = subprocess.run(
            [shutil.which("pip") or "pip", "install", "nodejs-wheel"],
            timeout=120,
            check=False,
            capture_output=True,
            text=True
        );
        if result.returncode == 0 {
            console.print("  Installed nodejs-wheel successfully!");
            # Try again after install
            return ensure_node_available();
        } else {
            console.error(f"  Failed to install nodejs-wheel: {result.stderr}");
            return False;
        }
    } except Exception as e {
        console.error(f"  Installation failed: {e}");
        return False;
    }
}

"""Get the path to the Node.js binary."""
impl get_node_path -> (str | None) {
    import shutil;

    node_bin = shutil.which("node");
    if node_bin {
        return node_bin;
    }

    # Try to ensure it's available first
    if ensure_node_available() {
        return shutil.which("node");
    }

    return None;
}
