"""Implementation of script runner."""

"""Run a script defined in package.json."""
impl run_script(
    script_name: str,
    package_json_path: object,
    cwd: (object | None) = None,
    check: bool = False,
    capture_output: bool = False,
    text: bool = True,
    timeout: (int | None) = None
) -> object {
    import json;
    import os;
    import subprocess;
    import from pathlib { Path }

    pkg_path = Path(str(package_json_path));
    if not pkg_path.exists() {
        raise RuntimeError(f"package.json not found at {pkg_path}") ;
    }

    with pkg_path.open('r', encoding='utf-8') as f {
        package_data = json.load(f);
    }

    scripts = package_data.get('scripts', {});
    if script_name not in scripts {
        available = ', '.join(scripts.keys()) if scripts else 'none';
        raise RuntimeError(
            f"Script '{script_name}' not found in package.json. Available: {available}"
        ) ;
    }

    script_cmd = scripts[script_name];
    work_dir = Path(str(cwd)) if cwd else pkg_path.parent;

    # Prepend node_modules/.bin to PATH
    env = os.environ.copy();
    node_modules_bin = work_dir / 'node_modules' / '.bin';
    if node_modules_bin.exists() {
        env['PATH'] = f"{node_modules_bin}:{env.get('PATH', '')}";
    }
    # Also check parent directories for node_modules
    parent_nm_bin = work_dir.parent / 'node_modules' / '.bin';
    if parent_nm_bin.exists() {
        env['PATH'] = f"{parent_nm_bin}:{env.get('PATH', '')}";
    }

    kwargs: dict = {
        'cwd': str(work_dir),
        'env': env,
        'shell': True,
        'check': check,
        'text': text
    };
    if capture_output {
        kwargs['capture_output'] = True;
    }
    if timeout {
        kwargs['timeout'] = timeout;
    }

    return subprocess.run(script_cmd, **kwargs);
}

"""Run a binary from node_modules/.bin/."""
impl run_bin(
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
) -> object {
    import os;
    import subprocess;
    import from pathlib { Path }

    nm_dir = Path(str(node_modules_dir));
    bin_dir = nm_dir / '.bin';
    bin_path = bin_dir / bin_name;

    if not bin_path.exists() {
        raise RuntimeError(
            f"Binary '{bin_name}' not found in {bin_dir}. "
            f"Run 'jac add --npm' to install dependencies first."
        ) ;
    }

    # Build command
    command = [str(bin_path)] + args;

    work_dir = Path(str(cwd)) if cwd else nm_dir.parent;

    # Prepend node_modules/.bin to PATH so the binary can find its deps
    env = os.environ.copy();
    env['PATH'] = f"{bin_dir}:{env.get('PATH', '')}";

    if as_popen {
        # Return a Popen object for long-running processes (like dev servers)
        popen_kwargs: dict = {'cwd': str(work_dir), 'env': env};
        if stdout is not None {
            popen_kwargs['stdout'] = stdout;
        }
        if stderr is not None {
            popen_kwargs['stderr'] = stderr;
        }
        if text {
            popen_kwargs['text'] = True;
        }
        return subprocess.Popen(command, **popen_kwargs);
    } else {
        kwargs: dict = {'cwd': str(work_dir), 'env': env, 'check': check, 'text': text};
        if capture_output {
            kwargs['capture_output'] = True;
        }
        if timeout {
            kwargs['timeout'] = timeout;
        }
        return subprocess.run(command, **kwargs);
    }
}
