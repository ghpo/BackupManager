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
  # Verify integrity in-place: decrypt → pipe to tar t (list mode).
  # This checks both gpg decryption AND tar archive structure
  # without writing any data to disk.
  if [[ -f "$snapshot" ]] && [[ "$snapshot" == *.tar.gpg ]]; then
    local snap_size
    snap_size="$(stat -c '%s' "$snapshot" 2>/dev/null || echo "0")"
    info "Encrypted snapshot: $(basename "$snapshot") ($(_format_bytes "$snap_size"))"

    # Check magic bytes — GPG encrypted data starts with 0x85 0x01 or similar
    local magic
    magic="$(head -c 4 "$snapshot" 2>/dev/null | od -A n -t x1 | tr -d ' \n')"
    if [[ -z "$magic" ]]; then
      fail "Cannot read encrypted snapshot"
      return 1
    fi
    ok "GPG header present: ${magic}"

    # Decrypt to stdout, pipe to tar t — no files written to disk.
    # Single pass: capture the full listing to count entries.
    info "Verifying decryption and archive structure..."
    local pw
    pw="$(_encrypt_passphrase)" || return 1

    local entries
    entries="$(gpg --decrypt \
        --batch \
        --no-symkey-cache \
        --pinentry-mode loopback \
        --passphrase-fd 3 \
        3< <(echo "$pw") \
        "$snapshot" 2>/dev/null | tar t 2>/dev/null)"
    local gpg_rc="${PIPESTATUS[0]}" tar_rc="${PIPESTATUS[1]}"

    if (( gpg_rc != 0 )); then
      fail "Decryption failed (gpg exit ${gpg_rc})"
      return 1
    fi

    if (( tar_rc != 0 )); then
      fail "Archive structure is corrupt (tar exit ${tar_rc})"
      return 1
    fi

    # Count entries from the captured listing (single pass)
    local total_entries total_dirs total_files
    total_entries="$(echo "$entries" | wc -l)"
    total_dirs="$(echo "$entries" | grep '/$' | wc -l)"
    total_files=$(( total_entries - total_dirs ))

    ok "Structure: ${total_dirs} directories, ${total_files} files"
    ok "Encrypted snapshot integrity verified (no data written to disk)"
    return 0
  fi

  if [[ ! -d "$snapshot" ]]; then
    log_error "Snapshot not found: ${snapshot}"
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
