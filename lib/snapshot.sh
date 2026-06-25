# shellcheck shell=bash
# =============================================================================
# bhm — snapshot.sh
# Btrfs snapshot management (snapper-style, no snapper dependency)
# Creates/deletes snapshots before/after backup runs
# =============================================================================

# shellcheck disable=SC2034,SC2153  # sourced, BTRFS_*

# --- Prerequisites -------------------------------------------------------

_btrfs_available() {
  command -v btrfs &>/dev/null
}

_btrfs_check_config() {
  if [[ "${BTRFS_ENABLE:-no}" != "yes" ]]; then
    return 1
  fi
  if ! _btrfs_available; then
    log_warn "Btrfs-tools not installed — snapshot support disabled"
    return 1
  fi
  if [[ -z "$BTRFS_SUBVOL" ]]; then
    log_warn "BTRFS_SUBVOL is not configured — snapshot support disabled"
    return 1
  fi
  if [[ ! -d "$BTRFS_SUBVOL" ]]; then
    log_warn "Btrfs subvolume not found: ${BTRFS_SUBVOL}"
    return 1
  fi
  return 0
}

# --- Create a Btrfs snapshot (read-only) ---------------------------------

_btrfs_snapshot_create() {
  _btrfs_check_config || return 0  # silently skip if not enabled

  local prefix="${BTRFS_SNAPSHOT_PREFIX:-bhm-}"
  local name
  name="${prefix}$(date '+%Y%m%d_%H%M%S')"
  local snap_dir="${BTRFS_SUBVOL}/.snapshots"
  _ensure_dir "$snap_dir" || return 1

  local dest="${snap_dir}/${name}"

  log_info "Creating Btrfs snapshot: ${BTRFS_SUBVOL} → ${dest}"

  if btrfs subvolume snapshot -r "$BTRFS_SUBVOL" "$dest" 2>&1; then
    ok "Btrfs snapshot created: ${name}"
    log_info "Btrfs snapshot: ${dest}"
    echo "$dest"
    return 0
  else
    local rc=$?
    log_error "Btrfs snapshot failed (exit ${rc})"
    return $rc
  fi
}

# --- List Btrfs snapshots ------------------------------------------------

_btrfs_snapshot_list() {
  _btrfs_check_config || return 0

  local prefix="${BTRFS_SNAPSHOT_PREFIX:-bhm-}"
  local snap_dir="${BTRFS_SUBVOL}/.snapshots"

  if [[ ! -d "$snap_dir" ]]; then
    info "No Btrfs snapshots directory: ${snap_dir}"
    return 0
  fi

  local count=0
  local snap
  while IFS= read -r -d '' snap; do
    local name size date
    name="$(basename "$snap")"
    size="$(btrfs qgroup show -e "$snap" 2>/dev/null | awk 'NR==4{print $2}' || du -sh "$snap" | awk '{print $1}')"
    date="$(stat -c '%y' "$snap" 2>/dev/null | cut -d. -f1)"
    printf '%-30s %-12s %s\n' "$name" "$size" "$date"
    ((count++))
  done < <(find "$snap_dir" -maxdepth 1 -type d -name "${prefix}*" -print0 | sort -rz)

  if (( count == 0 )); then
    info "No Btrfs snapshots found with prefix '${prefix}'"
  fi
}

# --- Prune old Btrfs snapshots -------------------------------------------

_btrfs_snapshot_prune() {
  _btrfs_check_config || return 0

  local retention="${BTRFS_RETENTION:-7}"
  local prefix="${BTRFS_SNAPSHOT_PREFIX:-bhm-}"
  local snap_dir="${BTRFS_SUBVOL}/.snapshots"

  if [[ ! -d "$snap_dir" ]]; then
    return 0
  fi

  local snaps=()
  while IFS= read -r -d '' s; do
    snaps+=("$s")
  done < <(find "$snap_dir" -maxdepth 1 -type d -name "${prefix}*" -print0 | sort)

  local count="${#snaps[@]}"
  if (( count <= retention )); then
    log_debug "Btrfs snapshots (${count}) within retention (${retention}), nothing to prune"
    return 0
  fi

  local to_delete=$(( count - retention ))
  local i
  for (( i = 0; i < to_delete; i++ )); do
    log_info "Removing old Btrfs snapshot: $(basename "${snaps[$i]}")"
    btrfs subvolume delete "${snaps[$i]}" 2>&1 || log_warn "Failed to delete snapshot: ${snaps[$i]}"
  done

  ok "Pruned ${to_delete} old Btrfs snapshots, kept ${retention}"
}
