#!/usr/bin/env sh
# Merge all logs into a single logs/system.log for easier introspection.
set -eu
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="${LOG_DIR:-$REPO_ROOT/logs}"
SYSTEM_LOG="$LOG_DIR/system.log"
mkdir -p "$LOG_DIR" || true
# Header for run
printf '# == merged logs: %s ==\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" > "$SYSTEM_LOG" || true
# Concatenate all non-empty log files (excluding system.log) in chronological order
for f in $(ls -1t "$LOG_DIR" | grep -v '^system.log$' || true); do
  fp="$LOG_DIR/$f"
  if [ -f "$fp" ] && [ -s "$fp" ]; then
    printf '\n# -- %s (size=%s) --\n' "$f" "$(du -h "$fp" | awk '{print $1}')" >> "$SYSTEM_LOG" 2>/dev/null || true
    sed -n '1,5000p' "$fp" >> "$SYSTEM_LOG" 2>/dev/null || true
  fi
done
# Final marker
printf '\n# == end merged logs: %s ==\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" >> "$SYSTEM_LOG" || true
exit 0
