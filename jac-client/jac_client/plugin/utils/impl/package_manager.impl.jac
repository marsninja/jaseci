"""Implementation of package manager abstraction methods."""

"""Check if bun is installed and accessible."""
impl PackageManager.is_bun_installed -> bool {
    try {
        result = subprocess.run(
            ['bun', '--version'], capture_output=True, text=True, timeout=5
        );
        return result.returncode == 0;
    } except (FileNotFoundError, subprocess.TimeoutExpired) {
        return False;
    }
}

"""Check if npm is installed and accessible."""
impl PackageManager.is_npm_installed -> bool {
    try {
        result = subprocess.run(
            ['npm', '--version'], capture_output=True, text=True, timeout=5
        );
        return result.returncode == 0;
    } except (FileNotFoundError, subprocess.TimeoutExpired) {
        return False;
    }
}

"""Get the currently installed bun version."""
impl PackageManager.get_bun_version -> (str | None) {
    try {
        result = subprocess.run(
            ['bun', '--version'], capture_output=True, text=True, timeout=5
        );
        if result.returncode == 0 {
            return result.stdout.strip();
        }
    } except (FileNotFoundError, subprocess.TimeoutExpired) { }
    return None;
}

"""Get the currently installed npm version."""
impl PackageManager.get_npm_version -> (str | None) {
    try {
        result = subprocess.run(
            ['npm', '--version'], capture_output=True, text=True, timeout=5
        );
        if result.returncode == 0 {
            return result.stdout.strip();
        }
    } except (FileNotFoundError, subprocess.TimeoutExpired) { }
    return None;
}

"""Get the preferred package manager."""
impl PackageManager.get_preferred -> str {
    # Check environment variable override first
    env_override = os.environ.get(PackageManager.ENV_VAR, '').lower();
    if env_override in ('bun', 'npm') {
        return env_override;
    }
    # Auto-detect: prefer bun if available
    if PackageManager.is_bun_installed() {
        return 'bun';
    }
    # Fallback to npm
    return 'npm';
}

"""Get the install command for the preferred package manager."""
impl PackageManager.get_install_cmd -> list[str] {
    pm = PackageManager.get_preferred();
    return [pm, 'install'];
}

"""Get the run command for a script."""
impl PackageManager.get_run_cmd(script: str) -> list[str] {
    pm = PackageManager.get_preferred();
    return [pm, 'run', script];
}

"""Get the exec command (npx/bunx)."""
impl PackageManager.get_exec_cmd -> str {
    pm = PackageManager.get_preferred();
    if pm == 'bun' {
        return 'bunx';
    }
    return 'npx';
}

"""Get the global add command for a package."""
impl PackageManager.get_global_add_cmd(pkg: str) -> list[str] {
    pm = PackageManager.get_preferred();
    if pm == 'bun' {
        return ['bun', 'add', '-g', pkg];
    }
    return ['npm', 'install', '-g', pkg];
}

"""Get the global list command."""
impl PackageManager.get_global_list_cmd -> list[str] {
    pm = PackageManager.get_preferred();
    if pm == 'bun' {
        return ['bun', 'pm', 'ls', '-g'];
    }
    return ['npm', 'list', '-g'];
}

"""Get the version check command."""
impl PackageManager.get_version_cmd -> list[str] {
    pm = PackageManager.get_preferred();
    return [pm, '--version'];
}

"""Run a package manager command with proper environment."""
impl PackageManager.run_cmd(
    args: list,
    cwd: Path,
    timeout: int = 300,
    check: bool = True,
    capture_output: bool = True
) -> object {
    pm = PackageManager.get_preferred();
    cmd = [pm] + args;
    # First, try running directly (if pm is in PATH)
    try {
        return subprocess.run(
            cmd,
            cwd=cwd,
            capture_output=capture_output,
            text=True,
            timeout=timeout,
            check=check
        );
    } except FileNotFoundError { }
    # For npm: If not in PATH, try sourcing NVM
    if pm == 'npm' {
        args_str = ' '.join(args);
        command = (
            'export NVM_DIR="$HOME/.nvm"\n' + '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"\n' + f'npm {args_str}\n'
        );
        return subprocess.run(
            ['bash', '-c', command],
            cwd=cwd,
            capture_output=capture_output,
            text=True,
            timeout=timeout,
            check=check
        );
    }
    # For bun: check common install locations
    if pm == 'bun' {
        bun_paths = [
            Path.home() / '.bun' / 'bin' / 'bun',
            Path('/usr/local/bin/bun'),

        ];
        for bun_path in bun_paths {
            if bun_path.exists() {
                return subprocess.run(
                    [str(bun_path)] + args,
                    cwd=cwd,
                    capture_output=capture_output,
                    text=True,
                    timeout=timeout,
                    check=check
                );
            }
        }
    }
    # Re-raise the FileNotFoundError if we couldn't find the command
    raise FileNotFoundError(f'{pm} command not found') ;
}

"""Get the build script content for package.json."""
impl PackageManager.get_build_script(config_path: str) -> str {
    pm = PackageManager.get_preferred();
    return f'{pm} run compile && vite build --config {config_path}';
}
