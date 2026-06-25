# shellcheck shell=bash
# =============================================================================
# bhm — restore.sh
# Full and partial restore with safety checks
# =============================================================================

# shellcheck disable=SC2034,SC2153  # sourced

# --- List files in a backup snapshot ------------------------------------

_restore_list_files() {
  local snapshot="$1"
  local pattern="${2:-}"

  if [[ ! -d "$snapshot" ]]; then
    log_error "Snapshot directory not found: ${snapshot}"
    return 1
  fi

  if [[ -n "$pattern" ]]; then
    find "$snapshot" -not -path '*/\.bhm_*' -path "*${pattern}*" 2>/dev/null \
      | sed "s|^${snapshot}/||" \
      | sort
  else
    find "$snapshot" -not -path '*/\.bhm_*' -type f 2>/dev/null \
      | sed "s|^${snapshot}/||" \
      | sort
  fi
}

# --- Show stats about a backup (dry-run for restore) --------------------

_restore_dry_run() {
  local snapshot="$1"
  local target="${2:-$BACKUP_SRC}"
  local extra_args=()

  info "Dry-run restore preview: ${snapshot} → ${target}"
  rsync --archive --dry-run --stats --human-readable \
    "${extra_args[@]}" \
    "${snapshot}/" "${target}/" 2>&1
  echo ""
  info "Use --no-dry-run to execute this restore."
}

# --- Execute restore ----------------------------------------------------

_restore_run() {
  local snapshot="$1"
  local target="${2:-$BACKUP_SRC}"
  local partial_path="${3:-}"

  if [[ ! -d "$snapshot" ]]; then
    log_error "Snapshot directory not found: ${snapshot}"
    return 1
  fi

  if [[ ! -d "$target" ]]; then
    log_error "Target directory not found: ${target}"
    return 1
  fi

  # Resolve snapshot to absolute path
  snapshot="$(cd "$snapshot" && pwd)"

  local src="${snapshot}/"
  local restore_label="full"

  # Partial restore: only sync a sub-path
  if [[ -n "$partial_path" ]]; then
    partial_path="${partial_path#/}"  # strip leading slash
    src="${snapshot}/${partial_path}"
    if [[ ! -e "$src" ]]; then
      log_error "Path not found in snapshot: ${partial_path}"
      return 1
    fi
    restore_label="partial (${partial_path})"
    # Ensure target subdir exists
    local target_subdir="${target}/${partial_path%/*}"
    _ensure_dir "$target_subdir" || return 1
  fi

  log_info "Starting ${restore_label} restore: ${src} → ${target}"

  # Safety: add trailing slash to both
  [[ "$src" != */ ]] && src="${src}/"
  local tgt="$target"
  [[ "$tgt" != */ ]] && tgt="${tgt}/"

  local start_epoch end_epoch duration
  start_epoch="$(date +%s)"

  set +e
  rsync --archive --hard-links --xattrs --acls \
    --partial --progress --human-readable --stats \
    "${src}" "${tgt}" 2>&1
  local rc=$?
  set -e

  end_epoch="$(date +%s)"
  duration=$(( end_epoch - start_epoch ))

  if _rsync_is_ok "$rc"; then
    ok "${restore_label^} restore completed in $(_format_seconds "$duration")"
    log_info "Restore from ${snapshot} to ${target} succeeded"
    return 0
  elif _rsync_is_partial "$rc"; then
    warn "${restore_label^} restore partially completed (rsync exit ${rc})"
    return 2
  else
    fail "${restore_label^} restore FAILED (rsync exit ${rc})"
    log_error "rsync exit code ${rc}: $(_rsync_explain "$rc")"
    return 1
  fi
}

# --- Restore entry point (CLI) ------------------------------------------

_restore_cmd() {
  local snapshot="" target="" dry_run="yes" partial=""
  local OPTS

  OPTS="$(getopt -o s:t:d --long snapshot:,target:,no-dry-run,path: -n 'bhm restore' -- "$@")" || return 1
  eval set -- "$OPTS"

  while true; do
    case "$1" in
      -s|--snapshot) snapshot="$2"; shift 2 ;;
      -t|--target)   target="$2"; shift 2 ;;
      -d|--no-dry-run) dry_run="no"; shift ;;
      --path)        partial="$2"; shift 2 ;;
      --) shift; break ;;
    esac
  done

  # Auto-select latest snapshot
  if [[ -z "$snapshot" ]]; then
    snapshot="$(_latest_backup_dir "${BACKUP_DST}/${BACKUP_HOST:-localhost}/${BACKUP_USER:-$USER}")"
    if [[ -z "$snapshot" ]]; then
      log_error "No snapshots found and --snapshot not provided"
      return 1
    fi
    info "Auto-selected latest snapshot: $(basename "$snapshot")"
  fi

  target="${target:-$BACKUP_SRC}"

  if [[ "$dry_run" == "yes" ]]; then
    _restore_dry_run "$snapshot" "$target"
    info "Pass --no-dry-run to execute the restore"
    return 0
  fi

  _confirm "Restore $(basename "$snapshot") to ${target}${partial:+/${partial}}? This may OVERWRITE existing files." || {
    info "Restore cancelled."
    return 0
  }

  _restore_run "$snapshot" "$target" "$partial"
}
