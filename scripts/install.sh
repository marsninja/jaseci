#!/usr/bin/env bash
# Jac Programming Language Installer
#
# jaclang ships as ONE self-contained `jac` binary (a Zig launcher that dlopens a
# bundled CPython -- no system Python, uv, or pip needed). This script downloads
# that prebuilt binary from GitHub Releases. Plugins (byllm, jac-scale, jac-mcp)
# are added per-project with `jac install <plugin>`, which pulls their wheels
# into the project's own venv -- there is no global "ecosystem" install.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/jaseci-labs/jaseci/main/scripts/install.sh | bash
#
# Options:
#   --version V   Install a specific release version
#   --uninstall   Remove Jac
#   --help        Print usage
#
# Examples:
#   curl -fsSL ... | bash                          # Latest jac binary
#   curl -fsSL ... | bash -s -- --version 2.3.1    # Specific version

set -euo pipefail

REPO="jaseci-labs/jaseci"
GITHUB_API="https://api.github.com/repos/${REPO}"
INSTALL_DIR="${HOME}/.local/bin"

# --- Defaults ---
VERSION=""
UNINSTALL=false

# --- Colors and output helpers ---

info() {
    printf "\033[0;34m[jac]\033[0m %s\n" "$*"
}

warn() {
    printf "\033[0;33m[jac]\033[0m %s\n" "$*" >&2
}

err() {
    printf "\033[0;31m[jac]\033[0m %s\n" "$*" >&2
}

has_cmd() {
    command -v "$1" &>/dev/null
}

need_cmd() {
    if ! has_cmd "$1"; then
        err "Required command not found: $1"
        err "Please install '$1' and try again."
        exit 1
    fi
}

# --- Usage ---

usage() {
    cat <<EOF
Jac Programming Language Installer

USAGE:
    curl -fsSL https://raw.githubusercontent.com/jaseci-labs/jaseci/main/scripts/install.sh | bash
    curl -fsSL ... | bash -s -- [OPTIONS]

OPTIONS:
    --version V   Install a specific release version (e.g., 2.3.1)
    --uninstall   Remove Jac installation
    --help        Print this help message

EXAMPLES:
    # Latest jac binary
    curl -fsSL ... | bash

    # Specific version
    curl -fsSL ... | bash -s -- --version 2.3.1

After installing, add plugins per-project with e.g. \`jac install byllm\`.
EOF
}

# --- Platform detection ---

detect_platform() {
    local os arch
    os="$(uname -s)"
    arch="$(uname -m)"

    case "$os" in
        Linux*)  OS="linux" ;;
        Darwin*) OS="macos" ;;
        MINGW* | MSYS* | CYGWIN*)
            err "Windows detected. Windows support via PowerShell is coming soon."
            err "For now, please use WSL2."
            exit 1
            ;;
        *)
            err "Unsupported operating system: $os"
            exit 1
            ;;
    esac

    case "$arch" in
        x86_64 | amd64)  ARCH="x86_64" ;;
        aarch64 | arm64)  ARCH="aarch64" ;;
        *)
            err "Unsupported architecture: $arch"
            exit 1
            ;;
    esac
}

# --- Argument parsing ---

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version)
                if [[ $# -lt 2 ]]; then
                    err "--version requires a version argument (e.g., --version 2.3.1)"
                    exit 1
                fi
                VERSION="$2"
                shift 2
                ;;
            --uninstall)
                UNINSTALL=true
                shift
                ;;
            # Accepted for backward compatibility; there is now a single binary
            # and no uv path, so these are no-ops.
            --standalone | --core)
                warn "'$1' is deprecated and ignored: the single 'jac' binary is the only install."
                shift
                ;;
            --help | -h)
                usage
                exit 0
                ;;
            *)
                err "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# --- PATH helpers ---

ensure_on_path() {
    if ! echo "$PATH" | tr ':' '\n' | grep -q "^${INSTALL_DIR}$"; then
        export PATH="${INSTALL_DIR}:${PATH}"
    fi

    # Check if the install dir is in the user's shell profile
    local shell_name
    shell_name="$(basename "${SHELL:-/bin/bash}")"
    local profile=""

    case "$shell_name" in
        zsh)  profile="$HOME/.zshrc" ;;
        bash)
            if [[ -f "$HOME/.bashrc" ]]; then
                profile="$HOME/.bashrc"
            elif [[ -f "$HOME/.bash_profile" ]]; then
                profile="$HOME/.bash_profile"
            fi
            ;;
        fish) profile="$HOME/.config/fish/config.fish" ;;
    esac

    if [[ -n "$profile" ]] && ! grep -q "${INSTALL_DIR}" "$profile" 2>/dev/null; then
        warn ""
        warn "Add ${INSTALL_DIR} to your PATH by running:"
        if [[ "$shell_name" == "fish" ]]; then
            warn "  fish_add_path ${INSTALL_DIR}"
        else
            warn "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> $profile"
        fi
        warn ""
        warn "Then restart your shell or run: source $profile"
    fi
}

# --- Release / asset resolution ---

get_latest_version() {
    local response
    response=$(curl -fsSL "${GITHUB_API}/releases/latest" 2>/dev/null) || {
        err "Failed to query GitHub API for latest release."
        err "Check your internet connection or specify a version with --version."
        exit 1
    }

    # Extract tag_name, strip leading 'v'
    local tag
    tag=$(echo "$response" | grep -o '"tag_name":[[:space:]]*"[^"]*"' | head -1 | grep -o '"v[^"]*"' | tr -d '"' | sed 's/^v//')

    if [[ -z "$tag" ]]; then
        err "Could not determine latest version from GitHub Releases."
        err "Please specify a version with --version."
        exit 1
    fi

    echo "$tag"
}

resolve_jaclang_version_from_release() {
    local release_tag="$1"
    local response
    response=$(curl -fsSL "${GITHUB_API}/releases/tags/v${release_tag}" 2>/dev/null) || {
        err "Failed to query GitHub API for release v${release_tag}."
        exit 1
    }

    # The jac binary asset is named jac-<jaclang version>-<os>-<arch>; the jaclang
    # version differs from the jaseci release version, so read it off the asset.
    local jac_version
    jac_version=$(echo "$response" | grep -o '"name":[[:space:]]*"jac-[^"]*"' | head -1 | grep -oE 'jac-[0-9]+\.[0-9]+\.[0-9]+' | sed 's/^jac-//')

    if [[ -z "$jac_version" ]]; then
        err "Could not determine the jac binary version from release v${release_tag} assets."
        err "The jac standalone binary may not have been built yet for this release."
        exit 1
    fi

    echo "$jac_version"
}

# --- Standalone binary installation (the only path) ---

install_standalone() {
    need_cmd "curl"

    # Resolve version (this is the jaseci/release version)
    if [[ -z "$VERSION" ]]; then
        info "Fetching latest version..."
        VERSION=$(get_latest_version)
        info "Latest release: ${VERSION}"
    fi

    info "Resolving jac binary version for release v${VERSION}..."
    local asset_version
    asset_version=$(resolve_jaclang_version_from_release "$VERSION")
    info "jac binary version: ${asset_version}"

    local asset="jac-${asset_version}-${OS}-${ARCH}"
    local download_url="https://github.com/${REPO}/releases/download/v${VERSION}/${asset}"
    local checksum_url="${download_url}.sha256"

    # Create install directory
    mkdir -p "$INSTALL_DIR"

    # Download to temp location
    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT

    info "Downloading ${asset}..."
    if ! curl -fsSL -o "${tmpdir}/${asset}" "$download_url"; then
        err "Failed to download: ${download_url}"
        err ""
        err "This could mean:"
        err "  - The version '${VERSION}' does not exist"
        err "  - A jac binary is not available for ${OS}-${ARCH}"
        err "  - Network issue"
        exit 1
    fi

    # Verify checksum if available
    if curl -fsSL -o "${tmpdir}/${asset}.sha256" "$checksum_url" 2>/dev/null; then
        info "Verifying checksum..."
        local expected actual
        expected=$(awk '{print $1}' "${tmpdir}/${asset}.sha256")

        if has_cmd sha256sum; then
            actual=$(sha256sum "${tmpdir}/${asset}" | awk '{print $1}')
        elif has_cmd shasum; then
            actual=$(shasum -a 256 "${tmpdir}/${asset}" | awk '{print $1}')
        else
            warn "Neither sha256sum nor shasum found, skipping checksum verification."
            actual="$expected"
        fi

        if [[ "$expected" != "$actual" ]]; then
            err "Checksum verification failed!"
            err "  Expected: ${expected}"
            err "  Got:      ${actual}"
            exit 1
        fi
        info "Checksum verified."
    else
        warn "Checksum file not available, skipping verification."
    fi

    # Install binary
    mv "${tmpdir}/${asset}" "${INSTALL_DIR}/jac"
    chmod +x "${INSTALL_DIR}/jac"

    ensure_on_path

    # Verify
    if has_cmd jac; then
        info ""
        info "Jac installed successfully!"
        jac --version 2>/dev/null || true
        info ""
        info "Get started:"
        info "  jac --help"
        info ""
    else
        warn "Binary installed to ${INSTALL_DIR}/jac but 'jac' is not on PATH."
        warn "Try restarting your shell or adding ~/.local/bin to PATH."
    fi
}

# --- Uninstall ---

do_uninstall() {
    local removed=false

    # Remove legacy uv-managed installations (pre-single-binary).
    if has_cmd uv; then
        if uv tool list 2>/dev/null | grep -q "^jaseci "; then
            info "Removing jaseci (legacy uv tool)..."
            uv tool uninstall jaseci
            removed=true
        fi
        if uv tool list 2>/dev/null | grep -q "^jaclang "; then
            info "Removing jaclang (legacy uv tool)..."
            uv tool uninstall jaclang
            removed=true
        fi
    fi

    # Remove standalone binary
    if [[ -f "${INSTALL_DIR}/jac" ]]; then
        info "Removing ${INSTALL_DIR}/jac..."
        rm -f "${INSTALL_DIR}/jac"
        removed=true
    fi

    if $removed; then
        info "Jac has been uninstalled."
    else
        warn "No Jac installation found."
    fi
}

# --- Main ---

main() {
    parse_args "$@"

    if $UNINSTALL; then
        do_uninstall
        exit 0
    fi

    detect_platform

    info "Detected platform: ${OS}-${ARCH}"

    install_standalone
}

main "$@"
