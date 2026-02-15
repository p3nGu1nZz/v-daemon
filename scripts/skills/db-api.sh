#!/usr/bin/env sh
# Lightweight shell wrapper for the Python db-api helper.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PYWRAP="$REPO_ROOT/scripts/skills/db-api.py"

if [ -x "$PYWRAP" ]; then
  exec "$PYWRAP" "$@"
else
  exec python3 "$PYWRAP" "$@"
fi
