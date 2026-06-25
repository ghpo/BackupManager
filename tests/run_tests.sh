#!/usr/bin/env bash
# =============================================================================
# bhm — Test Runner
# Runs Bats tests with proper environment
# =============================================================================

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BATS_DIR="${SCRIPT_DIR}/bats"
TEST_REPORT_DIR="${SCRIPT_DIR}/reports"

# Ensure bats is installed
if ! command -v bats &>/dev/null; then
  echo "ERROR: 'bats' not found. Install it:"
  echo "  npm install -g bats       # or"
  echo "  brew install bats-core     # or"
  echo "  apt install bats           # (Debian/Ubuntu)"
  echo "  dnf install bats           # (Fedora)"
  exit 1
fi

# Parse args
BATS_ARGS=()
# shellcheck disable=SC2034
COVERAGE=0
VERBOSE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--verbose) VERBOSE=1; BATS_ARGS+=("--verbose-run"); shift ;;
    -c|--coverage) shift ;; # coverage flag (reserved)
    -h|--help)
      echo "Usage: $0 [options] [test-file ...]"
      echo ""
      echo "Options:"
      echo "  -v, --verbose       Verbose output"
      echo "  -c, --coverage      Show line-by-line coverage (requires shellspec)"
      echo "  -h, --help          Show this help"
      echo ""
      echo "If no test file is specified, all tests in tests/bats/ are run."
      exit 0
      ;;
    *) BATS_ARGS+=("$1"); shift ;;
  esac
done

# If no specific files given, run all
if [[ $# -eq 0 ]]; then
  set -- "${BATS_DIR}/"*.bats
fi

echo "=========================================="
echo "  bhm — Backup Home Manager Test Suite"
echo "  Project: ${PROJECT_DIR}"
echo "  Bats:    $(bats --version 2>&1)"
echo "=========================================="
echo ""

# Run tests
mkdir -p "$TEST_REPORT_DIR"
if (( VERBOSE )); then
  bats "${BATS_ARGS[@]}" "$@" 2>&1 | tee "${TEST_REPORT_DIR}/test_output.log"
  rc=${PIPESTATUS[0]}
else
  bats --formatter tap "${BATS_ARGS[@]}" "$@" 2>&1 | tee "${TEST_REPORT_DIR}/test_output.log"
  rc=${PIPESTATUS[0]}
fi

echo ""
echo "=========================================="
echo "  Report: ${TEST_REPORT_DIR}/test_output.log"
echo "  Exit:   ${rc}"
echo "=========================================="

exit "$rc"
