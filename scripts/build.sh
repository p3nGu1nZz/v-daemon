#!/usr/bin/env sh
# Build helper: configure and build into ./build using CMake + Ninja
set -eu

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  cat <<'USAGE'
Usage: sh scripts/build.sh

Configure and build the project into ./build using CMake + Ninja.
USAGE
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Configure and build
cmake -G Ninja ..
ninja -j$(nproc 2>/dev/null || echo 2)
