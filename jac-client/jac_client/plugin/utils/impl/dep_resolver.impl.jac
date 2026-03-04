"""Implementation of dependency resolver."""

import re;

"""Parse a version string into a tuple of (major, minor, patch).

Strips leading 'v' and ignores pre-release/build suffixes for comparison.
"""
def _parse_version(version: str) -> tuple[int, int, int] {
    v = version.lstrip('v');
    # Strip pre-release (-alpha.1) and build metadata (+build)
    v = re.split(r'[-+]', v)[0];
    parts = v.split('.');
    try {
        major = int(parts[0]) if len(parts) > 0 else 0;
        minor = int(parts[1]) if len(parts) > 1 else 0;
        patch = int(parts[2]) if len(parts) > 2 else 0;
        return (major, minor, patch);
    } except ValueError {
        return (0, 0, 0);
    }
}

"""Compare two version tuples. Returns -1, 0, or 1."""
def _compare_versions(a: tuple[int, int, int], b: tuple[int, int, int]) -> int {
    if a < b {
        return -1;
    }
    if a > b {
        return 1;
    }
    return 0;
}

"""Check if a version satisfies a single comparator (e.g., '>=1.2.3', '^1.0.0')."""
def _satisfies_comparator(version: tuple[int, int, int], comparator: str) -> bool {
    comp = comparator.strip();

    # Wildcard: *, x, or empty
    if comp in ('*', 'x', 'X', '', 'latest') {
        return True;
    }

    # Caret range: ^1.2.3 (compatible with version)
    if comp.startswith('^') {
        target = _parse_version(comp[1:]);
        if version < target {
            return False;
        }
        # ^0.0.x: only patch changes
        if target[0] == 0 and target[1] == 0 {
            return version[0] == 0 and version[1] == 0 and version[2] >= target[2];
        }
        # ^0.x: only minor+patch changes
        if target[0] == 0 {
            return version[0] == 0 and version[1] == target[1];
        }
        # ^x: same major
        return version[0] == target[0];
    }

    # Tilde range: ~1.2.3 (approximately equivalent)
    if comp.startswith('~') {
        target = _parse_version(comp[1:]);
        if version < target {
            return False;
        }
        # Same major.minor, patch >= target patch
        return version[0] == target[0] and version[1] == target[1];
    }

    # >=, <=, >, <, = comparators
    if comp.startswith('>=') {
        target = _parse_version(comp[2:]);
        return version >= target;
    }
    if comp.startswith('<=') {
        target = _parse_version(comp[2:]);
        return version <= target;
    }
    if comp.startswith('>') {
        target = _parse_version(comp[1:]);
        return version > target;
    }
    if comp.startswith('<') {
        target = _parse_version(comp[1:]);
        return version < target;
    }
    if comp.startswith('=') {
        target = _parse_version(comp[1:]);
        return version == target;
    }

    # Exact version
    target = _parse_version(comp);
    return version == target;
}

"""Check if a version string satisfies a semver range specifier."""
impl semver_satisfies(version: str, range_spec: str) -> bool {
    v = _parse_version(version);
    # Skip pre-release versions unless explicitly requested
    if '-' in version and '-' not in range_spec {
        return False;
    }

    # Handle || (union of ranges)
    if '||' in range_spec {
        for part in range_spec.split('||') {
            if _satisfies_range_set(v, part.strip()) {
                return True;
            }
        }
        return False;
    }

    return _satisfies_range_set(v, range_spec);
}

"""Check if a version satisfies a set of space-separated comparators (intersection)."""
def _satisfies_range_set(version: tuple[int, int, int], range_set: str) -> bool {
    # Handle hyphen ranges: 1.0.0 - 2.0.0
    if ' - ' in range_set {
        parts = range_set.split(' - ', 1);
        lower = _parse_version(parts[0].strip());
        upper = _parse_version(parts[1].strip());
        return version >= lower and version <= upper;
    }

    # Space-separated comparators are AND'd together
    comparators = range_set.strip().split();
    for comp in comparators {
        if not _satisfies_comparator(version, comp) {
            return False;
        }
    }
    return True;
}

"""Find the best (latest) version from a list that satisfies a semver range."""
impl resolve_version(versions: list[str], range_spec: str) -> (str | None) {
    matching: list[tuple[tuple[int, int, int], str]] = [];
    for v in versions {
        if semver_satisfies(v, range_spec) {
            matching.append((_parse_version(v), v));
        }
    }
    if not matching {
        return None;
    }
    # Sort by parsed version and return the latest
    matching.sort(reverse=True);
    return matching[0][1];
}

"""Resolve all dependencies from a package.json dict."""
impl resolve_dependencies(
    dependencies: dict[str, str],
    dev_dependencies: (dict[str, str] | None) = None,
    npmrc_config: (dict | None) = None
) -> dict[str, dict] {
    import from jac_client.plugin.utils.npm_registry { fetch_package_metadata }

    config = npmrc_config or {};
    registries: dict = config.get('registries', {});
    tokens: dict = config.get('tokens', {});
    default_registry: str = config.get('default_registry', 'https://registry.npmjs.org');

    # Metadata cache to avoid re-fetching
    metadata_cache: dict[str, dict] = {};
    # Resolved packages: { name: { version, tarball, dependencies } }
    resolved: dict[str, dict] = {};
    # Track packages being resolved to detect cycles
    resolving: set[str] = set();

    # Get registry URL and auth token for a package.
    def _get_registry_for_package(name: str) -> tuple[str, str | None] {
        if name.startswith('@') {
            scope = name.split('/')[0];
            if scope in registries {
                registry = registries[scope];
                # Find matching token
                for (token_path, token) in tokens.items() {
                    if token_path.rstrip('/') in registry {
                        return (registry, token);
                    }
                }
                return (registry, None);
            }
        }
        return (default_registry, None);
    }

    # Fetch and cache package metadata.
    def _get_metadata(name: str) -> dict {
        if name not in metadata_cache {
            (registry, token) = _get_registry_for_package(name);
            metadata_cache[name] = fetch_package_metadata(
                name, registry_url=registry, auth_token=token
            );
        }
        return metadata_cache[name];
    }

    # Recursively resolve a package and its dependencies.
    def _resolve_package(name: str, range_spec: str) -> None {
        # Skip if already resolved with a compatible version
        if name in resolved {
            existing = resolved[name]['version'];
            if semver_satisfies(existing, range_spec) {
                return;
            }
            # Version conflict: keep the existing one (hoisting strategy)
            return;
        }

        # Cycle detection
        if name in resolving {
            return;
        }
        resolving.add(name);

        try {
            metadata = _get_metadata(name);
            versions = list(metadata.get('versions', {}).keys());

            # Handle "latest" tag
            actual_range = range_spec;
            if range_spec == 'latest' or range_spec == '*' {
                dist_tags = metadata.get('dist-tags', {});
                if 'latest' in dist_tags {
                    actual_range = dist_tags['latest'];
                }
            }

            version = resolve_version(versions, actual_range);
            if not version {
                # Try dist-tags as fallback
                dist_tags = metadata.get('dist-tags', {});
                if actual_range in dist_tags {
                    version = dist_tags[actual_range];
                }
            }

            if not version {
                import from jaclang.cli.console { console }
                console.warning(f"  Could not resolve {name}@{range_spec}, skipping");
                return;
            }

            version_data = metadata['versions'][version];
            dist = version_data.get('dist', {});

            resolved[name] = {
                'version': version,
                'tarball': dist.get('tarball', ''),
                'integrity': dist.get('integrity', ''),
                'dependencies': version_data.get('dependencies', {})
            };

            # Resolve transitive dependencies
            for (dep_name, dep_range) in version_data.get('dependencies', {}).items() {
                _resolve_package(dep_name, dep_range);
            }
            # Note: we intentionally skip optionalDependencies and peerDependencies
            # for simplicity. peerDependencies are expected to be in the top-level deps.
        } finally {
            resolving.discard(name);
        }
    }

    # Resolve all top-level dependencies
    all_deps: dict[str, str] = dict(dependencies);
    if dev_dependencies {
        all_deps.update(dev_dependencies);
    }

    for (name, range_spec) in all_deps.items() {
        _resolve_package(name, range_spec);
    }

    return resolved;
}
