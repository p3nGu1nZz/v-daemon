#!/usr/bin/env sh
# Backward-compatible wrapper: moved to scripts/lib/daemon.sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/lib/daemon.sh" "$@"
