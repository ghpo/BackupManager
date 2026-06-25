# shellcheck shell=bash
# =============================================================================
# bhm — logging.sh
# Syslog-style leveled logger with log rotation
# =============================================================================

# shellcheck disable=SC2034  # sourced, not executed

declare -gA BHM_LOG_LEVELS
BHM_LOG_LEVELS=([DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3)

_log_level_num() {
  local level="${1:-INFO}"
  echo "${BHM_LOG_LEVELS[$level]:-1}"
}

_log_init() {
  local log_dir
  log_dir="${LOG_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/bhm/logs}"
  mkdir -p "$log_dir" || return 1
  BHM_LOG_FILE="$log_dir/bhm_$(date '+%Y%m%d').log"
  touch "$BHM_LOG_FILE" 2>/dev/null || return 1
  _log_rotate_if_needed
}

_log_rotate_if_needed() {
  local max_size="${LOG_MAX_SIZE:-5242880}"
  local max_files="${LOG_MAX_FILES:-14}"
  local f size

  # Rotate current if oversized
  if [[ -f "$BHM_LOG_FILE" ]]; then
    size=$(stat -c%s "$BHM_LOG_FILE" 2>/dev/null || echo 0)
    if (( size > max_size )); then
      mv "$BHM_LOG_FILE" "${BHM_LOG_FILE}.1"
      touch "$BHM_LOG_FILE"
    fi
  fi

  # Prune old rotated logs (keep max_files)
  for f in "${BHM_LOG_FILE}".*; do
    [[ -f "$f" ]] || continue
    local num="${f##*.}"
    if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= max_files )); then
      rm -f "$f"
    fi
  done
}

_log_msg() {
  local level="$1"
  shift
  local msg="$*"
  local pid=$$
  local ts
  ts="$(date '+%b %d %H:%M:%S')"
  local level_num
  level_num="$(_log_level_num "$level")"
  local current_level_num
  current_level_num="$(_log_level_num "${LOG_LEVEL:-INFO}")"

  # Skip messages below configured level
  if (( level_num < current_level_num )); then
    return 0
  fi

  local formatted="${ts} ${BACKUP_HOST:-localhost} bhm[${pid}]: ${level}: ${msg}"

  # Always to stderr for WARN/ERROR, stdout for DEBUG/INFO
  if (( level_num >= 3 )); then
    echo "$formatted" >&2
  else
    echo "$formatted"
  fi

  # File log (all levels)
  if [[ -n "${BHM_LOG_FILE:-}" ]]; then
    echo "$formatted" >> "$BHM_LOG_FILE" 2>/dev/null || true
  fi
}

log_debug() { _log_msg "DEBUG" "$@"; }
log_info()  { _log_msg "INFO"  "$@"; }
log_warn()  { _log_msg "WARN"  "$@" >&2; }
log_error() { _log_msg "ERROR" "$@" >&2; }

# Error handler for trap
_log_catch_error() {
  local rc=$?
  local line=$1
  log_error "Command at line ${line} exited with code ${rc}"
}

# Print a one-line summary line for the final report
_log_summary() {
  local duration="$1"
  local status="$2"
  local details="$3"
  local line
  line="$(printf '=%.0s' {1..72})"
  log_info "$line"
  log_info "BACKUP SUMMARY: status=${status} duration=${duration}s ${details}"
  log_info "$line"
}
