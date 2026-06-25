#!/usr/bin/env bats
# =============================================================================
# bhm — test_backup.bats
# Backup engine tests
# =============================================================================

setup() {
  load 'helpers'
  bhm_setup
  _config_load
}

@test "backup: _rsync_explain known codes" {
  run _rsync_explain 0
  [ "$output" = "Success" ]

  run _rsync_explain 24
  [ "$output" = "Partial transfer: some files vanished during sync (normal)" ]

  run _rsync_explain 99
  [ "$output" = "Unknown error code 99" ]
}

@test "backup: _rsync_is_ok returns 0 for codes 0 and 24" {
  run _rsync_is_ok 0
  [ "$status" -eq 0 ]

  run _rsync_is_ok 24
  [ "$status" -eq 0 ]

  run _rsync_is_ok 23
  [ "$status" -ne 0 ]
}

@test "backup: _rsync_is_partial returns 0 for 23 and 25" {
  run _rsync_is_partial 23
  [ "$status" -eq 0 ]

  run _rsync_is_partial 25
  [ "$status" -eq 0 ]

  run _rsync_is_partial 1
  [ "$status" -ne 0 ]
}

@test "backup: _build_exclude_file creates file with patterns" {
  BACKUP_DST="${BATS_TEST_TMPDIR}/backups"
  _ensure_dir "$BACKUP_DST"
  _build_exclude_file
  [ -f "$BHM_EXCLUDE_FILE" ]
  grep -q "node_modules/" "$BHM_EXCLUDE_FILE"
  grep -q "*.log" "$BHM_EXCLUDE_FILE"
  _cleanup_exclude_file
}

@test "backup: _backup_write_metadata creates metadata file" {
  local snap_dir="${BATS_TEST_TMPDIR}/snap"
  _ensure_dir "$snap_dir"
  _backup_write_metadata "$snap_dir" 0 42
  [ -f "${snap_dir}/.bhm_metadata" ]
  grep -q "rsync_exit_code=0" "${snap_dir}/.bhm_metadata"
  grep -q "duration_seconds=42" "${snap_dir}/.bhm_metadata"
}

@test "backup: _latest_backup_dir returns correct dir" {
  local base="${BATS_TEST_TMPDIR}/backups"
  _ensure_dir "$base/2024-01-01_00-00-00"
  _ensure_dir "$base/2024-01-02_00-00-00"
  _ensure_dir "$base/2024-01-03_00-00-00"

  result="$(_latest_backup_dir "$base")"
  echo "$result" | grep -q "2024-01-03_00-00-00"
}
