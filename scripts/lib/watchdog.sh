#!/usr/bin/env sh
# Lightweight watchdog to remove duplicate tail -F processes mirroring log files
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_DIR="${LOG_DIR:-$REPO_ROOT/logs}"
# Targets to deduplicate; add others if needed
TARGETS="$LOG_DIR/director.log $LOG_DIR/system.log $LOG_DIR/daemon.log $LOG_DIR/supervisor.log"

for tgt in $TARGETS; do
  # find tail processes watching this target
  pids=$(ps -eo pid,args 2>/dev/null | awk -v pat="$tgt" '$0 ~ pat && $0 ~ /tail/ {print $1}' | tr '\n' ' ' | sed 's/ $//')
  [ -z "$pids" ] && continue
  # Keep the most recent PID (largest numeric value); kill the rest
  keep=$(echo "$pids" | tr ' ' '\n' | awk '{print $0}' | sort -n | tail -n1)
  for pid in $(echo "$pids" | tr ' ' '\n'); do
    if [ "$pid" != "$keep" ]; then
      if kill -0 "$pid" 2>/dev/null; then
        # best-effort graceful then force
        kill "$pid" 2>/dev/null || true
        sleep 0.2
        if kill -0 "$pid" 2>/dev/null; then
          kill -9 "$pid" 2>/dev/null || true
        fi
        # Log the action to system.log when possible
        if [ -w "$LOG_DIR" ] || [ -f "$LOG_DIR/system.log" ]; then
          ts="$(date +'%Y-%m-%dT%H:%M:%S%z')"
          printf '%s [WATCHDOG] Removed duplicate tail pid %s for %s\n' "$ts" "$pid" "$tgt" >> "$LOG_DIR/system.log" 2>/dev/null || true
        fi
      fi
    fi
  done
done
