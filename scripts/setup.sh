#!/usr/bin/env sh
# Minimal setup script to install C++ build dependencies and ninja for parallel builds
set -eu

usage() {
  echo "Usage: $0 [--yes|-y]"
  echo "Installs required packages (cmake, ninja, a C++ toolchain, git) for common Linux distros."
  exit 1
}

FORCE=1
while [ "$#" -gt 0 ]; do
  case "$1" in
    -y|--yes) FORCE=1; shift;;
    -h|--help) usage;;
    *) echo "Unknown argument: $1"; usage;;
  esac
done

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

echo "Setup complete. Example build: mkdir -p build && cd build && cmake -G Ninja .. && ninja -j$(nproc 2>/dev/null || echo 2)"
