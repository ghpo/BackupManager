# =============================================================================
# bhm — test helpers
# Source this from Bats test files to load bhm into the test context
# =============================================================================

bhm_setup() {
  # Resolve BHM_HOME from test location: tests/bats/ → project root
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  export BHM_HOME="$script_dir"

  # Create tempdir per test
  export BATS_TEST_TMPDIR="${BATS_TEST_TMPDIR:-$(mktemp -d)}"
  export XDG_CACHE_HOME="${BATS_TEST_TMPDIR}/cache"
  export XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}/config"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "$HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"

  # Silence logging during tests
  export LOG_LEVEL="DEBUG"
  export LOG_DIR="${BATS_TEST_TMPDIR}/logs"

  # Source all bhm libs
  source "${BHM_HOME}/lib/logging.sh"
  source "${BHM_HOME}/lib/utils.sh"
  source "${BHM_HOME}/lib/config.sh"
  source "${BHM_HOME}/lib/backup.sh"
  source "${BHM_HOME}/lib/restore.sh"
  source "${BHM_HOME}/lib/verify.sh"
  source "${BHM_HOME}/lib/cleanup.sh"

  # Override hostname for deterministic tests
  export BACKUP_HOST="testhost"
  export BACKUP_USER="testuser"

  _log_init
}
