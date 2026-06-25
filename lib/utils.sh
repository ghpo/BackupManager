# shellcheck shell=bash
# =============================================================================
# bhm — utils.sh
# Shared utilities, I/O helpers, and formatting
# =============================================================================

# shellcheck disable=SC2034  # sourced, not executed

# --- Terminal output -----------------------------------------------------

_has_color() {
  [[ -t 1 ]] && [[ -n "${TERM:-}" ]] && [[ "$TERM" != dumb ]]
}

_bhm_echo() {
  local color="$1" label="$2"; shift 2
  if _has_color; then
    printf '\033[%sm[%s]\033[0m %s\n' "$color" "$label" "$*"
  else
    printf '[%s] %s\n' "$label" "$*"
  fi
}

ok()   { _bhm_echo '32'  ' OK ' "$@"; }
info() { _bhm_echo '34;1' 'INFO' "$@"; }
warn() { _bhm_echo '33'  'WARN' "$@"; }
fail() { _bhm_echo '31;1' 'FAIL' "$@"; }

# --- Duration formatting -------------------------------------------------

_format_seconds() {
  local s=$1
  local h m
  h=$((s / 3600)); s=$((s % 3600))
  m=$((s / 60));   s=$((s % 60))
  (( h > 0 )) && printf '%dh%02dm%02ds' "$h" "$m" "$s" && return
  (( m > 0 )) && printf '%dm%02ds'       "$m" "$s" && return
  printf '%ds' "$s"
}

# --- Size formatting -----------------------------------------------------

_format_bytes() {
  local bytes=$1
  LC_ALL=C numfmt --to=iec-i --suffix=B "$bytes" 2>/dev/null ||
    echo "${bytes}B"
}

# --- File helpers --------------------------------------------------------

_ensure_dir() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir" || {
      log_error "Cannot create directory: $dir"
      return 1
    }
  fi
}

_safe_remove() {
  local path="$1"
  [[ -z "$path" ]] && return 1
  [[ ! -e "$path" ]] && return 0
  rm -rf "$path" || {
    log_error "Failed to remove: $path"
    return 1
  }
}

# --- Checksum helpers ----------------------------------------------------

_checksum_file() {
  local file="$1"
  if command -v sha256sum &>/dev/null; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum &>/dev/null; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    md5sum "$file" | awk '{print $1}'
  fi
}

# --- Confirm prompt ------------------------------------------------------

_confirm() {
  local prompt="$1"
  local default="${2:-n}"
  local yn
  case "$default" in
    y|Y) prompt_str="$prompt [Y/n] " ;;
    *)   prompt_str="$prompt [y/N] " ;;
  esac
  read -r -p "$prompt_str" yn
  yn="${yn:-$default}"
  [[ "$yn" =~ ^[yY](es)?$ ]]
}

# --- Version stamp -------------------------------------------------------

_bhm_version() {
  cat <<'VERSION'
bhm 2.0.0 — Backup Home Manager
Copyright (C) 2026  Gustavo Oliveira <ghpo@protonmail.com>
License: MIT <https://opensource.org/license/mit>
VERSION
}
