#!/usr/bin/env bash
# =============================================================================
# bhm — system-manifest.sh
# Captures a manifest of all installed packages and components so you can
# reproduce the same system environment on a new machine.
#
# Usage:
#   system-manifest capture              Save manifest to ./system-manifest/
#   system-manifest restore              Restore from ./system-manifest/
#   system-manifest capture /path/to/dir Save to custom path
#   system-manifest restore /path/to/dir Restore from custom path
# =============================================================================

set -o errexit
set -o nounset
set -o pipefail

MANIFEST_DIR="${2:-system-manifest}"
CMD="${1:-help}"

# ── Colors ──────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { echo -e " ${GREEN}[ OK ]${NC} $1"; }
warn() { echo -e " ${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e " ${RED}[FAIL]${NC} $1"; }
info() { echo -e " ${CYAN}[INFO]${NC} $1"; }

# ── Capture ─────────────────────────────────────────────────────────────

_capture() {
  local dir="$1"
  mkdir -p "$dir"
  echo ""
  info "Capturing system manifest to: ${dir}"
  echo ""

  # ── 1. DNF user-installed packages ────────────────────────────────────
  if command -v dnf &>/dev/null; then
    info "Capturing DNF packages..."
    if dnf repoquery --userinstalled 2>/dev/null | sort > "${dir}/dnf-packages.txt" 2>/dev/null; then
      ok "DNF: $(wc -l < "${dir}/dnf-packages.txt") user-installed packages"
    else
      # Fallback for systems without repoquery (older DNF)
      dnf list installed 2>/dev/null | awk 'NR>1 {print $1}' | sort > "${dir}/dnf-packages.txt" 2>/dev/null || true
      ok "DNF: $(wc -l < "${dir}/dnf-packages.txt") installed packages (all)"
    fi
    # Save DNF repos too
    if [[ -d /etc/yum.repos.d ]]; then
      cp -r /etc/yum.repos.d "${dir}/dnf-repos/" 2>/dev/null || true
      ok "DNF repos saved"
    fi
  else
    warn "DNF not found — skipping"
  fi

  # ── 2. Flatpak apps ───────────────────────────────────────────────────
  if command -v flatpak &>/dev/null; then
    info "Capturing Flatpak apps..."
    flatpak list --app --columns=application 2>/dev/null | sort > "${dir}/flatpak-apps.txt" || true
    if [[ -s "${dir}/flatpak-apps.txt" ]]; then
      ok "Flatpak: $(wc -l < "${dir}/flatpak-apps.txt") apps"
    else
      info "No Flatpak apps found"
    fi
  fi

  # ── 3. Docker images ──────────────────────────────────────────────────
  if command -v docker &>/dev/null; then
    info "Capturing Docker images..."
    docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null \
      | grep -v '<none>' | sort > "${dir}/docker-images.txt" || true
    if [[ -s "${dir}/docker-images.txt" ]]; then
      ok "Docker: $(wc -l < "${dir}/docker-images.txt") images"
    else
      info "No Docker images found"
    fi
    # Check if Docker Compose files exist in home
    local composes
    composes="$(find "$HOME" -maxdepth 3 -name 'docker-compose*' -o -name 'compose.yaml' 2>/dev/null || true)"
    if [[ -n "$composes" ]]; then
      echo "$composes" > "${dir}/docker-compose-files.txt"
      ok "Docker Compose files found (paths saved)"
    fi
  fi

  # ── 4. Podman images (alternative to Docker) ──────────────────────────
  if command -v podman &>/dev/null; then
    info "Capturing Podman images..."
    podman images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null \
      | grep -v '<none>' | sort > "${dir}/podman-images.txt" || true
    if [[ -s "${dir}/podman-images.txt" ]]; then
      ok "Podman: $(wc -l < "${dir}/podman-images.txt") images"
    fi
  fi

  # ── 5. VS Code extensions ────────────────────────────────────────────
  if command -v code &>/dev/null; then
    info "Capturing VS Code extensions..."
    code --list-extensions 2>/dev/null | sort > "${dir}/vscode-extensions.txt" || true
    if [[ -s "${dir}/vscode-extensions.txt" ]]; then
      ok "VS Code: $(wc -l < "${dir}/vscode-extensions.txt") extensions"
    fi
  fi
  # Cursor too
  if command -v cursor &>/dev/null; then
    info "Capturing Cursor extensions..."
    cursor --list-extensions 2>/dev/null | sort > "${dir}/cursor-extensions.txt" || true
  fi

  # ── 6. Systemd enabled services ──────────────────────────────────────
  info "Capturing systemd services..."
  systemctl list-unit-files --state=enabled --no-legend 2>/dev/null \
    | awk '{print $1}' | sort > "${dir}/systemd-enabled.txt" || true
  ok "Systemd: $(wc -l < "${dir}/systemd-enabled.txt") enabled services"

  # ── 7. NVM / Node / NPM global packages ──────────────────────────────
  if command -v nvm &>/dev/null || [[ -d "${NVM_DIR:-$HOME/.nvm}" ]]; then
    info "Capturing NVM/Node..."
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    # Current Node version
    command -v node &>/dev/null && node --version > "${dir}/node-version.txt" 2>/dev/null || true
    # NVM versions
    if [[ -f "$NVM_DIR/nvm.sh" ]]; then
      source "$NVM_DIR/nvm.sh"
      nvm list --no-colors 2>/dev/null > "${dir}/nvm-versions.txt" || true
    fi
    # NPM global packages
    if command -v npm &>/dev/null; then
      npm list -g --depth=0 2>/dev/null | tail -n +2 > "${dir}/npm-global.txt" || true
    fi
    ok "Node/NVM manifest saved"
  fi

  # ── 8. Pip global packages ───────────────────────────────────────────
  if command -v pip3 &>/dev/null; then
    info "Capturing pip packages..."
    pip3 list --format=columns 2>/dev/null | tail -n +3 > "${dir}/pip-packages.txt" || true
    if [[ -s "${dir}/pip-packages.txt" ]]; then
      ok "Pip: $(wc -l < "${dir}/pip-packages.txt") packages"
    fi
  fi

  # ── 9. Snap packages ─────────────────────────────────────────────────
  if command -v snap &>/dev/null; then
    info "Capturing Snap packages..."
    snap list 2>/dev/null | awk 'NR>1 {print $1}' | sort > "${dir}/snap-packages.txt" || true
    if [[ -s "${dir}/snap-packages.txt" ]]; then
      ok "Snap: $(wc -l < "${dir}/snap-packages.txt") packages"
    fi
  fi

  # ── 10. Rust / Cargo tools ───────────────────────────────────────────
  if command -v cargo &>/dev/null; then
    info "Capturing Cargo installed tools..."
    cargo install --list 2>/dev/null | grep '^ ' | awk '{print $1}' | sort -u \
      > "${dir}/cargo-tools.txt" || true
    if [[ -s "${dir}/cargo-tools.txt" ]]; then
      ok "Cargo: $(wc -l < "${dir}/cargo-tools.txt") tools"
    fi
  fi

  # ── 11. OS release info ──────────────────────────────────────────────
  cat /etc/os-release 2>/dev/null > "${dir}/os-release.txt" || true
  uname -a > "${dir}/kernel.txt" 2>/dev/null
  ok "OS release and kernel info saved"

  echo ""
  info "───────────────────────────────────────────────────────────────"
  info "Manifest saved to: ${dir}/"
  info "To restore on a new machine:"
  info "  $(basename "$0") restore ${dir}"
  info "───────────────────────────────────────────────────────────────"
  echo ""
}

# ── Restore ─────────────────────────────────────────────────────────────

_restore() {
  local dir="$1"

  if [[ ! -d "$dir" ]]; then
    fail "Manifest directory not found: ${dir}"
    echo ""
    echo "  Run capture first on the original machine:"
    echo "    $(basename "$0") capture ${dir}"
    echo ""
    exit 1
  fi

  echo ""
  info "Restoring system from manifest: ${dir}"
  echo ""
  warn "This will install packages on THIS machine. Continue?"
  read -r -p "  [y/N] " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    info "Cancelled."
    exit 0
  fi
  echo ""

  # ── 1. DNF packages ──────────────────────────────────────────────────
  if [[ -f "${dir}/dnf-packages.txt" ]] && [[ -s "${dir}/dnf-packages.txt" ]] && command -v dnf &>/dev/null; then
    info "Installing DNF packages ($(wc -l < "${dir}/dnf-packages.txt"))..."

    # Restore repos first
    if [[ -d "${dir}/dnf-repos/" ]]; then
      sudo cp -r "${dir}/dnf-repos/"* /etc/yum.repos.d/ 2>/dev/null || true
      ok "DNF repos restored"
    fi

    # Filter out packages that might already be installed
    sudo dnf5 install -y $(cat "${dir}/dnf-packages.txt") 2>&1 || \
      sudo dnf install -y $(cat "${dir}/dnf-packages.txt") 2>&1 || \
      warn "Some DNF packages failed to install (may be already installed or renamed)"
    ok "DNF packages installed"
  fi

  # ── 2. Flatpak apps ──────────────────────────────────────────────────
  if [[ -f "${dir}/flatpak-apps.txt" ]] && [[ -s "${dir}/flatpak-apps.txt" ]] && command -v flatpak &>/dev/null; then
    info "Installing Flatpak apps..."
    while IFS= read -r app; do
      [[ -z "$app" ]] && continue
      flatpak install -y flathub "$app" 2>/dev/null || warn "Failed to install Flatpak: ${app}"
    done < "${dir}/flatpak-apps.txt"
    ok "Flatpak apps installed"
  fi

  # ── 3. Docker images (pull, don't rebuild) ───────────────────────────
  if [[ -f "${dir}/docker-images.txt" ]] && [[ -s "${dir}/docker-images.txt" ]] && command -v docker &>/dev/null; then
    info "Pulling Docker images..."
    while IFS= read -r img; do
      [[ -z "$img" ]] && continue
      docker pull "$img" 2>/dev/null || warn "Failed to pull image: ${img}"
    done < "${dir}/docker-images.txt"
    ok "Docker images pulled"
  fi

  # ── 4. Podman images ─────────────────────────────────────────────────
  if [[ -f "${dir}/podman-images.txt" ]] && [[ -s "${dir}/podman-images.txt" ]] && command -v podman &>/dev/null; then
    info "Pulling Podman images..."
    while IFS= read -r img; do
      [[ -z "$img" ]] && continue
      podman pull "$img" 2>/dev/null || warn "Failed to pull Podman image: ${img}"
    done < "${dir}/podman-images.txt"
    ok "Podman images pulled"
  fi

  # ── 5. VS Code extensions ────────────────────────────────────────────
  if [[ -f "${dir}/vscode-extensions.txt" ]] && [[ -s "${dir}/vscode-extensions.txt" ]] && command -v code &>/dev/null; then
    info "Installing VS Code extensions..."
    while IFS= read -r ext; do
      [[ -z "$ext" ]] && continue
      code --install-extension "$ext" 2>/dev/null || warn "Failed to install extension: ${ext}"
    done < "${dir}/vscode-extensions.txt"
    ok "VS Code extensions installed"
  fi

  # ── 6. Cursor extensions ─────────────────────────────────────────────
  if [[ -f "${dir}/cursor-extensions.txt" ]] && [[ -s "${dir}/cursor-extensions.txt" ]] && command -v cursor &>/dev/null; then
    info "Installing Cursor extensions..."
    while IFS= read -r ext; do
      [[ -z "$ext" ]] && continue
      cursor --install-extension "$ext" 2>/dev/null || true
    done < "${dir}/cursor-extensions.txt"
    ok "Cursor extensions installed"
  fi

  # ── 7. Node/NPM global packages ──────────────────────────────────────
  if [[ -f "${dir}/npm-global.txt" ]] && [[ -s "${dir}/npm-global.txt" ]] && command -v npm &>/dev/null; then
    info "Installing NPM global packages..."
    while IFS= read -r line; do
      local pkg
      pkg="$(echo "$line" | awk '{print $1}')"
      [[ "$pkg" == "" || "$pkg" == "*" ]] && continue
      npm install -g "$pkg" 2>/dev/null || warn "Failed to install npm package: ${pkg}"
    done < "${dir}/npm-global.txt"
    ok "NPM global packages installed"
  fi

  # ── 8. Pip packages ──────────────────────────────────────────────────
  if [[ -f "${dir}/pip-packages.txt" ]] && [[ -s "${dir}/pip-packages.txt" ]] && command -v pip3 &>/dev/null; then
    info "Installing pip packages..."
    pip3 install -r "${dir}/pip-packages.txt" 2>/dev/null || warn "Some pip packages failed"
    ok "Pip packages installed"
  fi

  # ── 9. Snap packages ─────────────────────────────────────────────────
  if [[ -f "${dir}/snap-packages.txt" ]] && [[ -s "${dir}/snap-packages.txt" ]] && command -v snap &>/dev/null; then
    info "Installing Snap packages..."
    sudo snap install $(cat "${dir}/snap-packages.txt") 2>/dev/null || warn "Some Snap packages failed"
    ok "Snap packages installed"
  fi

  # ── 10. Cargo tools ──────────────────────────────────────────────────
  if [[ -f "${dir}/cargo-tools.txt" ]] && [[ -s "${dir}/cargo-tools.txt" ]] && command -v cargo &>/dev/null; then
    info "Installing Cargo tools..."
    while IFS= read -r tool; do
      [[ -z "$tool" ]] && continue
      cargo install "$tool" 2>/dev/null || warn "Failed to install cargo tool: ${tool}"
    done < "${dir}/cargo-tools.txt"
    ok "Cargo tools installed"
  fi

  echo ""
  ok "───────────────────────────────────────────────────────────────"
  ok "Restore complete! Log out and back in for all changes."
  ok "───────────────────────────────────────────────────────────────"
  echo ""
  info "Things to check manually:"
  info "  1. Docker: copy docker-compose files from manifest if needed"
  info "  2. Node: use 'nvm install' with versions from nvm-versions.txt"
  info "  3. Flatpak: some apps may need a reboot to appear"
  echo ""
}

# ── Help ────────────────────────────────────────────────────────────────

_help() {
  echo ""
  echo "bhm — system-manifest"
  echo ""
  echo "Usage:"
  echo "  system-manifest capture [dir]    Save system manifest"
  echo "  system-manifest restore [dir]    Restore packages from manifest"
  echo ""
  echo "Defaults:"
  echo "  dir = ./system-manifest/"
  echo ""
  echo "Examples:"
  echo "  # Capture on original machine, save into backup dir"
  echo "  system-manifest capture /home/backup/linux/gustavo/2026-06-26_11-11-37"
  echo ""
  echo "  # Restore on new machine"
  echo "  system-manifest restore /run/media/pendrive/system-manifest/"
  echo ""
}

# ── Main ────────────────────────────────────────────────────────────────

case "$CMD" in
  capture|cap) _capture "${2:-$MANIFEST_DIR}" ;;
  restore|res) _restore "${2:-$MANIFEST_DIR}" ;;
  *) _help && exit 1 ;;
esac
