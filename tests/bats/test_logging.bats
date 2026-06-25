#!/usr/bin/env bats
# =============================================================================
# bhm — test_logging.bats
# Logging system tests
# =============================================================================

setup() {
  load 'helpers'
  bhm_setup
  _config_load
}

@test "logging: log_init creates log directory" {
  local test_log="${BATS_TEST_TMPDIR}/logs"
  LOG_DIR="$test_log"
  _log_init
  [ -d "$test_log" ]
}

@test "logging: log_info outputs to stdout" {
  _log_init
  run log_info "test message"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "INFO"
  echo "$output" | grep -q "test message"
}

@test "logging: log_error outputs to stderr" {
  _log_init
  run log_error "error test"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "ERROR"
}

@test "logging: log_debug suppressed at INFO level" {
  LOG_LEVEL="INFO"
  _log_init
  run log_debug "debug message"
  [ -z "$output" ]
}

@test "logging: log_debug visible at DEBUG level" {
  LOG_LEVEL="DEBUG"
  _log_init
  run log_debug "debug message"
  echo "$output" | grep -q "DEBUG"
}

@test "logging: log file is created" {
  local test_log="${BATS_TEST_TMPDIR}/logs"
  LOG_DIR="$test_log"
  _log_init
  log_info "file test"
  [ -f "$BHM_LOG_FILE" ]
  cat "$BHM_LOG_FILE" | grep -q "file test"
}
