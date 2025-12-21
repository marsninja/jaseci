"""Implementation of lock file management for Jac projects."""

# ===============================================================================
# Lockfile Implementation
# ===============================================================================
impl Lockfile.load(
    lockfile_path: Path
) -> Lockfile | None {
    import sys;
    import tomllib;
    if not lockfile_path.exists() {
        return None;
    }
    try {
        with open(lockfile_path, "rb") as f {
            data = tomllib.load(f);
        }
    } except Exception as e {
        print(f"Warning: Could not parse lock file: {e}", file=sys.stderr);
        return None;
    }
    lockfile = Lockfile();
    lockfile.lockfile_path = lockfile_path;
    if "metadata" in data {
        meta = data["metadata"];
        lockfile.metadata = LockfileMetadata(
            generated_at=meta.get("generated_at", ""),
            jac_version=meta.get("jac_version", ""),
            python_version=meta.get("python_version", ""),
            platform_name=meta.get("platform", ""),
            config_hash=meta.get("config_hash", "")
        );
    }
    if "package" in data {
        for pkg_data in data["package"] {
            pkg = LockedPackage(
                name=pkg_data.get("name", ""),
                version=pkg_data.get("version", ""),
                hash=pkg_data.get("hash", ""),
                source=pkg_data.get("source", "pypi"),
                dependencies=pkg_data.get("dependencies", [])
            );
            lockfile.packages.append(pkg);
        }
    }
    return lockfile;
}

impl Lockfile.create(config: JacConfig, packages: list[LockedPackage]) -> Lockfile {
    import platform;
    import from datetime { datetime, timezone }
    import from importlib.metadata { version as pkg_version }
    lockfile = Lockfile();
    if config.project_root {
        lockfile.lockfile_path = config.project_root / "jac.lock";
    }
    try {
        jac_ver = pkg_version("jaclang");
    } except Exception {
        jac_ver = "unknown";
    }
    lockfile.metadata = LockfileMetadata(
        generated_at=datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        jac_version=jac_ver,
        python_version=platform.python_version(),
        platform_name=platform.system().lower(),
        config_hash=Lockfile.hash_config(config)
    );
    lockfile.packages = packages;
    return lockfile;
}

impl Lockfile.save -> None {
    import tomlkit;
    if self.lockfile_path is None {
        raise ValueError("No lockfile_path set, cannot save lock file") ;
    }
    doc = tomlkit.document();
    doc.add(tomlkit.comment("jac.lock - Auto-generated, do not edit manually"));
    doc.add(tomlkit.nl());
    meta_table = tomlkit.table();
    meta_table.add("generated_at", self.metadata.generated_at);
    meta_table.add("jac_version", self.metadata.jac_version);
    meta_table.add("python_version", self.metadata.python_version);
    meta_table.add("platform", self.metadata.platform_name);
    meta_table.add("config_hash", self.metadata.config_hash);
    doc.add("metadata", meta_table);
    doc.add(tomlkit.nl());
    if self.packages {
        aot = tomlkit.aot();
        for pkg in self.packages {
            pkg_table = tomlkit.table();
            pkg_table.add("name", pkg.name);
            pkg_table.add("version", pkg.version);
            if pkg.hash {
                pkg_table.add("hash", pkg.hash);
            }
            pkg_table.add("source", pkg.source);
            if pkg.dependencies {
                pkg_table.add("dependencies", pkg.dependencies);
            }
            aot.append(pkg_table);
        }
        doc.add("package", aot);
    }
    with open(self.lockfile_path, "w") as f {
        f.write(tomlkit.dumps(doc));
    }
}

impl Lockfile.is_current(config: JacConfig) -> bool {
    current_hash = Lockfile.hash_config(config);
    return self.metadata.config_hash == current_hash;
}

impl Lockfile.get_package(name: str) -> LockedPackage | None {
    normalized_name = name.lower().replace("-", "_");
    for pkg in self.packages {
        if pkg.name.lower().replace("-", "_") == normalized_name {
            return pkg;
        }
    }
    return None;
}

impl Lockfile.hash_config(config: JacConfig) -> str {
    import hashlib;
    import json;
    deps_data = {
        "dependencies": dict(sorted(config.dependencies.items())),
        "dev_dependencies": dict(sorted(config.dev_dependencies.items())),
        "git_dependencies": dict(sorted(config.git_dependencies.items())),
        "plugin_dependencies": dict(sorted(config.plugin_dependencies.items()))
    };
    deps_json = json.dumps(deps_data, sort_keys=True);
    return hashlib.sha256(deps_json.encode()).hexdigest()[:16];
}

# ===============================================================================
# Lock File Utilities Implementation
# ===============================================================================
impl get_lockfile_path(
    config: JacConfig | None = None
) -> Path | None {
    import from jaclang.project.config { get_config }
    if config is None {
        config = get_config();
    }
    if config is None or config.project_root is None {
        return None;
    }
    return config.project_root / "jac.lock";
}

impl lockfile_exists(config: JacConfig | None = None) -> bool {
    path = get_lockfile_path(config);
    if path is None {
        return False;
    }
    return path.exists();
}
