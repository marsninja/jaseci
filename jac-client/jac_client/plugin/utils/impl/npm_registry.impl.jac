"""Implementation of NPM registry client."""

"""Fetch package metadata from the npm registry."""
impl fetch_package_metadata(
    package_name: str,
    registry_url: str = "https://registry.npmjs.org",
    auth_token: (str | None) = None
) -> dict {
    import json;
    import from urllib.request { Request, urlopen }
    import from urllib.parse { quote }
    import from urllib.error { HTTPError, URLError }

    # Handle scoped packages: @scope/name -> @scope%2fname
    if package_name.startswith('@') {
        encoded_name = quote(package_name, safe='@');
    } else {
        encoded_name = package_name;
    }

    url = f"{registry_url.rstrip('/')}/{encoded_name}";

    headers = {'Accept': 'application/json', 'User-Agent': 'jac-pm/1.0'};
    if auth_token {
        headers['Authorization'] = f'Bearer {auth_token}';
    }

    req = Request(url, headers=headers);
    try {
        with urlopen(req, timeout=30) as response {
            return json.loads(response.read().decode('utf-8'));
        }
    } except HTTPError as e {
        if e.code == 404 {
            raise RuntimeError(
                f"Package '{package_name}' not found in registry"
            ) from e ;
        }
        raise RuntimeError(
            f"Registry error for '{package_name}': HTTP {e.code}"
        ) from e ;
    } except URLError as e {
        raise RuntimeError(
            f"Cannot reach registry at {registry_url}: {e.reason}"
        ) from e ;
    }
}

"""Fetch metadata for a specific version of a package."""
impl fetch_version_metadata(
    package_name: str,
    version: str,
    registry_url: str = "https://registry.npmjs.org",
    auth_token: (str | None) = None
) -> dict {
    metadata = fetch_package_metadata(package_name, registry_url, auth_token);
    versions = metadata.get('versions', {});
    if version not in versions {
        available = list(versions.keys())[-5:] if versions else [];
        raise RuntimeError(
            f"Version '{version}' not found for '{package_name}'. "
            f"Recent versions: {', '.join(available)}"
        ) ;
    }
    return versions[version];
}

"""Download a tarball from the given URL and return the bytes."""
impl download_tarball(tarball_url: str, auth_token: (str | None) = None) -> bytes {
    import from urllib.request { Request, urlopen }
    import from urllib.error { HTTPError, URLError }

    headers = {'User-Agent': 'jac-pm/1.0'};
    if auth_token {
        headers['Authorization'] = f'Bearer {auth_token}';
    }

    req = Request(tarball_url, headers=headers);
    try {
        with urlopen(req, timeout=120) as response {
            return response.read();
        }
    } except HTTPError as e {
        raise RuntimeError(
            f"Failed to download tarball: HTTP {e.code} from {tarball_url}"
        ) from e ;
    } except URLError as e {
        raise RuntimeError(
            f"Cannot download tarball from {tarball_url}: {e.reason}"
        ) from e ;
    }
}

"""Parse .npmrc file and return registry/auth configuration."""
impl parse_npmrc(npmrc_path: object) -> dict {
    import from pathlib { Path }
    import os;

    result: dict = {
        'registries': {},
        'tokens': {},
        'default_registry': 'https://registry.npmjs.org'
    };

    path = Path(str(npmrc_path));
    if not path.exists() {
        return result;
    }

    for line in path.read_text(encoding='utf-8').splitlines() {
        line = line.strip();
        if not line or line.startswith('#') or line.startswith(';') {
            continue;
        }

        # Scoped registry: @scope:registry=https://...
        if ':registry=' in line and line.startswith('@') {
            parts = line.split(':registry=', 1);
            scope = parts[0].strip();
            registry = parts[1].strip();
            result['registries'][scope] = registry;
        }
        # Auth token: //registry.url/:_authToken=...
        elif line.startswith('//') and ':_authToken=' in line {
            parts = line.split(':_authToken=', 1);
            registry_path = parts[0].strip();
            token = parts[1].strip();
            # Expand environment variables in token
            if token.startswith('${') and token.endswith('}') {
                env_var = token[2:-1];
                token = os.environ.get(env_var, '');
            }
            result['tokens'][registry_path] = token;
        }
        # Default registry: registry=https://...
        elif line.startswith('registry=') {
            result['default_registry'] = line.split('=', 1)[1].strip();
        }
    }

    return result;
}
