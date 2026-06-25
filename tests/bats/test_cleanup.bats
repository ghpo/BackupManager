#!/usr/bin/env bats
# =============================================================================
# bhm — test_cleanup.bats
# Retention / cleanup tests
# =============================================================================

setup() {
  load 'helpers'
  bhm_setup
  _config_load
}

@test "cleanup: no snapshots dir returns success" {
  BACKUP_DST="${BATS_TEST_TMPDIR}/nope"
  run _cleanup_run
  [ "$status" -eq 0 ]
}

@test "cleanup: classify keeps within retention" {
  local snaps=()
  local i
  for (( i = 10; i >= 1; i-- )); do
    snaps+=("2024-01-$(printf '%02d' "$i")_12-00-00")
  done

  # 2024-01-01 is a Monday, 2024-01-07 is a Sunday
  # 10 snaps with 7 daily + 4 weekly + 3 monthly:
  # kept = 7 newest dailies + 1 weekly (01-07, unique) + 1 monthly (01-01, unique) = 9
  RETENTION_DAILY=7
  RETENTION_WEEKLY=4
  RETENTION_MONTHLY=3

  keep=()
  remove=()
  _cleanup_classify "${snaps[@]}"

  [ "${#keep[@]}" -eq 9 ]
  [ "${#remove[@]}" -eq 1 ]
}

@test "cleanup: classify marks oldest for removal" {
  local snaps=("2024-01-01_00-00-00" "2024-01-02_00-00-00" "2024-01-03_00-00-00")
  RETENTION_DAILY=2
  RETENTION_WEEKLY=0
  RETENTION_MONTHLY=0

  keep=()
  remove=()
  _cleanup_classify "${snaps[@]}"

  [ "${#keep[@]}" -eq 2 ]
  [ "${#remove[@]}" -eq 1 ]
}

@test "cleanup: empty snap list handles gracefully" {
  keep=()
  remove=()
  _cleanup_classify
  [ "${#keep[@]}" -eq 0 ]
  [ "${#remove[@]}" -eq 0 ]
}
