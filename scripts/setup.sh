#!/usr/bin/env sh
# Minimal setup script to install C++ build dependencies and ninja for parallel builds
set -eu

usage() {
  echo "Usage: $0 [--check|--clean|--directive \"<string>\"]"
  echo "Non-interactive by default; setup will run without prompting."
  echo "Use --check to run repository checks only (no installs)."
  echo "Use --clean to remove generated artifacts (audits, logs, run)."
  echo "Use --directive \"<string>\" to update config/settings.toml with the prime directive for agents and commit via scripts/skills/patch-repo.sh."
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
  check_cmd sqlite3

  # Copilot CLI is required by default; in CI mode it's optional
  if [ "${CI_MODE:-0}" -eq 1 ]; then
    echo "CI mode: copilot not required (skipping strict failure on missing copilot)"
    if command -v copilot >/dev/null 2>&1; then
      printf 'OK: copilot\n'
    else
      printf 'INFO: copilot not installed in CI mode\n'
    fi
  else
    check_cmd copilot
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
  if [ "${CI_MODE:-0}" -eq 1 ]; then
    echo "CI mode: skipping Catch2 presence check (not required in CI)"
  else
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

update_directive_in_config() {
  cfg="$REPO_ROOT/config/settings.toml"
  val="$1"
  # escape double quotes in value
  esc=$(printf '%s' "$val" | sed 's/"/\\"/g')
  if [ -f "$cfg" ] && grep -q '^[[:space:]]*directive[[:space:]]*=' "$cfg" 2>/dev/null; then
    awk -v v="$esc" 'BEGIN{q="\""} /^[[:space:]]*directive[[:space:]]*=/ {print "directive = \"" v "\""; next} {print}' "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
  else
    printf '\n# Prime directive for agents\ndirective = "%s"\n' "$esc" >> "$cfg"
  fi
  echo "Updated $cfg with directive: $val"
}

FORCE=1
CHECK_ONLY=0
CLEAN=0
CI_MODE=0
DIRECTIVE_ARG=""
DIRECTIVE_PROVIDED=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) CHECK_ONLY=1; shift;;
    --clean) CLEAN=1; shift;;
    --directive)
      DIRECTIVE_PROVIDED=1
      if [ "$#" -eq 1 ]; then
        DIRECTIVE_ARG=""
        shift
      else
        DIRECTIVE_ARG="$2"
        shift 2
      fi
      ;;
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

# Detect CI from standard CI environment variable if present
if [ -n "${CI:-}" ] && [ "${CI}" != "0" ]; then
  CI_MODE=1
fi

if [ "${CI_MODE:-0}" -eq 1 ]; then
  echo "CI mode enabled: running non-interactively"
  FORCE=1
fi

# Non-interactive install: require root or sudo; prefer sudo -n to avoid password prompts
if [ "$(id -u)" -ne 0 ] && ! command -v sudo >/dev/null 2>&1; then
  echo "Non-interactive install requires root or sudo; please run as root or install sudo." >&2
  exit 1
fi
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo -n"
else
  SUDO=""
fi

# If directive arg provided, update the settings file and commit via patch-repo
if [ "${DIRECTIVE_PROVIDED:-0}" -eq 1 ]; then
  cfg="$REPO_ROOT/config/settings.toml"
  # If empty string requested, print current directive and exit; if empty in config, auto-derive from docs/TODO.md
  if [ -z "${DIRECTIVE_ARG:-}" ]; then
    if [ -f "$cfg" ]; then
      current="$(grep '^[[:space:]]*directive[[:space:]]*=' "$cfg" 2>/dev/null | sed -n 's/^[[:space:]]*directive[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' || true)"
      if [ -n "$current" ]; then
        echo "$current"
        exit 0
      fi
    else
      echo "Config file $cfg not found" >&2
      exit 1
    fi
    # Attempt to derive directive from TODO.md
    TODO_FILE="$REPO_ROOT/TODO.md"
    if [ -f "$TODO_FILE" ]; then
      candidate="$(awk '/^##[[:space:]]*Prime directive/{found=1;next} found && NF{print; exit}' "$TODO_FILE" 2>/dev/null || true)"
      if [ -n "$candidate" ]; then
        DIRECTIVE_ARG="$candidate"
        echo "Auto-derived prime directive: $DIRECTIVE_ARG"
      else
        echo "No prime directive found in $TODO_FILE" >&2
        exit 1
      fi
    else
      echo "No TODO.md found to derive directive" >&2
      exit 1
    fi
  fi
  update_directive_in_config "$DIRECTIVE_ARG"
  if [ -f "$SCRIPT_DIR/skills/patch-repo.sh" ]; then
    echo "Committing settings change using patch-repo..."
    sh "$SCRIPT_DIR/skills/patch-repo.sh" || echo "patch-repo failed; check run/skills/patch-repo"
  else
    echo "patch-repo helper not found at $SCRIPT_DIR/skills/patch-repo.sh; please commit $REPO_ROOT/config/settings.toml manually"
  fi
  exit 0
fi

PKGS_COMMON="cmake git pkg-config ca-certificates curl"
PKGS_BUILD=""

if command -v apt-get >/dev/null 2>&1; then
  PM="apt"
  PKGS="$PKGS_COMMON ninja-build build-essential sqlite3"
  INSTALL_CMD="$SUDO apt-get update && $SUDO apt-get install -y $PKGS"
elif command -v dnf >/dev/null 2>&1; then
  PM="dnf"
  PKGS="$PKGS_COMMON ninja-build gcc-c++ make sqlite"
  INSTALL_CMD="$SUDO dnf install -y $PKGS"
elif command -v yum >/dev/null 2>&1; then
  PM="yum"
  PKGS="$PKGS_COMMON ninja-build gcc-c++ make sqlite"
  INSTALL_CMD="$SUDO yum install -y $PKGS"
elif command -v pacman >/dev/null 2>&1; then
  PM="pacman"
  PKGS="$PKGS_COMMON base-devel ninja sqlite"
  INSTALL_CMD="$SUDO pacman -Sy --noconfirm $PKGS"
elif command -v apk >/dev/null 2>&1; then
  PM="apk"
  PKGS="$PKGS_COMMON build-base ninja sqlite"
  INSTALL_CMD="$SUDO apk add --no-cache $PKGS"
else
  echo "Unsupported package manager. Please manually install: cmake, ninja, a C++ compiler (g++/clang), make, git." >&2
  exit 1
fi

echo "=== Setup Summary ==="
echo "Detected package manager: $PM"
echo "Packages to install: $PKGS"
echo
echo "Running install command (non-interactive)..."
sh -c "$INSTALL_CMD"

# Ensure 'ninja' binary exists
if ! command -v ninja >/dev/null 2>&1 && command -v ninja-build >/dev/null 2>&1; then
  echo "Linking ninja-build -> /usr/local/bin/ninja"
  $SUDO ln -sf "$(command -v ninja-build)" /usr/local/bin/ninja || true
fi

# Fetch Catch2 into external/Catch2 (optional in CI)
EXTERNAL_DIR="$REPO_ROOT/external"
CATCH_DIR="$EXTERNAL_DIR/Catch2"
if [ "${CI_MODE:-0}" -eq 1 ]; then
  echo "CI mode: skipping Fetch Catch2 into $CATCH_DIR (not required in CI)"
else
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
fi

# Install GitHub Copilot CLI if missing (skip in CI)
if [ "${CI_MODE:-0}" -eq 1 ]; then
  echo "CI mode: skipping Copilot CLI installation"
else
  if ! command -v copilot >/dev/null 2>&1; then
    echo "Copilot CLI not found; installing via https://gh.io/copilot-install"
    curl -fsSL https://gh.io/copilot-install | bash
  else
    echo "Copilot CLI already installed"
  fi
fi

echo "Setup complete. Example build: mkdir -p build && cd build && cmake -G Ninja .. && ninja -j$(nproc 2>/dev/null || echo 2)"

# Run checks automatically after setup completes
run_checks
