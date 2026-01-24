"""Implementation of Node.js and bun installer methods."""

"""Check if Node.js is installed and accessible."""
impl NodeInstaller.is_node_installed -> bool {
    try {
        result = subprocess.run(
            ['node', '--version'], capture_output=True, text=True, timeout=5
        );
        return result.returncode == 0;
    } except (FileNotFoundError, subprocess.TimeoutExpired) {
        return False;
    }
}

"""Check if npm is installed and accessible."""
impl NodeInstaller.is_npm_installed -> bool {
    try {
        result = subprocess.run(
            ['npm', '--version'], capture_output=True, text=True, timeout=5
        );
        return result.returncode == 0;
    } except (FileNotFoundError, subprocess.TimeoutExpired) {
        return False;
    }
}

"""Check if bun is installed and accessible."""
impl NodeInstaller.is_bun_installed -> bool {
    try {
        result = subprocess.run(
            ['bun', '--version'], capture_output=True, text=True, timeout=5
        );
        return result.returncode == 0;
    } except (FileNotFoundError, subprocess.TimeoutExpired) {
        # Also check common bun install location
        bun_path = Path.home() / '.bun' / 'bin' / 'bun';
        if bun_path.exists() {
            try {
                result = subprocess.run(
                    [str(bun_path), '--version'],
                    capture_output=True,
                    text=True,
                    timeout=5
                );
                return result.returncode == 0;
            } except (FileNotFoundError, subprocess.TimeoutExpired) {
                return False;
            }
        }
        return False;
    }
}

"""Check if NVM is installed."""
impl NodeInstaller.is_nvm_installed -> bool {
    nvm_dir = Path.home() / '.nvm';
    return nvm_dir.exists() and (nvm_dir / 'nvm.sh').exists();
}

"""Get the currently installed Node.js version."""
impl NodeInstaller.get_node_version -> (str | None) {
    try {
        result = subprocess.run(
            ['node', '--version'], capture_output=True, text=True, timeout=5
        );
        if result.returncode == 0 {
            return result.stdout.strip();
        }
    } except (FileNotFoundError, subprocess.TimeoutExpired) { }
    return None;
}

"""Get the currently installed bun version."""
impl NodeInstaller.get_bun_version -> (str | None) {
    try {
        result = subprocess.run(
            ['bun', '--version'], capture_output=True, text=True, timeout=5
        );
        if result.returncode == 0 {
            return result.stdout.strip();
        }
    } except (FileNotFoundError, subprocess.TimeoutExpired) {
        # Also check common bun install location
        bun_path = Path.home() / '.bun' / 'bin' / 'bun';
        if bun_path.exists() {
            try {
                result = subprocess.run(
                    [str(bun_path), '--version'],
                    capture_output=True,
                    text=True,
                    timeout=5
                );
                if result.returncode == 0 {
                    return result.stdout.strip();
                }
            } except (FileNotFoundError, subprocess.TimeoutExpired) { }
        }
    }
    return None;
}

"""Install NVM (Node Version Manager)."""
impl NodeInstaller.install_nvm -> tuple[bool, str] {
    system = platform.system();
    if system == 'Windows' {
        return (
            False,
            'Windows detected. Please install Node.js manually:\n' + '  1. Download from: https://nodejs.org/\n' + '  2. Or use nvm-windows: https://github.com/coreybutler/nvm-windows\n' + '  After installation, run "jac add --cl" again.'
        );
    }
    print('Installing NVM (Node Version Manager)...');
    try {
        # Download and run NVM installation script
        install_script = subprocess.run(
            ['curl', '-o-', NodeInstaller.NVM_INSTALL_URL],
            capture_output=True,
            text=True,
            timeout=30
        );

        if install_script.returncode != 0 {
            return (
                False,
                f'Failed to download NVM installer: {install_script.stderr}'
            );
        }

        # Execute the installation script
        result = subprocess.run(
            ['bash', '-c', install_script.stdout],
            capture_output=True,
            text=True,
            timeout=60
        );

        if result.returncode != 0 {
            return (False, f'NVM installation failed: {result.stderr}');
        }

        print('NVM installed successfully!');
        return (True, 'NVM installed successfully');
    } except subprocess.TimeoutExpired {
        return (
            False,
            'NVM installation timed out. Please check your internet connection.'
        );
    } except FileNotFoundError as e {
        if 'curl' in str(e) {
            return (
                False,
                'curl command not found. Please install curl first:\n' + '  Ubuntu/Debian: sudo apt-get install curl\n' + '  macOS: curl is pre-installed\n' + '  Fedora/RHEL: sudo dnf install curl'
            );
        }
        return (False, f'Required command not found: {e}');
    } except Exception as e {
        return (False, f'Unexpected error during NVM installation: {e}');
    }
}

"""Install bun using the official install script."""
impl NodeInstaller.install_bun -> tuple[bool, str] {
    system = platform.system();
    if system == 'Windows' {
        return (
            False,
            'Windows detected. Please install bun manually:\n' + '  Run in PowerShell: irm bun.sh/install.ps1 | iex\n' + '  Or download from: https://bun.sh/\n' + '  After installation, run your command again.'
        );
    }
    print('Installing bun...');
    try {
        # Download and run bun installation script
        # The bun install script: curl -fsSL https://bun.sh/install | bash
        install_script = subprocess.run(
            ['curl', '-fsSL', NodeInstaller.BUN_INSTALL_URL],
            capture_output=True,
            text=True,
            timeout=30
        );

        if install_script.returncode != 0 {
            return (
                False,
                f'Failed to download bun installer: {install_script.stderr}'
            );
        }

        # Execute the installation script
        result = subprocess.run(
            ['bash', '-c', install_script.stdout],
            capture_output=True,
            text=True,
            timeout=120
        );

        if result.returncode != 0 {
            return (False, f'bun installation failed: {result.stderr}');
        }

        print('bun installed successfully!');
        return (True, 'bun installed successfully');
    } except subprocess.TimeoutExpired {
        return (
            False,
            'bun installation timed out. Please check your internet connection.'
        );
    } except FileNotFoundError as e {
        if 'curl' in str(e) {
            return (
                False,
                'curl command not found. Please install curl first:\n' + '  Ubuntu/Debian: sudo apt-get install curl\n' + '  macOS: curl is pre-installed\n' + '  Fedora/RHEL: sudo dnf install curl'
            );
        }
        return (False, f'Required command not found: {e}');
    } except Exception as e {
        return (False, f'Unexpected error during bun installation: {e}');
    }
}

"""Install Node.js using NVM."""
impl NodeInstaller.install_node_via_nvm(version: str = "20") -> tuple[bool, str] {
    print(f'Installing Node.js v{version} via NVM...');
    nvm_dir = Path.home() / '.nvm';
    nvm_script = nvm_dir / 'nvm.sh';
    if not nvm_script.exists() {
        return (False, 'NVM is not installed or nvm.sh not found');
    }
    try {
        # Source NVM and install Node.js
        command = (
            'export NVM_DIR="$HOME/.nvm"\n' + '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"\n' + f'nvm install {version}\n' + f'nvm use {version}\n' + f'nvm alias default {version}\n'
        );

        result = subprocess.run(
            ['bash', '-c', command], capture_output=True, text=True, timeout=300
        );

        if result.returncode != 0 {
            return (False, f'Node.js installation failed: {result.stderr}');
        }

        print(f'Node.js v{version} installed successfully!');
        return (True, f'Node.js v{version} installed successfully');
    } except subprocess.TimeoutExpired {
        return (False, 'Node.js installation timed out. Please try again.');
    } except Exception as e {
        return (False, f'Unexpected error during Node.js installation: {e}');
    }
}

"""Ensure Node.js is installed, installing automatically if needed.

Returns tuple of (success: bool, message: str, was_just_installed: bool)
"""
impl NodeInstaller.ensure_node_installed(
    interactive: bool = True
) -> tuple[bool, str, bool] {
    # Common fallback message for manual installation
    manual_install_msg = (
        'Please install Node.js manually:\n' + '  • Download from: https://nodejs.org/\n' + '  • Or install NVM: https://github.com/nvm-sh/nvm\n' + '  After installation, run "jac add --cl" again.'
    );
    # Check if Node.js is already available
    if NodeInstaller.is_node_installed() and NodeInstaller.is_npm_installed() {
        version = NodeInstaller.get_node_version();
        return (True, f'Node.js {version} is already installed', False);
    }
    print('\nNode.js is not installed or not found in PATH.');
    # Check for interactive mode
    if interactive {
        print(
            '\nJac client requires Node.js to build and run client-side applications.'
        );
        print(
            f'Would you like to automatically install Node.js v{NodeInstaller.DEFAULT_NODE_VERSION} using NVM?'
        );
        response = input('Install Node.js? [Y/n]: ').strip().lower();
        if response and response not in ('y', 'yes') {
            return (
                False,
                f'Node.js installation cancelled. {manual_install_msg}',
                False
            );
        }
    }
    # Wrap entire installation process in error handling
    try {
        # Check if NVM is installed
        if not NodeInstaller.is_nvm_installed() {
            success_nvm = NodeInstaller.install_nvm();
            if not success_nvm[0] {
                return (
                    False,
                    f'Unable to automatically install Node.js.\n\nError: {success_nvm[
                        1
                    ]}\n\n{manual_install_msg}',
                    False
                );
            }
        }

        # Install Node.js via NVM
        success_node = NodeInstaller.install_node_via_nvm();
        if not success_node[0] {
            return (
                False,
                f'Unable to automatically install Node.js.\n\nError: {success_node[1]}\n\n{manual_install_msg}',
                False
            );
        }

        # Node.js is now available via NVM sourcing in subprocesses
        print('\n' + '=' * 70);
        print('Node.js has been installed successfully!');
        print('Continuing with package installation...');
        print('=' * 70 + '\n');

        return (
            True,
            f'Node.js {NodeInstaller.DEFAULT_NODE_VERSION} installed successfully',
            True
        );
    } except Exception as e {
        # Catch any unexpected errors during installation
        return (
            False,
            f'Unable to automatically install Node.js.\n\nUnexpected error: {str(e)}\n\n{manual_install_msg}',
            False
        );
    }
}

"""Run npm command with NVM environment properly sourced.

This method automatically sources NVM in a subprocess, so npm commands work
immediately after NVM installation without requiring the user to reload their shell.
"""
impl NodeInstaller.run_npm_with_nvm(
    args: list, cwd: Path, timeout: int = 300
) -> object {
    # First, try running npm directly (in case it's already in PATH)
    try {
        return subprocess.run(
            ['npm'] + args,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=True
        );
    } except FileNotFoundError { }
    # If npm is not in PATH, source NVM and run npm in a subprocess
    # This allows npm to work immediately after installation without shell reload
    args_str = ' '.join(args);
    command = (
        'export NVM_DIR="$HOME/.nvm"\n' + '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"\n' + f'npm {args_str}\n'
    );
    return subprocess.run(
        ['bash', '-c', command],
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=True
    );
}

"""Run bun command with proper PATH (handles ~/.bun/bin).

This method adds the bun bin directory to PATH, so bun commands work
immediately after installation without requiring the user to reload their shell.
"""
impl NodeInstaller.run_bun_with_path(
    args: list, cwd: Path, timeout: int = 300
) -> object {
    # First, try running bun directly (in case it's already in PATH)
    try {
        return subprocess.run(
            ['bun'] + args,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=True
        );
    } except FileNotFoundError { }
    # If bun is not in PATH, check common install location
    bun_bin = Path.home() / '.bun' / 'bin';
    bun_path = bun_bin / 'bun';
    if bun_path.exists() {
        return subprocess.run(
            [str(bun_path)] + args,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=True
        );
    }
    # Fall back to running via bash with PATH set
    args_str = ' '.join(args);
    command = f'export PATH="$HOME/.bun/bin:$PATH"\n' + f'bun {args_str}\n';
    return subprocess.run(
        ['bash', '-c', command],
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=True
    );
}

"""Ensure bun is installed, installing automatically if needed.

Returns tuple of (success: bool, message: str, was_just_installed: bool)
"""
impl NodeInstaller.ensure_bun_installed(
    interactive: bool = True
) -> tuple[bool, str, bool] {
    # Common fallback message for manual installation
    manual_install_msg = (
        'Please install bun manually:\n' + '  • Run: curl -fsSL https://bun.sh/install | bash\n' + '  • Or visit: https://bun.sh/\n' + '  After installation, run your command again.'
    );
    # Check if bun is already available
    if NodeInstaller.is_bun_installed() {
        version = NodeInstaller.get_bun_version();
        return (True, f'bun {version} is already installed', False);
    }
    print('\nbun is not installed or not found in PATH.');
    # Check for interactive mode
    if interactive {
        print('\nbun is a fast JavaScript runtime and package manager.');
        print('Would you like to automatically install bun?');
        response = input('Install bun? [Y/n]: ').strip().lower();
        if response and response not in ('y', 'yes') {
            return (False, f'bun installation cancelled. {manual_install_msg}', False);
        }
    }
    # Wrap entire installation process in error handling
    try {
        success_bun = NodeInstaller.install_bun();
        if not success_bun[0] {
            return (
                False,
                f'Unable to automatically install bun.\n\nError: {success_bun[1]}\n\n{manual_install_msg}',
                False
            );
        }

        # bun is now available
        print('\n' + '=' * 70);
        print('bun has been installed successfully!');
        print('Continuing with package installation...');
        print('=' * 70 + '\n');

        return (True, 'bun installed successfully', True);
    } except Exception as e {
        # Catch any unexpected errors during installation
        return (
            False,
            f'Unable to automatically install bun.\n\nUnexpected error: {str(e)}\n\n{manual_install_msg}',
            False
        );
    }
}

"""Ensure a package manager (bun or npm) is available.

Prefers bun, falls back to npm/Node.js if bun installation fails.
Returns tuple of (success: bool, message: str, package_manager: str)
"""
impl NodeInstaller.ensure_package_manager_installed(
    interactive: bool = True
) -> tuple[bool, str, str] {
    # Check if bun is available (preferred)
    if NodeInstaller.is_bun_installed() {
        version = NodeInstaller.get_bun_version();
        return (True, f'bun {version} is available', 'bun');
    }
    # Check if npm is available (fallback)
    if NodeInstaller.is_npm_installed() {
        version = NodeInstaller.get_node_version();
        return (True, f'npm (Node.js {version}) is available', 'npm');
    }
    # Neither is installed, try to install bun first (faster, simpler)
    print('\nNo package manager found. Attempting to install bun (recommended)...');
    if interactive {
        print(
            '\nJac client requires a package manager (bun or npm) to build client applications.'
        );
        print('bun is recommended for faster installs.');
        print('\nOptions:');
        print('  1. Install bun (recommended, faster)');
        print('  2. Install Node.js/npm');
        print('  3. Cancel');
        response = input('\nChoose [1/2/3] (default: 1): ').strip();
        if response == '3' {
            return (False, 'Package manager installation cancelled.', '');
        }
        if response == '2' {
            # Install Node.js/npm
            result = NodeInstaller.ensure_node_installed(interactive=False);
            if result[0] {
                return (True, result[1], 'npm');
            }
            return (False, result[1], '');
        }
    }
    # Default: Try to install bun
    result = NodeInstaller.ensure_bun_installed(interactive=False);
    if result[0] {
        return (True, result[1], 'bun');
    }
    # bun failed, try npm as fallback
    print('\nbun installation failed. Falling back to Node.js/npm...');
    result = NodeInstaller.ensure_node_installed(interactive=False);
    if result[0] {
        return (True, result[1], 'npm');
    }
    return (
        False,
        'Failed to install any package manager. Please install bun or Node.js manually:\n' + '  • bun: curl -fsSL https://bun.sh/install | bash\n' + '  • Node.js: https://nodejs.org/',
        ''
    );
}
