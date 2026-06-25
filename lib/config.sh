# shellcheck shell=bash
# =============================================================================
# bhm — config.sh
# Configuration loading from layered sources (system → user → CLI override)
# =============================================================================

# shellcheck disable=SC2034  # sourced, not executed

# --- Config load order (later overrides earlier) -------------------------
#  1. Internal defaults (hardcoded in lib/config.sh)
#  2. /etc/bhm/bhm.conf
#  3. $XDG_CONFIG_HOME/bhm/bhm.conf  (or ~/.config/bhm/bhm.conf)
#  4. CLI flags (set by caller before calling _config_load)

_bhm_conf_files_loaded=()

# Initialize all config vars with internal defaults
_config_set_defaults() {
  # Source / destination (respect pre-set env vars)
  BACKUP_SRC="${BACKUP_SRC:-$HOME}"
  BACKUP_DST="${XDG_DATA_HOME:-$HOME/.local/share}/bhm/backups"
  BACKUP_HOST="$(hostname -s 2>/dev/null || echo 'localhost')"
  BACKUP_USER="${USER}"

  # Retention
  RETENTION_DAILY="7"
  RETENTION_WEEKLY="4"
  RETENTION_MONTHLY="3"

  # Rsync
  RSYNC_OPTS=(--archive --hard-links --xattrs --acls --one-file-system --delete --delete-excluded --partial --human-readable --stats)

  # Excludes
  EXCLUDE_PATTERNS=(
    node_modules/ vendor/ __pycache__/ *.pyc *.pyo target/ build/ dist/ .next/
    .cache/ cache/ .local/share/Trash/
    .local/share/bhm/
    *.tmp *.temp ~* .~* *.swp *.swo core.* Thumbs.db .DS_Store
    .env .env.* *.pem *.key
    .idea/ .vscode/ *.sublime-*
    *.log npm-debug.log* yarn-error.log* .npm/ .yarn/
    cargo/registry/ go/pkg/mod/ .m2/repository/
    *.vdi *.vmdk *.qcow2 .vagrant/
  )

  # Btrfs
  BTRFS_ENABLE="no"
  BTRFS_SUBVOL=""
  BTRFS_SNAPSHOT_PREFIX="bhm-"
  BTRFS_RETENTION="7"

  # Encryption
  ENCRYPT_ENABLE="no"
  ENCRYPT_ALGO="AES256"
  ENCRYPT_PASSWORD_FILE=""

  # Verify
  VERIFY_CHECKSUM="yes"
  VERIFY_SAMPLE_PCT="5"

  # Logging
  LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/bhm/logs"
  LOG_LEVEL="INFO"
  LOG_MAX_FILES="14"
  LOG_MAX_SIZE="5242880"

  # Notifications
  NOTIFY_ON_SUCCESS="no"
  NOTIFY_ON_FAILURE="yes"
}

# Load a single config file safely, return 0 if loaded
_config_load_file() {
  local path="$1"
  if [[ -f "$path" ]] && [[ -r "$path" ]]; then
    # shellcheck source=/dev/null
    source "$path" || {
      log_warn "Config file has errors: ${path}"
      return 1
    }
    _bhm_conf_files_loaded+=("$path")
    log_debug "Loaded config: ${path}"
    return 0
  fi
  # File not found is not an error — config is optional
  return 0
}

# Load all configuration layers
_config_load() {
  _config_set_defaults

  # Load path overrides from backwards-compat env
  local sys_conf="/etc/bhm/bhm.conf"
  local user_conf="${XDG_CONFIG_HOME:-$HOME/.config}/bhm/bhm.conf"

  _config_load_file "$sys_conf" || true
  _config_load_file "$user_conf" || true
}

# Print effective configuration (for --dry-run / --verbose)
_config_dump() {
  local key
  local skip_keys='^(_|BASH_SOURCE|EXCLUDE_PATTERNS|RSYNC_OPTS|ENCRYPT_PASSWORD_FILE)'
  echo "# Loaded from: ${_bhm_conf_files_loaded[*]:-(defaults)}"
  echo ""
  # Simple key=value vars
  while IFS='=' read -r key _; do
    key="${key%%\[*}"
    [[ "$key" =~ $skip_keys ]] && continue
    declare -p "$key" 2>/dev/null | sed "s/^declare -[a-z]* //"
  done < <(compgen -v | grep -E '^(BACKUP_|RETENTION_|BTRFS_|ENCRYPT_|VERIFY_|LOG_|NOTIFY_)')
  echo ""
  echo "RSYNC_OPTS=(${RSYNC_OPTS[*]})"
  echo "EXCLUDE_PATTERNS=(${EXCLUDE_PATTERNS[*]})"
}

# Validate config — return non-zero if critical values are missing
_config_validate() {
  local errors=0
  [[ -z "$BACKUP_SRC" ]] && log_error "BACKUP_SRC is not set" && ((errors++))
  [[ -z "$BACKUP_DST" ]] && log_error "BACKUP_DST is not set" && ((errors++))
  [[ ! -d "$BACKUP_SRC" ]] && log_error "BACKUP_SRC does not exist: ${BACKUP_SRC}" && ((errors++))
  return "$errors"
}

# Detect if BACKUP_DST is still the internal default (never customized)
_config_is_default_dst() {
  local default="${XDG_DATA_HOME:-$HOME/.local/share}/bhm/backups"
  [[ "$BACKUP_DST" == "$default" ]]
}

# Write user config file, preserving any existing content
_config_write_user() {
  local key="$1" value="$2"
  local conf_dir="${XDG_CONFIG_HOME:-$HOME/.config}/bhm"
  local conf_file="${conf_dir}/bhm.conf"

  _ensure_dir "$conf_dir" || return 1

  if [[ -f "$conf_file" ]] && grep -q "^${key}=" "$conf_file" 2>/dev/null; then
    # Update existing key
    sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$conf_file"
  else
    # Append to file (or create new)
    echo "${key}=\"${value}\"" >> "$conf_file"
  fi

  log_info "Saved ${key}=${value} to ${conf_file}"
}

# Prompt user for a destination path (shared by first-run and change prompts)
_config_prompt_dest() {
  local current="$1"
  local prompt_label="${2:-Backup destination path}"

  local suggestions=()
  local d
  for d in "$HOME" /media /mnt /run/media/"$USER"; do
    [[ -d "$d" ]] && suggestions+=("$d")
  done

  if [[ ${#suggestions[@]} -gt 0 ]]; then
    echo "  Detected mount points: ${suggestions[*]}"
  fi

  local user_dst
  read -r -p "${prompt_label} [${current}]: " user_dst
  user_dst="${user_dst:-$current}"
  user_dst="${user_dst/#\~/$HOME}"

  # Verify it exists or ask to create
  if [[ ! -d "$user_dst" ]]; then
    local parent
    parent="$(dirname "$user_dst")"
    if [[ -d "$parent" ]]; then
      if _confirm "'${user_dst}' does not exist. Create it?" y; then
        mkdir -p "$user_dst"
      else
        warn "Using current destination instead."
        user_dst="$current"
      fi
    else
      warn "Parent directory '${parent}' does not exist. Using current."
      user_dst="$current"
    fi
  fi

  echo "$user_dst"
}

# Interactive first-run setup wizard (also asks on each backup if stdin is a terminal)
_config_first_run() {
  local conf_dir="${XDG_CONFIG_HOME:-$HOME/.config}/bhm"
  local conf_file="${conf_dir}/bhm.conf"

  # Skip prompts if stdin is not a terminal (cron, pipes, scripts)
  if [[ ! -t 0 ]]; then
    return 0
  fi

  local configured=0
  [[ -f "$conf_file" ]] && grep -q "^BACKUP_DST=" "$conf_file" 2>/dev/null && configured=1

  echo ""

  if (( configured )); then
    # Already configured — offer to change destination
    echo "  Current destination: ${BACKUP_DST}"
    if _confirm "Change destination?" n; then
      echo ""
      local user_dst
      user_dst="$(_config_prompt_dest "$BACKUP_DST")"
      _config_write_user "BACKUP_DST" "$user_dst"
      echo ""
    fi

    # Also offer to change source
    echo "  Current source: ${BACKUP_SRC}"
    if _confirm "Change source directory?" n; then
      local user_src
      read -r -p "  New source path [${BACKUP_SRC}]: " user_src
      user_src="${user_src:-$BACKUP_SRC}"
      user_src="${user_src/#\~/$HOME}"
      if [[ -d "$user_src" ]]; then
        _config_write_user "BACKUP_SRC" "$user_src"
        BACKUP_SRC="$user_src"
      else
        warn "Directory does not exist: ${user_src}. Keeping current."
      fi
      echo ""
    fi

    echo ""
    return 0
  else
    # First run — full wizard
    ok "Welcome to Backup Home Manager!"
    echo ""
    echo "  This is your first run. Let's configure where backups go."
    echo ""
    echo "  Default destination: ${BACKUP_DST}"
    echo "  (inside your home directory — safe but not external)"
    echo ""

    local user_dst
    user_dst="$(_config_prompt_dest "$BACKUP_DST")"

    local user_src="${BACKUP_SRC}"
    echo ""
    info "Backup source (what to back up): ${BACKUP_SRC}"
    read -r -p "  Change source directory? (leave empty for default) [${BACKUP_SRC}]: " user_src
    user_src="${user_src:-$BACKUP_SRC}"
    user_src="${user_src/#\~/$HOME}"

    local src_line
    if [[ "$user_src" != "$HOME" ]]; then
      src_line="BACKUP_SRC=\"${user_src}\""
    else
      src_line="# BACKUP_SRC=\"\${HOME}\""
    fi

    # Write config file
    _ensure_dir "$conf_dir" || return 1

    cat > "$conf_file" <<CONFEOF
# bhm — Backup Home Manager user configuration
# Created by first-run wizard on $(date '+%Y-%m-%d %H:%M')
# Uncomment and edit any value below as needed.

# Backup destination (external drive, NAS mount, etc.)
BACKUP_DST="${user_dst}"

# Source directory to back up (default: $HOME)
${src_line}

# Retention: keep N daily, weekly, monthly snapshots
# RETENTION_DAILY=7
# RETENTION_WEEKLY=4
# RETENTION_MONTHLY=3
CONFEOF

    chmod 600 "$conf_file" 2>/dev/null || true
    ok "Configuration saved to ${conf_file}"

    # Re-read config so BACKUP_DST takes effect immediately
    _config_set_defaults
    _config_load_file "$conf_file" || true
  fi

  echo ""
  info "Backup will go to: ${BACKUP_DST}"
  echo ""
  return 0
}
