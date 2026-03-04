"""Dependency resolver for npm packages.

Resolves semver version ranges and builds a flat dependency tree
from a package.json's dependencies.
"""

"""Check if a version string satisfies a semver range specifier.

Supports: ^, ~, >=, <=, >, <, =, exact versions, *, x, and || (union).
"""
def semver_satisfies(version: str, range_spec: str) -> bool;

"""Find the best (latest) version from a list that satisfies a semver range."""
def resolve_version(versions: list[str], range_spec: str) -> (str | None);

"""Resolve all dependencies from a package.json dict.

Takes dependencies and devDependencies dicts, resolves the full
transitive dependency tree, and returns a flat map of:
  { 'package_name': { 'version': '1.2.3', 'tarball': 'https://...', 'dependencies': {...} } }

Uses npmrc_config for private registry lookups.
"""
def resolve_dependencies(
    dependencies: dict[str, str],
    dev_dependencies: (dict[str, str] | None) = None,
    npmrc_config: (dict | None) = None
) -> dict[str, dict];
