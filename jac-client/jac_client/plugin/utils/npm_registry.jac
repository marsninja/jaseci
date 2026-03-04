"""NPM registry client for fetching package metadata and tarballs.

Provides functions to interact with the npm registry (registry.npmjs.org)
or private registries configured via .npmrc.
"""

"""Fetch package metadata from the npm registry.

Returns the full metadata dict for a package, including all versions.
Supports scoped packages (@scope/name).
"""
def fetch_package_metadata(
    package_name: str,
    registry_url: str = "https://registry.npmjs.org",
    auth_token: (str | None) = None
) -> dict;

"""Fetch metadata for a specific version of a package.

Returns the version-specific metadata dict, including tarball URL and dependencies.
"""
def fetch_version_metadata(
    package_name: str,
    version: str,
    registry_url: str = "https://registry.npmjs.org",
    auth_token: (str | None) = None
) -> dict;

"""Download a tarball from the given URL and return the bytes.

Supports authentication for private registries.
"""
def download_tarball(tarball_url: str, auth_token: (str | None) = None) -> bytes;

"""Parse .npmrc file and return registry/auth configuration.

Returns a dict with:
  - 'registries': { '@scope': 'https://registry.url' }
  - 'tokens': { '//registry.url/': 'token_value' }
  - 'default_registry': str
"""
def parse_npmrc(npmrc_path: object) -> dict;
