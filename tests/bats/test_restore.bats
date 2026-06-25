#!/usr/bin/env bats
# =============================================================================
# bhm — test_restore.bats
# Restore engine tests
# =============================================================================

setup() {
  load 'helpers'
  bhm_setup
  _config_load
}

@test "restore: _restore_list_files on empty dir returns nothing" {
  local snap="${BATS_TEST_TMPDIR}/snapshot"
  _ensure_dir "$snap"
  run _restore_list_files "$snap"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "restore: _restore_list_files lists files" {
  local snap="${BATS_TEST_TMPDIR}/snapshot"
  _ensure_dir "$snap"
  echo "test" > "${snap}/file1.txt"
  mkdir -p "${snap}/sub"
  echo "test2" > "${snap}/sub/file2.txt"

  run _restore_list_files "$snap"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "file1.txt"
  echo "$output" | grep -q "sub/file2.txt"
}

@test "restore: _restore_list_files with pattern" {
  local snap="${BATS_TEST_TMPDIR}/snapshot"
  _ensure_dir "$snap"
  echo "a" > "${snap}/report.pdf"
  echo "b" > "${snap}/notes.txt"

  run _restore_list_files "$snap" ".txt"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "notes.txt"
  ! echo "$output" | grep -q "report.pdf"
}

@test "restore: fails on nonexistent snapshot" {
  run _restore_run "/nonexistent/snapshot" "/tmp"
  [ "$status" -ne 0 ]
}

@test "restore: fails on nonexistent target" {
  local snap="${BATS_TEST_TMPDIR}/snapshot"
  _ensure_dir "$snap"
  run _restore_run "$snap" "/nonexistent/target"
  [ "$status" -ne 0 ]
}

@test "restore: metadata files excluded from listing" {
  local snap="${BATS_TEST_TMPDIR}/snapshot"
  _ensure_dir "$snap"
  echo "meta" > "${snap}/.bhm_metadata"
  echo "file" > "${snap}/real.txt"

  run _restore_list_files "$snap"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "\.bhm_metadata"
  echo "$output" | grep -q "real.txt"
}
