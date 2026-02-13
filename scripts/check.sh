#!/usr/bin/env sh
# Check environment and dependencies for building and Docker usage (WSL-friendly)
set -eu

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

if [ "$missing" -ne 0 ]; then
  echo "Some checks failed. Run scripts/setup.sh to install common packages (if supported) and re-run this check." >&2
  exit 2
fi

echo "All checks passed."
