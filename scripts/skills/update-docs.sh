#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/skills/update-docs.sh [--help] [args...]

Wrapper for scripts/docs.sh that captures outputs under run/skills/update-docs/<timestamp>/.

Options:
  --help  Show this help and exit.

All other args are forwarded to scripts/docs.sh.
USAGE
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

# Determine repository root and docs script location
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DOCS_SCRIPT="$ROOT_DIR/scripts/docs.sh"

if [ ! -f "$DOCS_SCRIPT" ]; then
  echo "Error: helper script not found: $DOCS_SCRIPT" >&2
  exit 1
fi

# Prepare output directory
TIMESTAMP="$(date -u +"%Y%m%dT%H%M%SZ")"
OUTDIR="$ROOT_DIR/run/skills/update-docs/$TIMESTAMP"
mkdir -p "$OUTDIR"

STDOUT_FILE="$OUTDIR/stdout.txt"
STDERR_FILE="$OUTDIR/stderr.txt"
CMD_FILE="$OUTDIR/command.txt"

# Save the invoked command for audit
printf '%s\n' "$DOCS_SCRIPT $*" >"$CMD_FILE"

# Run the docs script and capture outputs
set +e
"$DOCS_SCRIPT" "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE"
RC=$?
set -e

# Gather git context if available
commit="$(git rev-parse --short HEAD 2>/dev/null || true)"
branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"

# Write a simple JSON report
cat >"$OUTDIR/report.json" <<JSON
{
  "timestamp": "$TIMESTAMP",
  "script": "scripts/docs.sh",
  "args": "$(printf '%s ' "$@" | sed -e "s/\\"/\\\\\"/g")",
  "exit_code": $RC,
  "commit": "$commit",
  "branch": "$branch",
  "stdout": "${STDOUT_FILE}",
  "stderr": "${STDERR_FILE}"
}
JSON

# Provide user-friendly summary
if [ "$RC" -eq 0 ]; then
  echo "update-docs: completed successfully. Outputs: $OUTDIR"
else
  echo "update-docs: completed with exit code $RC. See $STDERR_FILE for errors."
fi

exit $RC
