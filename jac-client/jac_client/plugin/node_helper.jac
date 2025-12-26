"""Node.js helper utilities for Jac Client.

This module provides functions for detecting, validating, and installing
Node.js and npm for client-side development.
"""

import os;
import sys;
import shutil;
import platform;
import subprocess;

"""Check if Node.js and npm are available.

Returns:
    Tuple of (success, node_version, npm_version).
    If not installed, returns (False, None, None).
"""
def check_nodejs_installed -> tuple {
    node_version = None;
    npm_version = None;

    # Check for node
    node_path = shutil.which("node");
    if not node_path {
        return (False, None, None);
    }

    # Get node version
    try {
        result = subprocess.run(
            ["node", "--version"], capture_output=True, text=True, timeout=10
        );
        if result.returncode == 0 {
            node_version = result.stdout.strip();
        }
    } except Exception {
        return (False, None, None);
    }

    # Check for npm
    npm_path = shutil.which("npm");
    if not npm_path {
        return (False, node_version, None);
    }

    # Get npm version
    try {
        result = subprocess.run(
            ["npm", "--version"], capture_output=True, text=True, timeout=10
        );
        if result.returncode == 0 {
            npm_version = result.stdout.strip();
        }
    } except Exception {
        return (False, node_version, None);
    }

    return (True, node_version, npm_version);
}

"""Get platform-specific Node.js installation instructions."""
def get_nodejs_install_instructions -> str {
    system = platform.system().lower();

    header = '''
Node.js is required for Jac client-side development.

Installation options:
''';

    footer = '''
After installation, restart your terminal and try again.

Or use: jac create --cl --setup-node <name>
to automatically install Node.js via nvm.
''';

    if system == "darwin" {
        # macOS
        return header + '''
  Using Homebrew (recommended):
    brew install node

  Using the official installer:
    https://nodejs.org/en/download

  Using nvm (Node Version Manager):
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    nvm install --lts
''' + footer;
    } elif system == "linux" {
        # Linux
        return header + '''
  Using nvm (recommended):
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    nvm install --lts

  Using apt (Debian/Ubuntu):
    sudo apt update && sudo apt install nodejs npm

  Using dnf (Fedora):
    sudo dnf install nodejs npm

  Official downloads:
    https://nodejs.org/en/download
''' + footer;
    } elif system == "windows" {
        # Windows
        return header + '''
  Using the official installer (recommended):
    https://nodejs.org/en/download

  Using winget:
    winget install OpenJS.NodeJS.LTS

  Using Chocolatey:
    choco install nodejs-lts

  Using nvm-windows:
    https://github.com/coreybutler/nvm-windows
''' + footer;
    } else {
        # Generic
        return header + '''
  Official downloads:
    https://nodejs.org/en/download

  Using nvm (Node Version Manager):
    https://github.com/nvm-sh/nvm
''' + footer;
    }
}

"""Install Node.js using nvm (Node Version Manager).

This function downloads and runs the nvm install script, then installs
the LTS version of Node.js. Works on Linux and macOS.

Returns:
    True if installation succeeded, False otherwise.
"""
def setup_nodejs_with_nvm -> bool {
    system = platform.system().lower();

    if system == "windows" {
        print("Automatic Node.js setup is not supported on Windows.", file=sys.stderr);
        print(
            "Please install Node.js manually from: https://nodejs.org/en/download",
            file=sys.stderr
        );
        return False;
    }

    if system not in ["linux", "darwin"] {
        print(
            f"Automatic Node.js setup is not supported on {system}.", file=sys.stderr
        );
        return False;
    }

    print("Setting up Node.js via nvm (Node Version Manager)...");
    print("");

    # Determine shell config file
    shell = os.environ.get("SHELL", "/bin/bash");
    home = os.path.expanduser("~");

    if "zsh" in shell {
        shell_rc = os.path.join(home, ".zshrc");
    } else {
        shell_rc = os.path.join(home, ".bashrc");
    }

    nvm_dir = os.path.join(home, ".nvm");

    # Check if nvm is already installed
    if os.path.exists(nvm_dir) {
        print(f"nvm is already installed at {nvm_dir}");
    } else {
        # Download and run the nvm install script
        print("Downloading nvm install script...");
        nvm_install_url = "https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh";
        try {
            # Download the script
            curl_result = subprocess.run(
                ["curl", "-fsSL", nvm_install_url],
                capture_output=True,
                text=True,
                timeout=60
            );

            if curl_result.returncode != 0 {
                print("Failed to download nvm install script.", file=sys.stderr);
                print(f"Error: {curl_result.stderr}", file=sys.stderr);
                return False;
            }

            # Run the install script
            print("Installing nvm...");
            install_result = subprocess.run(
                ["bash"],
                input=curl_result.stdout,
                capture_output=True,
                text=True,
                timeout=120
            );

            if install_result.returncode != 0 {
                print("Failed to install nvm.", file=sys.stderr);
                print(f"Error: {install_result.stderr}", file=sys.stderr);
                return False;
            }

            print("nvm installed successfully!");
        } except subprocess.TimeoutExpired {
            print("Installation timed out.", file=sys.stderr);
            return False;
        } except FileNotFoundError {
            print("curl not found. Please install curl first.", file=sys.stderr);
            return False;
        } except Exception as e {
            print(f"Failed to install nvm: {e}", file=sys.stderr);
            return False;
        }
    }

    # Source nvm and install Node.js LTS
    print("Installing Node.js LTS...");

    # Build the command to source nvm and install node
    nvm_source = f'''
export NVM_DIR="{nvm_dir}"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
nvm install --lts
nvm use --lts
''';

    try {
        result = subprocess.run(
            ["bash", "-c", nvm_source], capture_output=True, text=True, timeout=300
        );

        if result.returncode != 0 {
            print("Failed to install Node.js.", file=sys.stderr);
            print(f"Error: {result.stderr}", file=sys.stderr);
            return False;
        }

        print(result.stdout);
        print("");
        print("Node.js installed successfully!");
    } except subprocess.TimeoutExpired {
        print("Node.js installation timed out.", file=sys.stderr);
        return False;
    } except Exception as e {
        print(f"Failed to install Node.js: {e}", file=sys.stderr);
        return False;
    }

    # Check if shell config has nvm sourcing
    nvm_source_line = 'export NVM_DIR="$HOME/.nvm"';
    needs_shell_update = True;

    if os.path.exists(shell_rc) {
        with open(shell_rc, "r") as f {
            if nvm_source_line in f.read() {
                needs_shell_update = False;
            }
        }
    }

    if needs_shell_update {
        print(f"\nNote: nvm has been added to {shell_rc}");
        print("To use Node.js in this terminal session, run:");
        print(f'  source {shell_rc}');
        print("");
    }

    # Set up environment for current process
    os.environ["NVM_DIR"] = nvm_dir;

    # Find the installed node binary
    node_versions_dir = os.path.join(nvm_dir, "versions", "node");
    if os.path.exists(node_versions_dir) {
        versions = os.listdir(node_versions_dir);
        if versions {
            # Get the latest version
            versions.sort(reverse=True);
            latest = versions[0];
            node_bin = os.path.join(node_versions_dir, latest, "bin");
            # Add to PATH for current process
            current_path = os.environ.get("PATH", "");
            os.environ["PATH"] = f"{node_bin}:{current_path}";
            print(f"Node.js {latest} is now available in this session.");
        }
    }

    return True;
}
