"""Implementation of Jac Package Manager."""

"""Install packages from a package.json file into a target directory."""
impl install(
    package_json_path: object, target_dir: object, npmrc_path: (object | None) = None
) -> None {
    import json;
    import os;
    import io;
    import tarfile;
    import hashlib;
    import from pathlib { Path }
    import from concurrent.futures { ThreadPoolExecutor, as_completed }
    import from jaclang.cli.console { console }
    import from jac_client.plugin.utils.npm_registry { download_tarball, parse_npmrc }
    import from jac_client.plugin.utils.dep_resolver { resolve_dependencies }

    pkg_path = Path(str(package_json_path));
    tgt_dir = Path(str(target_dir));

    if not pkg_path.exists() {
        raise RuntimeError(f"package.json not found at {pkg_path}") ;
    }

    # Read package.json
    with pkg_path.open('r', encoding='utf-8') as f {
        package_data = json.load(f);
    }

    dependencies = package_data.get('dependencies', {});
    dev_dependencies = package_data.get('devDependencies', {});

    if not dependencies and not dev_dependencies {
        console.print("  No dependencies to install.");
        return;
    }

    # Parse .npmrc if provided
    npmrc_config: dict | None = None;
    if npmrc_path {
        npmrc_config = parse_npmrc(npmrc_path);
    }

    # Check lock file
    lock_path = tgt_dir / 'jac-lock.json';
    node_modules = tgt_dir / 'node_modules';
    locked_packages: dict | None = None;

    if lock_path.exists() and node_modules.exists() {
        try {
            with lock_path.open('r', encoding='utf-8') as f {
                lock_data = json.load(f);
            }
            # Verify lock matches current deps
            lock_deps = lock_data.get('_source_deps', {});
            current_deps = {** dependencies, ** dev_dependencies};
            if lock_deps == current_deps {
                locked_packages = lock_data.get('dependencies', {});
                # Check if all locked packages exist in node_modules
                all_present = True;
                for name in locked_packages {
                    pkg_dir = node_modules / name;
                    if not pkg_dir.exists() {
                        all_present = False;
                        break;
                    }
                }
                if all_present {
                    console.print("  Dependencies up to date (from lock file).");
                    return;
                }
                # Some missing, reinstall from locked versions
            } else {
                locked_packages = None;
            }
        } except (json.JSONDecodeError, KeyError) {
            locked_packages = None;
        }
    }

    # Resolve dependencies
    if locked_packages {
        resolved = locked_packages;
        console.print("  Resolving from lock file...");
    } else {
        console.print("  Resolving dependencies...");
        resolved = resolve_dependencies(dependencies, dev_dependencies, npmrc_config);
    }

    if not resolved {
        console.print("  No packages to install.");
        return;
    }

    console.print(f"  Found {len(resolved)} packages to install.");

    # Create node_modules directory
    node_modules.mkdir(parents=True, exist_ok=True);
    bin_dir = node_modules / '.bin';
    bin_dir.mkdir(exist_ok=True);

    # Determine which packages need downloading
    to_download: list[tuple[str, dict]] = [];
    for (name, info) in resolved.items() {
        pkg_dir = node_modules / name;
        # Handle scoped packages
        if name.startswith('@') {
            scope_dir = node_modules / name.split('/')[0];
            scope_dir.mkdir(exist_ok=True);
        }
        # Skip if already installed with correct version
        existing_pkg_json = pkg_dir / 'package.json';
        if existing_pkg_json.exists() {
            try {
                with existing_pkg_json.open('r', encoding='utf-8') as f {
                    existing = json.load(f);
                }
                if existing.get('version') == info['version'] {
                    # Already installed, just ensure bin links
                    _link_bins(existing, pkg_dir, bin_dir);
                    continue;
                }
            } except (json.JSONDecodeError, KeyError) {
                ;
            }
        }
        to_download.append((name, info));
    }

    if not to_download {
        console.print("  All packages already installed.");
        _write_lock_file(lock_path, resolved, dependencies, dev_dependencies);
        return;
    }

    console.print(f"  Downloading {len(to_download)} packages...");

    # Get auth tokens for downloads
    tokens = (npmrc_config or {}).get('tokens', {});

    def _get_token_for_url(url: str) -> str | None {
        """Find matching auth token for a tarball URL."""
        for (registry_path, token) in tokens.items() {
            # registry_path is like //npm.pkg.github.com/
            clean_path = registry_path.lstrip('/');
            if clean_path in url {
                return token;
            }
        }
        return None;
    }

    # Download and extract in parallel
    def _download_and_extract(name: str, info: dict) -> str {
        tarball_url = info.get('tarball', '');
        if not tarball_url {
            raise RuntimeError(
                f"No tarball URL for {name}@{info.get('version', '?')}"
            ) ;
        }
        token = _get_token_for_url(tarball_url);
        data = download_tarball(tarball_url, auth_token=token);

        pkg_dir = node_modules / name;
        # Clean existing directory
        if pkg_dir.exists() {
            import shutil;
            shutil.rmtree(pkg_dir);
        }
        pkg_dir.mkdir(parents=True, exist_ok=True);

        # Extract tarball (npm tarballs have a package/ prefix)
        with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as tar {
            for member in tar.getmembers() {
                # Strip the first directory component (usually "package/")
                parts = member.name.split('/', 1);
                if len(parts) < 2 {
                    continue;
                }
                member.name = parts[1];
                if not member.name {
                    continue;
                }
                # Security: prevent path traversal
                if member.name.startswith('..') or member.name.startswith('/') {
                    continue;
                }
                tar.extract(member, pkg_dir);
            }
        }

        # Link binaries
        pkg_json_file = pkg_dir / 'package.json';
        if pkg_json_file.exists() {
            with pkg_json_file.open('r', encoding='utf-8') as f {
                pkg_json = json.load(f);
            }
            _link_bins(pkg_json, pkg_dir, bin_dir);
        }

        return name;
    }

    # Use thread pool for parallel downloads
    max_workers = min(8, len(to_download));
    with ThreadPoolExecutor(max_workers=max_workers) as executor {
        futures = {
            executor.submit(_download_and_extract, name, info): name
            for (name, info) in to_download
        };
        completed = 0;
        for future in as_completed(futures) {
            name = futures[future];
            try {
                future.result();
                completed += 1;
            } except Exception as e {
                console.warning(f"  Failed to install {name}: {e}");
            }
        }
    }

    console.print(f"  Installed {completed}/{len(to_download)} packages.");

    # Write lock file
    _write_lock_file(lock_path, resolved, dependencies, dev_dependencies);
}

"""Create symlinks in node_modules/.bin/ for a package's bin entries."""
def _link_bins(package_json: dict, pkg_dir: object, bin_dir: object) -> None {
    import os;
    import stat;
    import from pathlib { Path }

    pkg_path = Path(str(pkg_dir));
    bin_path = Path(str(bin_dir));
    bin_field = package_json.get('bin');

    if not bin_field {
        return;
    }

    # bin can be a string (single binary) or a dict
    bins: dict[str, str] = {};
    if isinstance(bin_field, str) {
        name = package_json.get('name', '').split('/')[-1];
        if name {
            bins[name] = bin_field;
        }
    } elif isinstance(bin_field, dict) {
        bins = bin_field;
    }

    for (bin_name, bin_target) in bins.items() {
        link_path = bin_path / bin_name;
        target_path = pkg_path / bin_target;

        # Remove existing link
        if link_path.exists() or link_path.is_symlink() {
            link_path.unlink();
        }

        if target_path.exists() {
            # Make the target executable
            target_path.chmod(
                target_path.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH
            );
            # Create symlink
            os.symlink(str(target_path.resolve()), str(link_path));
        }
    }
}

"""Write the lock file."""
def _write_lock_file(
    lock_path: object, resolved: dict, dependencies: dict, dev_dependencies: dict
) -> None {
    import json;
    import from pathlib { Path }

    path = Path(str(lock_path));
    lock_data = {
        'lockVersion': 1,
        '_source_deps': {** dependencies, ** dev_dependencies},
        'dependencies': resolved
    };

    with path.open('w', encoding='utf-8') as f {
        json.dump(lock_data, f, indent=2);
    }
}

"""Install a single package globally to ~/.jac/node_modules/."""
impl install_global(package_name: str, version: (str | None) = None) -> None {
    import json;
    import os;
    import from pathlib { Path }
    import from jaclang.cli.console { console }

    global_dir = Path(os.path.expanduser('~/.jac'));
    global_dir.mkdir(parents=True, exist_ok=True);

    # Create a temporary package.json for the global install
    pkg_json = {
        'name': 'jac-global',
        'version': '1.0.0',
        'dependencies': {package_name: version or 'latest'}
    };

    pkg_json_path = global_dir / 'package.json';
    with pkg_json_path.open('w', encoding='utf-8') as f {
        json.dump(pkg_json, f, indent=2);
    }

    try {
        console.print(f"  Installing {package_name} globally...");
        install(pkg_json_path, global_dir);
        console.print(f"  Installed {package_name} globally.");
    } finally {
        # Clean up temporary package.json
        if pkg_json_path.exists() {
            pkg_json_path.unlink();
        }
    }
}

"""List globally installed packages."""
impl list_global -> dict[str, str] {
    import json;
    import os;
    import from pathlib { Path }

    global_modules = Path(os.path.expanduser('~/.jac/node_modules'));
    result: dict[str, str] = {};

    if not global_modules.exists() {
        return result;
    }

    for item in global_modules.iterdir() {
        if item.name.startswith('.') {
            continue;
        }
        if item.name.startswith('@') {
            # Scoped packages
            for sub in item.iterdir() {
                pkg_json = sub / 'package.json';
                if pkg_json.exists() {
                    try {
                        with pkg_json.open('r', encoding='utf-8') as f {
                            data = json.load(f);
                        }
                        result[data.get('name', f'{item.name}/{sub.name}')] = data.get(
                            'version', '?'
                        );
                    } except Exception {
                        ;
                    }
                }
            }
        } else {
            pkg_json = item / 'package.json';
            if pkg_json.exists() {
                try {
                    with pkg_json.open('r', encoding='utf-8') as f {
                        data = json.load(f);
                    }
                    result[data.get('name', item.name)] = data.get('version', '?');
                } except Exception {
                    ;
                }
            }
        }
    }

    return result;
}

"""Check if a specific global package is installed."""
impl is_global_installed(package_name: str) -> bool {
    return package_name in list_global();
}
