#!/usr/bin/env sh
# Environment and dependency checker (WSL-friendly)
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  cat <<'USAGE'
Usage: sh scripts/check.sh

Checks required commands and basic environment (cmake, ninja, g++, make, git, docker).
Also verifies Catch2 is present in external/Catch2 (single_include or src layout).
USAGE
  exit 0
fi

echo "Checking required commands..."
missing=0
check_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    printf "OK: %s\n" "$1"
  else
    printf "MISSING: %s\n" "$1"
    missing=1
  fi
}

check_cmd cmake
check_cmd ninja
check_cmd g++
check_cmd make
check_cmd git
check_cmd docker

if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    echo "OK: docker daemon responding"
  else
    echo "WARNING: docker command found but daemon not responding; try: sudo systemctl start docker"
    missing=1
  fi
fi

# Detect WSL (optional)
if [ -f /proc/version ] && grep -qi microsoft /proc/version 2>/dev/null; then
  echo "Environment: WSL detected"
  # WSL-specific hint for Docker Desktop
  if ! docker info >/dev/null 2>&1; then
    echo "Hint: On WSL you may need Docker Desktop or to enable the Docker daemon for WSL."
  fi
else
  echo "Environment: non-WSL or undetected"
fi

# Verify Catch2 test library exists in external/Catch2 (accept multiple layouts)
CATCH_DIR="${REPO_ROOT}/external/Catch2"
if [ -d "$CATCH_DIR" ]; then
  if [ -f "${CATCH_DIR}/single_include/catch2/catch.hpp" ] || [ -f "${CATCH_DIR}/single_include/catch2/catch_all.hpp" ] || [ -f "${CATCH_DIR}/src/catch2/catch_all.hpp" ] || [ -f "${CATCH_DIR}/src/catch2/catch.hpp" ]; then
    echo "OK: Catch2 sources present at ${CATCH_DIR}"
  else
    echo "MISSING: Catch2 headers not found in ${CATCH_DIR} (run scripts/setup.sh to fetch and/or generate single header)" >&2
    missing=1
  fi
else
  echo "MISSING: Catch2 in external/Catch2 (run scripts/setup.sh to fetch)" >&2
  missing=1
fi

if [ "$missing" -ne 0 ]; then
  echo "Some checks failed. Run scripts/setup.sh to install common packages (if supported) and re-run this check." >&2
  exit 2
fi

echo "All checks passed."
