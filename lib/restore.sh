# shellcheck shell=bash
# =============================================================================
# bhm — restore.sh
# Full and partial restore with safety checks
# =============================================================================

# shellcheck disable=SC2034,SC2153  # sourced

# --- Resolve a snapshot path to a usable directory --------------------------
# Handles both unencrypted (dir) and encrypted (.tar.gpg) snapshots.
# For encrypted, decrypts to a temp dir that is cleaned up on shell exit.

_restore_resolve_snapshot() {
  local snap="$1"

  if [[ -d "$snap" ]]; then
    echo "$snap"
    return 0
  fi

  if [[ -f "$snap" ]] && [[ "$snap" == *.tar.gpg ]]; then
    local tmpdir
    tmpdir="$(mktemp -d "/tmp/bhm_restore_XXXXXX")"
    echo ""
    info "Decrypting snapshot: $(basename "$snap")"

    if _encrypt_decrypt_extract "$snap" "$tmpdir"; then
      # Find the actual snapshot dir inside the extracted tar
      local inner
      inner="$(find "$tmpdir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)"
      if [[ -n "$inner" ]]; then
        echo "$inner"
      else
        echo "$tmpdir"
      fi
      # Register cleanup
      trap "rm -rf '${tmpdir}' 2>/dev/null || true" EXIT
      return 0
    else
      rm -rf "$tmpdir" 2>/dev/null || true
      return 1
    fi
  fi

  log_error "Snapshot not found: ${snap}"
  return 1
}

# --- List files in a backup snapshot ------------------------------------

_restore_list_files() {
  local snapshot="$1"
  local pattern="${2:-}"

  if [[ -d "$snapshot" ]]; then
    if [[ -n "$pattern" ]]; then
      find "$snapshot" -not -path '*/\.bhm_*' -path "*${pattern}*" 2>/dev/null \
        | sed "s|^${snapshot}/||" \
        | sort
    else
      find "$snapshot" -not -path '*/\.bhm_*' -type f 2>/dev/null \
        | sed "s|^${snapshot}/||" \
        | sort
    fi
  elif [[ -f "$snapshot" ]] && [[ "$snapshot" == *.tar.gpg ]]; then
    # List from encrypted tar
    local snap_basename
    snap_basename="$(basename "$snapshot" .tar.gpg)"
    if [[ -n "$pattern" ]]; then
      _encrypt_list_files "$snapshot" "*${pattern}*" 2>/dev/null \
        | grep -v '/\.bhm_' \
        | sed "s|^${snap_basename}/||" \
        | sort
    else
      _encrypt_list_files "$snapshot" 2>/dev/null \
        | grep -v '/\.bhm_' \
        | grep -v '/$' \
        | sed "s|^${snap_basename}/||" \
        | sort
    fi
  else
    log_error "Snapshot not found: ${snapshot}"
    return 1
  fi
}

# --- Show stats about a backup (dry-run for restore) --------------------

_restore_dry_run() {
  local snapshot
  snapshot="$(_restore_resolve_snapshot "$1")" || return 1
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
  local snapshot
  snapshot="$(_restore_resolve_snapshot "$1")" || return 1
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
    local snap_label
    snap_label="$(basename "$snapshot")"
    snap_label="${snap_label%.tar.gpg}"
    info "Auto-selected latest snapshot: ${snap_label}"
  fi

  target="${target:-$BACKUP_SRC}"

  # When listing files, pass raw snapshot path (resolver handles both)
  if [[ -n "$partial" ]] && [[ "$dry_run" == "yes" ]]; then
    # Preview specific files before restore
    echo ""
    _restore_list_files "$snapshot" "$partial"
    echo ""
  fi

  if [[ "$dry_run" == "yes" ]]; then
    # Show overview listing if no specific path
    if [[ -z "$partial" ]]; then
      local count
      count="$(_restore_list_files "$snapshot" | wc -l)"
      info "Snapshot contains ${count} files"
      info "Use --path PATTERN to preview matching files, or --no-dry-run to restore."
    else
      _restore_dry_run "$snapshot" "$target"
      info "Pass --no-dry-run to execute the restore."
    fi
    return 0
  fi

  _confirm "Restore ${snap_label:-$(basename "$snapshot")} to ${target}${partial:+/${partial}}? This may OVERWRITE existing files." || {
    info "Restore cancelled."
    return 0
  }

  _restore_run "$snapshot" "$target" "$partial"
}
