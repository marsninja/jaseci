#!/usr/bin/env bash
# Jac single-binary installer (in-process libpython embed).
#
# Installs a self-contained `jac` native executable that requires NO system
# Python, uv, or pip. This is independent of the uv-based scripts/install.sh;
# the two installers can coexist.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/jaseci-labs/jaseci/main/scripts/install-binary.sh | bash
#   curl -fsSL .../install-binary.sh | bash -s -- --version 0.16.7
#   curl -fsSL .../install-binary.sh | bash -s -- --uninstall
#
# Options:
#   --version V     install a specific jaclang version (default: latest release)
#   --bin-dir DIR   install location (default: ~/.local/bin)
#   --uninstall     remove the installed binary (and optionally the rt cache)

set -euo pipefail

REPO="jaseci-labs/jaseci"
BIN_DIR="${HOME}/.local/bin"
VERSION=""
UNINSTALL=0

err()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[36m==>\033[0m %s\n' "$*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version)   VERSION="${2:-}"; shift 2 ;;
    --bin-dir)   BIN_DIR="${2:-}"; shift 2 ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help)   sed -n '2,20p' "$0"; exit 0 ;;
    *) err "unknown option: $1" ;;
  esac
done

# ---- platform detection (v1: linux-x86_64 only) ----------------------------
detect_platform() {
  local os arch
  os="$(uname -s)"; arch="$(uname -m)"
  if [ "$os" != "Linux" ]; then
    err "this installer currently supports Linux only (got: $os). Use scripts/install.sh (uv) instead."
  fi
  case "$arch" in
    x86_64|amd64) echo "linux-x86_64" ;;
    *) err "unsupported architecture: $arch (v1 ships linux-x86_64 only)" ;;
  esac
}

uninstall() {
  local target="${BIN_DIR}/jac"
  if [ -f "$target" ]; then
    rm -f "$target"
    info "removed $target"
  else
    info "no binary at $target"
  fi
  local rt="${XDG_CACHE_HOME:-$HOME/.cache}/jac/rt"
  if [ -d "$rt" ]; then
    printf 'Also remove the extracted runtime cache at %s? [y/N] ' "$rt"
    read -r ans </dev/tty || ans="n"
    case "$ans" in [yY]*) rm -rf "$rt"; info "removed $rt" ;; esac
  fi
  exit 0
}

[ "$UNINSTALL" = "1" ] && uninstall

PLATFORM="$(detect_platform)"
command -v curl >/dev/null 2>&1 || err "curl is required"

# ---- resolve version -------------------------------------------------------
if [ -z "$VERSION" ]; then
  info "resolving latest release…"
  VERSION="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | grep -oP '"tag_name"\s*:\s*"\K[^"]+' | head -1 | sed 's/^jaclang-//; s/^v//')"
  [ -n "$VERSION" ] || err "could not resolve latest version; pass --version"
fi
info "jaclang version: ${VERSION}"

ASSET="jac-${VERSION}-${PLATFORM}"
BASE="https://github.com/${REPO}/releases/download/jaclang-${VERSION}"

# ---- download + verify -----------------------------------------------------
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
info "downloading ${ASSET}…"
curl -fSL --progress-bar -o "${TMP}/${ASSET}" "${BASE}/${ASSET}" \
  || err "download failed: ${BASE}/${ASSET}"

if curl -fsSL -o "${TMP}/${ASSET}.sha256" "${BASE}/${ASSET}.sha256" 2>/dev/null; then
  info "verifying checksum…"
  ( cd "$TMP" && sha256sum -c "${ASSET}.sha256" >/dev/null ) \
    || err "checksum verification FAILED"
  info "checksum OK"
else
  info "no .sha256 published; skipping checksum verification"
fi

# ---- install ---------------------------------------------------------------
mkdir -p "$BIN_DIR"
install -m 0755 "${TMP}/${ASSET}" "${BIN_DIR}/jac"
info "installed: ${BIN_DIR}/jac"

# ---- PATH guidance ---------------------------------------------------------
case ":${PATH}:" in
  *":${BIN_DIR}:"*) ;;
  *)
    info "add ${BIN_DIR} to your PATH:"
    # shellcheck disable=SC2016  # literal $PATH is intentional in the printed hint
    printf '    export PATH="%s:$PATH"\n' "$BIN_DIR"
    ;;
esac

info "done. Try: jac --version"
