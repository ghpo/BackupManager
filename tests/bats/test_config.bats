#!/usr/bin/env bats
# =============================================================================
# bhm — test_config.bats
# Configuration loading and validation tests
# =============================================================================

setup() {
  load 'helpers'
  bhm_setup
}

@test "config: loads with defaults when no user config exists" {
  _config_load
  [ -n "$BACKUP_SRC" ]
  [ -n "$BACKUP_DST" ]
}

@test "config: BACKUP_SRC defaults to HOME" {
  _config_load
  [ "$BACKUP_SRC" = "$HOME" ]
}

@test "config: BACKUP_DST contains bhm/backups" {
  _config_load
  echo "$BACKUP_DST" | grep -q "bhm/backups"
}

@test "config: validate fails when BACKUP_SRC missing" {
  _config_set_defaults
  BACKUP_SRC=""
  run _config_validate
  [ "$status" -ne 0 ]
}

@test "config: validate fails when BACKUP_DST missing" {
  _config_set_defaults
  BACKUP_DST=""
  run _config_validate
  [ "$status" -ne 0 ]
}

@test "config: validate passes with defaults" {
  _config_load
  run _config_validate
  [ "$status" -eq 0 ]
}

@test "config: EXCLUDE_PATTERNS contains node_modules" {
  _config_load
  local found=0
  for p in "${EXCLUDE_PATTERNS[@]}"; do
    [[ "$p" == "node_modules/" ]] && found=1
  done
  [ "$found" -eq 1 ]
}

@test "config: dump does not crash" {
  _config_load
  run _config_dump
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "BACKUP_SRC"
}
