# shellcheck shell=bash
# =============================================================================
# bhm — backup.sh
# rsync-based incremental backup engine with --link-dest
# Handles ALL rsync exit codes with appropriate actions
# =============================================================================

# shellcheck disable=SC2034,SC2153  # sourced, EXCLUDE_PATTERNS from config

# Rsync exit codes and their meanings
#   0  = Success
#   1  = Syntax or usage error
#   2  = Protocol incompatibility
#   3  = Errors selecting input/output files/dirs
#   5  = Error starting client-server protocol
#   6  = Daemon unable to append to log-file
#  10  = Error in socket I/O
#  11  = Error in file I/O
#  12  = Error in rsync protocol data stream
#  13  = Errors with program diagnostics
#  14  = Error in IPC code
#  20  = SIGUSR1 or SIGINT received
#  21  = waitpid() error
#  22  = Error allocating core memory buffers
#  23  = Partial transfer due to error
#  24  = Partial transfer due to vanished source files  (OK for backups)
#  25  = --max-delete limit stopped deletions
#  30  = Maximum timeout exceeded
#  35  = Timeout waiting for daemon connection

_RSYNC_OK_CODES=(0 24)       # Success or vanished-source (acceptable)
_RSYNC_PARTIAL_CODES=(23 25) # Partial — warning, not fatal
_RSYNC_FATAL_CODES=(1 2 3 5 6 10 11 12 13 14 20 21 22 30 35)

# --- Build the rsync exclude file ---------------------------------------

_build_exclude_file() {
  BHM_EXCLUDE_FILE="${BACKUP_DST}/.bhm_exclude_$$"
  local p
  for p in "${EXCLUDE_PATTERNS[@]}"; do
    # Strip leading/trailing whitespace, skip comments and empty
    p="${p#"${p%%[![:space:]]*}"}"
    p="${p%"${p##*[![:space:]]}"}"
    [[ -z "$p" || "$p" == \#* ]] && continue
    echo "$p"
  done > "$BHM_EXCLUDE_FILE"
}

_cleanup_exclude_file() {
  [[ -f "${BHM_EXCLUDE_FILE:-}" ]] && rm -f "$BHM_EXCLUDE_FILE"
}

# --- Encrypt snapshot after backup (if enabled) ---------------------------

_encrypt_snapshot_step() {
  [[ "${ENCRYPT_ENABLE:-no}" != "yes" ]] && return 0
  local snapshot_dir="$1"

  if [[ ! -d "$snapshot_dir" ]]; then
    log_warn "Encryption skipped: snapshot dir not found: ${snapshot_dir}"
    return 0
  fi

  local out_file="${snapshot_dir}.tar.gpg"
  echo ""
  info "Encrypting snapshot..."

  if _encrypt_snapshot "$snapshot_dir" "$out_file"; then
    _safe_remove "$snapshot_dir"
    ok "Snapshot encrypted: $(basename "$out_file")"
    log_info "Encrypted snapshot saved: ${out_file}"
  else
    warn "Encryption failed — unencrypted snapshot remains at: ${snapshot_dir}"
    log_error "Snapshot encryption failed for: ${snapshot_dir}"
  fi
  return 0
}

# --- Determine latest backup for --link-dest ----------------------------

_latest_backup_dir() {
  local dst="$1"
  local latest
  latest="$(find "$dst" -maxdepth 2 -type d -name '????-??-??_??-??-??' 2>/dev/null \
    | sort | tail -1)"
  echo "$latest"
}

# --- Check if rsync supports --info=progress2 ---------------------------

_rsync_supports_progress() {
  rsync --help 2>/dev/null | grep -q -- '--info' && return 0
  return 1
}

# --- Estimate backup size (dry-run, excludes applied) --------------------
# Uses the same rsync args as the real run so the estimate is accurate.

_estimate_backup_size() {
  local src="$1"
  local dest_tmp
  dest_tmp="$(mktemp -d)"

  # Build a temporary exclude file for the estimate
  local excl_file="${dest_tmp}/.exclude"
  local p
  for p in "${EXCLUDE_PATTERNS[@]}"; do
    p="${p#"${p%%[![:space:]]*}"}"
    p="${p%"${p##*[![:space:]]}"}"
    [[ -z "$p" || "$p" == \#* ]] && continue
    echo "$p"
  done > "$excl_file"

  # Build same args as the real backup (but --dry-run)
  local host="${BACKUP_HOST:-localhost}"
  local user="${BACKUP_USER:-$USER}"
  local latest_dir
  latest_dir="$(_latest_backup_dir "${BACKUP_DST}/${host}/${user}")"
  local rsync_args=("${RSYNC_OPTS[@]}")
  rsync_args+=(--exclude-from="$excl_file" --dry-run)
  [[ -n "$latest_dir" && -d "$latest_dir" ]] && rsync_args+=(--link-dest="$latest_dir")
  rsync_args+=("$src/" "${dest_tmp}/")

  info "Calculating backup size (scanning source)..." >&2
  local out
  out="$(rsync "${rsync_args[@]}" 2>&1)" || true
  rm -rf "$dest_tmp"

  # Parse total size from --stats output
  local total_size total_files
  total_size="$(echo "$out" | grep 'Total transferred file size' | grep -oP '[\d,]+' | tail -1 | tr -d ',')"
  total_files="$(echo "$out" | grep 'Number of files' | grep -oP '[\d,]+' | tail -1 | tr -d ',')"

  if [[ -z "$total_size" || "$total_size" == "0" ]]; then
    # Fallback: count files with du (slower but reliable)
    total_files="$(find "$src" -type f 2>/dev/null | wc -l)"
    total_size=""
  fi

  echo "${total_size:-0}|${total_files:-0}"
}

# --- Backup a single path (or full BACKUP_SRC) --------------------------

_backup_run() {
  local src="${1:-$BACKUP_SRC}"
  local timestamp
  timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"
  local host="${BACKUP_HOST:-localhost}"
  local user="${BACKUP_USER:-$USER}"
  local backup_dir="${BACKUP_DST}/${host}/${user}/${timestamp}"
  local latest_dir
  latest_dir="$(_latest_backup_dir "${BACKUP_DST}/${host}/${user}")"

  _ensure_dir "$backup_dir" || return 1
  _build_exclude_file

  # Build rsync args
  local rsync_args=("${RSYNC_OPTS[@]}")
  rsync_args+=(--exclude-from="$BHM_EXCLUDE_FILE")
  [[ -n "$latest_dir" && -d "$latest_dir" ]] && rsync_args+=(--link-dest="$latest_dir")
  _rsync_supports_progress && rsync_args+=(--info=progress2)
  rsync_args+=("$src/" "$backup_dir/")

  log_info "Starting backup: ${src} → ${backup_dir}"
  log_debug "rsync ${rsync_args[*]}"
  log_debug "link-dest: ${latest_dir:-none}"

  local start_epoch end_epoch duration
  start_epoch="$(date +%s)"

  set +e
  rsync "${rsync_args[@]}" 2>&1
  local rc=$?
  set -e

  end_epoch="$(date +%s)"
  duration=$(( end_epoch - start_epoch ))

  _cleanup_exclude_file

  # Interpret exit code
  if _rsync_is_ok "$rc"; then
    ok "Backup completed successfully in $(_format_seconds "$duration")"
    log_info "Backup saved to: ${backup_dir}"
    _backup_write_metadata "$backup_dir" "$rc" "$duration"
    _encrypt_snapshot_step "$backup_dir"
    echo "$backup_dir"
    return 0
  elif _rsync_is_partial "$rc"; then
    warn "Backup partially completed (rsync exit ${rc}) in $(_format_seconds "$duration")"
    log_warn "rsync exit code ${rc} — partial transfer"
    _backup_write_metadata "$backup_dir" "$rc" "$duration"
    _encrypt_snapshot_step "$backup_dir"
    echo "$backup_dir"
    return 2
  else
    fail "Backup FAILED (rsync exit ${rc}) after $(_format_seconds "$duration")"
    log_error "rsync exit code ${rc}: $(_rsync_explain "$rc")"
    _backup_write_metadata "$backup_dir" "$rc" "$duration"
    # Remove failed backup directory
    _safe_remove "$backup_dir"
    return 1
  fi
}

# --- Rsync exit code classification -------------------------------------

_rsync_is_ok() {
  local code="$1"
  local c
  for c in "${_RSYNC_OK_CODES[@]}"; do [[ "$c" == "$code" ]] && return 0; done
  return 1
}

_rsync_is_partial() {
  local code="$1"
  local c
  for c in "${_RSYNC_PARTIAL_CODES[@]}"; do [[ "$c" == "$code" ]] && return 0; done
  return 1
}

_rsync_explain() {
  local code="$1"
  case "$code" in
     0) echo "Success" ;;
     1) echo "Syntax or usage error" ;;
     2) echo "Protocol incompatibility" ;;
     3) echo "Errors selecting input/output files/dirs" ;;
     4) echo "Requested action not supported" ;;
     5) echo "Error starting client-server protocol" ;;
     6) echo "Daemon unable to append to log-file" ;;
    10) echo "Error in socket I/O" ;;
    11) echo "Error in file I/O" ;;
    12) echo "Error in rsync protocol data stream" ;;
    13) echo "Errors with program diagnostics" ;;
    14) echo "Error in IPC code" ;;
    20) echo "Interrupted (SIGUSR1/SIGINT)" ;;
    21) echo "waitpid() error" ;;
    22) echo "Error allocating core memory buffers" ;;
    23) echo "Partial transfer due to error" ;;
    24) echo "Partial transfer: some files vanished during sync (normal)" ;;
    25) echo "Partial transfer: --max-delete limit reached" ;;
    30) echo "Maximum timeout exceeded" ;;
    35) echo "Timeout waiting for daemon connection" ;;
     *) echo "Unknown error code ${code}" ;;
  esac
}

# --- Write backup metadata ----------------------------------------------

_backup_write_metadata() {
  local dir="$1" rc="$2" duration="$3"
  local meta="${dir}/.bhm_metadata"
  cat > "$meta" <<EOF
# bhm backup metadata
created=$(date -Iseconds)
host=${BACKUP_HOST:-localhost}
user=${BACKUP_USER:-$USER}
source=${BACKUP_SRC}
rsync_exit_code=${rc}
duration_seconds=${duration}
bhm_version=2.0.0
EOF
}

# --- List available backups ---------------------------------------------

_backup_list_snapshots() {
  local host="${BACKUP_HOST:-localhost}"
  local user="${BACKUP_USER:-$USER}"
  local base="${BACKUP_DST}/${host}/${user}"
  local snap name date size

  if [[ ! -d "$base" ]]; then
    info "No backups found at ${base}"
    return 0
  fi

  printf '%-22s %-12s %s\n' 'SNAPSHOT' 'SIZE' 'DATE'
  printf '%.0s-' {1..60}
  echo

  # List unencrypted timestamp directories
  while IFS= read -r -d '' snap; do
    name="$(basename "$snap")"
    size="$(du -sh "$snap" 2>/dev/null | awk '{print $1}')"
    date="$(stat -c '%y' "$snap" 2>/dev/null | cut -d. -f1)"
    printf '%-22s %-12s %s\n' "$name" "$size" "$date"
  done < <(find "$base" -maxdepth 1 -type d -name '????-??-??_??-??-??' -print0 | sort -rz)

  # List encrypted .tar.gpg snapshots
  while IFS= read -r -d '' snap; do
    name="$(basename "$snap" .tar.gpg)"
    size="$(du -h "$snap" 2>/dev/null | awk '{print $1}')"
    date="$(stat -c '%y' "$snap" 2>/dev/null | cut -d. -f1)"
    printf '%-22s %-12s %s [encrypted]\n' "$name" "$size" "$date"
  done < <(find "$base" -maxdepth 1 -type f -name '????-??-??_??-??-??.tar.gpg' -print0 | sort -rz)
}
