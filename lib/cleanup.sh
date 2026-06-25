# shellcheck shell=bash
# =============================================================================
# bhm — cleanup.sh
# Backup rotation: daily / weekly / monthly retention policy
# =============================================================================

# shellcheck disable=SC2034,SC2153  # sourced, RETENTION_*

_cleanup_run() {
  local host="${BACKUP_HOST:-localhost}"
  local user="${BACKUP_USER:-$USER}"
  local base="${BACKUP_DST}/${host}/${user}"

  if [[ ! -d "$base" ]]; then
    info "No backup directory to clean: ${base}"
    return 0
  fi

  # Collect all snapshots sorted oldest-first
  local all_snaps=()
  local snap
  while IFS= read -r -d '' snap; do
    all_snaps+=("$(basename "$snap")")
  done < <(find "$base" -maxdepth 1 -type d -name '????-??-??_??-??-??' -print0 | sort -z)

  local total="${#all_snaps[@]}"
  if (( total == 0 )); then
    info "No snapshots to clean"
    return 0
  fi

  log_info "Running retention policy: ${total} snapshots found"

  local keep=()
  local remove=()

  _cleanup_classify "${all_snaps[@]}"

  local n_keep="${#keep[@]}"
  local n_remove="${#remove[@]}"

  if (( n_remove == 0 )); then
    ok "All ${n_keep} snapshots within retention policy"
    return 0
  fi

  info "Retention: keep ${n_keep}, remove ${n_remove}"

  local s dir
  for s in "${remove[@]}"; do
    dir="${base}/${s}"
    log_info "Removing expired snapshot: ${s}"
    _safe_remove "$dir"
  done

  ok "Cleanup complete: removed ${n_remove} expired snapshots"
}

# --- Classify snapshots into keep/remove sets ---------------------------

_cleanup_classify() {
  local snaps=("$@")
  local daily_keep="${RETENTION_DAILY:-7}"
  local weekly_keep="${RETENTION_WEEKLY:-4}"
  local monthly_keep="${RETENTION_MONTHLY:-3}"

  local i snap date_epoch dow day_of_month
  local -A seen

  # Process newest → oldest
  local reversed=()
  for (( i = ${#snaps[@]} - 1; i >= 0; i-- )); do
    reversed+=("${snaps[$i]}")
  done

  # Phase 1: Mark snapshots to keep based on policy
  local daily_count=0 weekly_count=0 monthly_count=0
  local day_key

  for snap in "${reversed[@]}"; do
    # Parse timestamp: YYYY-MM-DD_HH-MM-SS
    date_epoch="$(date -d "${snap:0:10}" +%s 2>/dev/null)" || continue
    dow="$(date -d "@$date_epoch" +%u)"      # 1=Mon … 7=Sun
    day_of_month="$(date -d "@$date_epoch" +%d)"
    # Strip leading zeros to avoid octal interpretation in (( ))
    dow="${dow#0}"
    day_of_month="${day_of_month#0}"
    # Handle empty after stripping (date 00 → "")
    dow="${dow:-0}"
    day_of_month="${day_of_month:-0}"

    # Monthly: keep first day of month
    if (( day_of_month == 1 )) && (( monthly_count < monthly_keep )); then
      keep+=("$snap")
      seen["$snap"]=1
      monthly_count=$((monthly_count + 1))
      continue
    fi

    # Weekly: keep Sundays
    if (( dow == 7 )) && (( weekly_count < weekly_keep )); then
      # Don't double-count if already kept as monthly
      if [[ -z "${seen["$snap"]:-}" ]]; then
        keep+=("$snap")
        seen["$snap"]=1
        weekly_count=$((weekly_count + 1))
        continue
      fi
    fi

    # Daily: keep most recent N (but only if not already kept)
    if (( daily_count < daily_keep )) && [[ -z "${seen["$snap"]:-}" ]]; then
      keep+=("$snap")
      seen["$snap"]=1
      daily_count=$((daily_count + 1))
    fi
  done

  # Phase 2: Everything not marked is removed
  for snap in "${snaps[@]}"; do
    if [[ -z "${seen["$snap"]:-}" ]]; then
      remove+=("$snap")
    fi
  done
}

# --- Cleanup entry point (CLI) ------------------------------------------

_cleanup_cmd() {
  _cleanup_run
}
