#!/usr/bin/env sh
# Minimal setup script to install C++ build dependencies and ninja for parallel builds
set -eu

usage() {
  echo "Usage: $0 [--yes|-y|--check|--clean]"
  echo "Installs required packages (cmake, ninja, a C++ toolchain, git) for common Linux distros."
  echo "Use --check to run repository checks only (no installs)."
  echo "Use --clean to remove generated artifacts (audits, logs, run)."
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Ensure runtime directories exist so tools and scripts can write logs and pidfiles
mkdir -p "$REPO_ROOT/run" "$REPO_ROOT/logs" "$REPO_ROOT/audits" 2>/dev/null || true

run_checks() {
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

  # Copilot CLI is optional in CI checks; warn if missing but do not fail the check
  if command -v copilot >/dev/null 2>&1; then
    printf 'OK: copilot\n'
  else
    printf 'WARNING: copilot not found (optional)\n'
  fi

  # If copilot exists, verify it is usable
  if command -v copilot >/dev/null 2>&1; then
    if copilot --version >/dev/null 2>&1; then
      echo "OK: copilot CLI available"
    else
      echo "WARNING: copilot binary found but not responding to --version; it may need setup or login"
      missing=1
    fi
  fi

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
}

clean_artifacts() {
  echo "Cleaning generated artifacts under $REPO_ROOT..."
  targets="$REPO_ROOT/audits $REPO_ROOT/logs $REPO_ROOT/run"
  for t in $targets; do
    if [ -e "$t" ]; then
      echo "Removing $t"
      rm -rf "$t" || echo "Failed to remove $t"
    else
      echo "Not found: $t"
    fi
  done
  echo "Clean complete."
}

FORCE=0
CHECK_ONLY=0
CLEAN=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    -y|--yes) FORCE=1; shift;;
    --check) CHECK_ONLY=1; shift;;
    --clean) CLEAN=1; shift;;
    -h|--help) usage;;
    *) echo "Unknown argument: $1"; usage;;
  esac
done

if [ "$CLEAN" -eq 1 ]; then
  clean_artifacts
  exit 0
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
  run_checks
  exit 0
fi

PKGS_COMMON="cmake git pkg-config ca-certificates curl"
PKGS_BUILD=""

if command -v apt-get >/dev/null 2>&1; then
  PM="apt"
  PKGS="$PKGS_COMMON ninja-build build-essential"
  INSTALL_CMD="sudo apt-get update && sudo apt-get install -y $PKGS"
elif command -v dnf >/dev/null 2>&1; then
  PM="dnf"
  PKGS="$PKGS_COMMON ninja-build gcc-c++ make"
  INSTALL_CMD="sudo dnf install -y $PKGS"
elif command -v yum >/dev/null 2>&1; then
  PM="yum"
  PKGS="$PKGS_COMMON ninja-build gcc-c++ make"
  INSTALL_CMD="sudo yum install -y $PKGS"
elif command -v pacman >/dev/null 2>&1; then
  PM="pacman"
  PKGS="$PKGS_COMMON base-devel ninja"
  INSTALL_CMD="sudo pacman -Sy --noconfirm $PKGS"
elif command -v apk >/dev/null 2>&1; then
  PM="apk"
  PKGS="$PKGS_COMMON build-base ninja"
  INSTALL_CMD="sudo apk add --no-cache $PKGS"
else
  echo "Unsupported package manager. Please manually install: cmake, ninja, a C++ compiler (g++/clang), make, git." >&2
  exit 1
fi

echo "Detected package manager: $PM"
echo "Packages to install: $PKGS"

if [ "$FORCE" -eq 1 ]; then
  sh -c "$INSTALL_CMD"
else
  printf "About to run: %s\nProceed? [y/N] " "$INSTALL_CMD"
  read ans || ans="n"
  case "$ans" in
    y|Y) sh -c "$INSTALL_CMD";;
    *) echo "Aborted."; exit 1;;
  esac
fi

# Ensure 'ninja' binary exists
if ! command -v ninja >/dev/null 2>&1 && command -v ninja-build >/dev/null 2>&1; then
  echo "Linking ninja-build -> /usr/local/bin/ninja"
  sudo ln -sf "$(command -v ninja-build)" /usr/local/bin/ninja || true
fi

# Fetch Catch2 into external/Catch2
EXTERNAL_DIR="$REPO_ROOT/external"
CATCH_DIR="$EXTERNAL_DIR/Catch2"
if [ ! -d "$CATCH_DIR" ]; then
  echo "Fetching Catch2 into $CATCH_DIR"
  mkdir -p "$EXTERNAL_DIR"
  if command -v git >/dev/null 2>&1; then
    git clone --depth 1 https://github.com/catchorg/Catch2.git "$CATCH_DIR"
    # remove git metadata to keep just the sources
    rm -rf "$CATCH_DIR/.git" || true
  else
    echo "WARNING: git not found; cannot clone Catch2. Please install git or fetch Catch2 manually into $CATCH_DIR" >&2
  fi
else
  echo "Catch2 already present at $CATCH_DIR"
fi

# Install GitHub Copilot CLI if missing
if ! command -v copilot >/dev/null 2>&1; then
  echo "Copilot CLI not found; installing via https://gh.io/copilot-install"
  curl -fsSL https://gh.io/copilot-install | bash
else
  echo "Copilot CLI already installed"
fi

echo "Setup complete. Example build: mkdir -p build && cd build && cmake -G Ninja .. && ninja -j$(nproc 2>/dev/null || echo 2)"

# Run checks automatically after setup completes
run_checks
