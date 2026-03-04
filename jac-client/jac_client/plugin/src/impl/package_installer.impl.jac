"""List all installed packages from jac.toml."""

impl PackageInstaller.list_packages(
    self: PackageInstaller
) -> dict[str, dict[str, str]] {
    if not self.config_file.exists() {
        raise ClientBundleError(
            f'jac.toml not found at {self.config_file}. Run "jac init" first.'
        ) ;
    }
    config = self.config_loader.load();
    package_config = config.get('package', {});
    return {
        'dependencies': package_config.get('dependencies', {}),
        'devDependencies': package_config.get('devDependencies', {})
    };
}

"""Uninstall a package by removing it from jac.toml."""
impl PackageInstaller.uninstall_package(
    self: PackageInstaller, package_name: str, is_dev: bool = False
) -> None {
    if not self.config_file.exists() {
        raise ClientBundleError(
            f'jac.toml not found at {self.config_file}. Run "jac init" first.'
        ) ;
    }
    # Remove the dependency using JacClientConfig
    result = self.config_loader.remove_dependency(package_name, is_dev);
    if not result {
        deps_key = 'dev-dependencies' if is_dev else 'dependencies';
        raise ClientBundleError(f'Package "{package_name}" not found in {deps_key}') ;
    }
    # Save the updated config
    self.config_loader.save();
    # Regenerate package.json and reinstall to actually remove the package
    self._regenerate_and_install();
}

"""Regenerate package.json from jac.toml and install packages."""
impl PackageInstaller._regenerate_and_install(self: PackageInstaller) -> None {
    import from jac_client.plugin.utils { ensure_node_available, jac_pm_install }
    import from jaclang.cli.console { console }
    # Ensure Node.js is available before proceeding
    if not ensure_node_available() {
        raise ClientBundleError(
            'Node.js is required. Install via: pip install nodejs-wheel'
        ) from None ;
    }
    # Regenerate package.json from updated jac.toml
    bundler = ViteBundler(self.project_dir);
    bundler.create_package_json();
    # Install packages using JacPM
    client_dir = bundler._get_client_dir();
    configs_package_json = client_dir / 'configs' / 'package.json';
    configs_npmrc = client_dir / 'configs' / '.npmrc';
    try {
        console.print("\n  ⏳ Installing packages...\n");
        npmrc_path = configs_npmrc if configs_npmrc.exists() else None;
        jac_pm_install(configs_package_json, client_dir, npmrc_path=npmrc_path);
        console.print("\n  ✔ Packages installed");
    } except Exception as e {
        raise ClientBundleError(f'Failed to install packages: {e}') ;
    }
}

"""Install all packages from jac.toml (regenerate package.json and install)."""
impl PackageInstaller.install_all(self: PackageInstaller) -> None {
    if not self.config_file.exists() {
        raise ClientBundleError(
            f'jac.toml not found at {self.config_file}. Run "jac init" first.'
        ) ;
    }
    self._regenerate_and_install();
}

"""Install a package by adding it to jac.toml."""
impl PackageInstaller.install_package(
    self: PackageInstaller,
    package_name: str,
    version: (str | None) = None,
    is_dev: bool = False
) -> None {
    if not self.config_file.exists() {
        raise ClientBundleError(
            f'jac.toml not found at {self.config_file}. Run "jac init" first.'
        ) ;
    }
    # Add package with version (default to latest if not specified)
    package_version = version or 'latest';
    # Use JacClientConfig to add the dependency
    self.config_loader.add_dependency(package_name, package_version, is_dev);
    # Save the updated config
    self.config_loader.save();
    # Regenerate package.json and install the package
    self._regenerate_and_install();
}

"""Handles installing packages by updating jac.toml."""
impl PackageInstaller.init(self: PackageInstaller, project_dir: Path) {
    self.project_dir = project_dir;
    self.config_loader = JacClientConfig(project_dir);
    self.config_file = project_dir / 'jac.toml';
}
