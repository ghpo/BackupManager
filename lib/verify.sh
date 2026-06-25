# shellcheck shell=bash
# =============================================================================
# bhm — verify.sh
# Backup integrity verification via checksum sampling
# =============================================================================

# shellcheck disable=SC2034  # sourced

# --- Verify the most recent backup --------------------------------------

_verify_latest() {
  local base="${BACKUP_DST}/${BACKUP_HOST:-localhost}/${BACKUP_USER:-$USER}"
  local latest
  latest="$(_latest_backup_dir "$base")"

  # Fall back to latest encrypted snapshot
  if [[ -z "$latest" ]]; then
    latest="$(find "$base" -maxdepth 1 -type f -name '????-??-??_??-??-??.tar.gpg' 2>/dev/null \
      | sort | tail -1)"
  fi

  if [[ -z "$latest" ]]; then
    log_error "No backup snapshots found to verify"
    return 1
  fi
  _verify_snapshot "$latest"
}

# --- Verify a specific snapshot -----------------------------------------

_verify_snapshot() {
  local snapshot="$1"
  local sample_pct="${VERIFY_SAMPLE_PCT:-5}"
  local cleanup_dir=""

  # Handle encrypted snapshots (.tar.gpg)
  if [[ -f "$snapshot" ]] && [[ "$snapshot" == *.tar.gpg ]]; then
    info "Encrypted snapshot: $(basename "$snapshot")"
    cleanup_dir="$(mktemp -d "/tmp/bhm_verify_XXXXXX")"

    if ! _encrypt_decrypt_extract "$snapshot" "$cleanup_dir"; then
      rm -rf "$cleanup_dir" 2>/dev/null || true
      fail "Failed to decrypt snapshot for verification"
      return 1
    fi

    local inner
    inner="$(find "$cleanup_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)"
    if [[ -n "$inner" ]]; then
      snapshot="$inner"
    else
      snapshot="$cleanup_dir"
    fi
  fi

  if [[ ! -d "$snapshot" ]]; then
    log_error "Snapshot not found: ${snapshot}"
    [[ -n "$cleanup_dir" ]] && rm -rf "$cleanup_dir" 2>/dev/null || true
    return 1
  fi

  info "Verifying snapshot: $(basename "$snapshot")"

  # Phase 1: structural check — directory tree exists and is readable
  local total_dirs total_files
  total_dirs="$(find "$snapshot" -type d 2>/dev/null | wc -l)"
  total_files="$(find "$snapshot" -not -path '*/\.bhm_*' -type f 2>/dev/null | wc -l)"

  if (( total_dirs == 0 )); then
    fail "Snapshot appears empty or unreadable: ${snapshot}"
    log_error "No directories found in ${snapshot}"
    [[ -n "$cleanup_dir" ]] && rm -rf "$cleanup_dir" 2>/dev/null || true
    return 1
  fi

  ok "Structure: ${total_dirs} directories, ${total_files} files"

  # Phase 2: checksum sampling (if enabled)
  local errors=0
  if [[ "${VERIFY_CHECKSUM:-yes}" == "yes" ]] && (( total_files > 0 )); then
    _verify_checksums "$snapshot" "$sample_pct" || errors=$?
  fi

  # Phase 3: metadata presence
  local meta="${snapshot}/.bhm_metadata"
  if [[ -f "$meta" ]]; then
    ok "Metadata present: $(head -3 "$meta" | tr '\n' ' ')"
  else
    warn "No .bhm_metadata found in snapshot"
  fi

  # Cleanup temp dir if this was an encrypted snapshot
  [[ -n "$cleanup_dir" ]] && rm -rf "$cleanup_dir" 2>/dev/null || true

  if (( errors > 0 )); then
    fail "Verification found ${errors} issue(s)"
    return 1
  fi

  ok "Snapshot verification passed"
  return 0
}

# --- Checksum sampling ---------------------------------------------------

_verify_checksums() {
  local snapshot="$1"
  local sample_pct="${2:-5}"
  local errors=0
  local checked=0

  # Collect sample file list (random subset)
  local sample_files=()
  local all_files=()

  while IFS= read -r -d '' f; do
    all_files+=("$f")
  done < <(find "$snapshot" -not -path '*/\.bhm_*' -type f -print0 2>/dev/null)

  local total="${#all_files[@]}"
  local sample_size=$(( total * sample_pct / 100 ))
  (( sample_size < 1 )) && sample_size=1
  (( sample_size > 500 )) && sample_size=500

  # Random sampling using shuf if available
  if command -v shuf &>/dev/null; then
    while IFS= read -r -d '' f; do
      sample_files+=("$f")
    done < <(printf '%s\0' "${all_files[@]}" | shuf -z -n "$sample_size")
  else
    sample_files=("${all_files[@]:0:$sample_size}")
  fi

  info "Checksumming ${#sample_files[@]} of ${total} files (${sample_pct}%)..."

  local f cs_a cs_b
  for f in "${sample_files[@]}"; do
    cs_a="$(_checksum_file "$f")"
    cs_b="$(_checksum_file "$f")"
    if [[ "$cs_a" != "$cs_b" ]]; then
      warn "Checksum mismatch (read instability): ${f#"${snapshot}"/}"
      ((errors++))
    fi
    ((checked++))
  done

  ok "Checksums: ${checked} verified, ${errors} mismatches"
  return "$errors"
}

# --- Verify entry point (CLI) -------------------------------------------

_verify_cmd() {
  local snapshot=""
  local OPTS
  OPTS="$(getopt -o s: --long snapshot: -n 'bhm verify' -- "$@")" || return 1
  eval set -- "$OPTS"

  while true; do
    case "$1" in
      -s|--snapshot) snapshot="$2"; shift 2 ;;
      --) shift; break ;;
    esac
  done

  if [[ -n "$snapshot" ]]; then
    _verify_snapshot "$snapshot"
  else
    _verify_latest
  fi
}
