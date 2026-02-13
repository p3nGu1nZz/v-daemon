#!/usr/bin/env sh
# Rotate and compress logs in ./logs with timestamped gz archives and retention.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$REPO_ROOT/logs"
KEEP=7

usage() {
  cat <<USAGE
Usage: $0 [--keep N]
Rotate and compress logs in $LOG_DIR, keeping N most recent rotations (default: $KEEP).
USAGE
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage ;;
    --keep|-k)
      shift
      KEEP="$1"
      shift ;;
    --keep=*)
      KEEP="${1#*=}"
      shift ;;
    *)
      echo "Unknown arg: $1" >&2
      usage ;;
  esac
done

if [ ! -d "$LOG_DIR" ]; then
  echo "Log directory $LOG_DIR not found, nothing to rotate."
  exit 0
fi

# validate KEEP is a non-negative integer
case "$KEEP" in
  ''|*[!0-9]*)
    echo "Invalid keep value: $KEEP" >&2
    exit 2 ;;
esac

for logfile in "$LOG_DIR"/daemon.log "$LOG_DIR"/supervisor.log; do
  [ -f "$logfile" ] || continue
  if [ ! -s "$logfile" ]; then
    echo "Skipping empty log: $(basename "$logfile")"
    continue
  fi

  timestamp=$(date +%Y%m%dT%H%M%S)
  rotfile="${logfile}.${timestamp}"

  # copytruncate: snapshot current log to timestamped file, then truncate original
  if cp "$logfile" "$rotfile"; then
    : > "$logfile"
    echo "Rotated $(basename "$logfile") -> $(basename "$rotfile")"
  else
    echo "Failed to rotate $(basename "$logfile")" >&2
    continue
  fi

  # remove old rotations beyond KEEP (keep newest KEEP)
  files=$(ls -1t "${logfile}".* 2>/dev/null || true)
  if [ -n "$files" ]; then
    count=0
    for f in $files; do
      count=$((count+1))
      if [ $count -gt "$KEEP" ]; then
        rm -f "$f" || true
        echo "Removed old rotation: $(basename "$f")"
      fi
    done
  fi

done

exit 0
