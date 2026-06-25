#!/usr/bin/env bash
# =============================================================================
# bhm — Install Script
# =============================================================================
#
# Usage:
#   ./install.sh              # Install to /usr/local (default)
#   PREFIX=~/.local ./install.sh   # User-local install
#   sudo ./install.sh         # System-wide install
# =============================================================================

set -o errexit
set -o nounset
set -o pipefail

PREFIX="${PREFIX:-/usr/local}"
BHM_LIBDIR="${PREFIX}/lib/bhm"
BHM_BINDIR="${PREFIX}/bin"
BHM_ETCDIR="${DESTDIR:-/etc}/bhm"
BHM_HOME="$(cd "$(dirname "$0")" && pwd)"

echo "bhm — Backup Home Manager Installer"
echo "  Prefix: ${PREFIX}"
echo ""

# Check for required commands
for cmd in rsync bash; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: Required command '${cmd}' not found."
    exit 1
  fi
done

# Create directories
mkdir -p "$BHM_BINDIR" "$BHM_LIBDIR" "$BHM_ETCDIR"

# Install main binary
install -m 755 "${BHM_HOME}/bhm" "${BHM_BINDIR}/bhm"
echo "  ✓ ${BHM_BINDIR}/bhm"

# Install libraries
for lib in "${BHM_HOME}/lib/"*.sh; do
  install -m 644 "$lib" "${BHM_LIBDIR}/"
  echo "  ✓ ${BHM_LIBDIR}/$(basename "$lib")"
done

# Install system config (if not exists)
if [[ -f "${BHM_ETCDIR}/bhm.conf" ]]; then
  echo "  - ${BHM_ETCDIR}/bhm.conf (already exists, skipping)"
else
  install -m 644 "${BHM_HOME}/etc/bhm.conf" "${BHM_ETCDIR}/bhm.conf"
  echo "  ✓ ${BHM_ETCDIR}/bhm.conf"
fi

# Create user config directory
USER_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bhm"
if [[ ! -f "${USER_CONFIG_DIR}/bhm.conf" ]]; then
  mkdir -p "$USER_CONFIG_DIR"
  cp "${BHM_HOME}/etc/bhm.conf" "${USER_CONFIG_DIR}/bhm.conf"
  echo "  ✓ ${USER_CONFIG_DIR}/bhm.conf (user default)"
fi

echo ""
echo "Installation complete."
echo "Run 'bhm help' to get started."
