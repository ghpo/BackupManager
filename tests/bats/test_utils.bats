#!/usr/bin/env bats
# =============================================================================
# bhm — test_utils.bats
# Utility function tests
# =============================================================================

setup() {
  load 'helpers'
  bhm_setup
}

@test "utils: _format_seconds" {
  run _format_seconds 0
  [ "$output" = "0s" ]

  run _format_seconds 45
  [ "$output" = "45s" ]

  run _format_seconds 125
  [ "$output" = "2m05s" ]

  run _format_seconds 3661
  [ "$output" = "1h01m01s" ]
}

@test "utils: _ensure_dir creates directory" {
  local d="${BATS_TEST_TMPDIR}/a/b/c"
  _ensure_dir "$d"
  [ -d "$d" ]
}

@test "utils: _ensure_dir succeeds on existing" {
  _ensure_dir "$BATS_TEST_TMPDIR"
  [ -d "$BATS_TEST_TMPDIR" ]
}

@test "utils: _safe_remove removes file" {
  local f="${BATS_TEST_TMPDIR}/testfile"
  touch "$f"
  _safe_remove "$f"
  [ ! -f "$f" ]
}

@test "utils: _safe_remove no-op on missing" {
  run _safe_remove "${BATS_TEST_TMPDIR}/nonexistent"
  [ "$status" -eq 0 ]
}

@test "utils: _checksum_file consistent" {
  local f="${BATS_TEST_TMPDIR}/checksum_test"
  echo "hello world" > "$f"
  local cs1 cs2
  cs1="$(_checksum_file "$f")"
  cs2="$(_checksum_file "$f")"
  [ "$cs1" = "$cs2" ]
}
