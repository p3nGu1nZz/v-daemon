#!/usr/bin/env sh
# merge-logs-daemon.sh - simple start/stop/status wrapper for periodic merging of logs into logs/system.log
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="${LOG_DIR:-$REPO_ROOT/logs}"
PIDFILE="${RUN_DIR:-$REPO_ROOT/run}/merge-logs-daemon.pid"
INTERVAL="${MERGE_LOGS_INTERVAL:-60}"
MERGE_SH="$SCRIPT_DIR/merge-logs.sh"

usage() {
  cat <<USAGE
Usage: $0 start|stop|status

start   - run merge-logs periodically in background (every ${INTERVAL}s)
stop    - stop the background daemon
status  - report whether daemon is running
USAGE
}

case "${1:-}" in
  start)
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
      echo "merge-logs-daemon already running (PID $(cat "$PIDFILE"))"
      exit 0
    fi
    # Start background loop
    ( while true; do sh "$MERGE_SH" || true; sleep "$INTERVAL"; done ) &
    echo $! > "$PIDFILE" 2>/dev/null || true
    echo "merge-logs-daemon started (pid $(cat "$PIDFILE" 2>/dev/null))"
    ;;
  stop)
    if [ -f "$PIDFILE" ]; then
      kill "$(cat "$PIDFILE")" 2>/dev/null || true
      rm -f "$PIDFILE" 2>/dev/null || true
      echo "merge-logs-daemon stopped"
    else
      echo "merge-logs-daemon not running"
    fi
    ;;
  status)
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
      echo "merge-logs-daemon running (PID $(cat "$PIDFILE"))"
      exit 0
    else
      echo "merge-logs-daemon not running"
      exit 1
    fi
    ;;
  *)
    usage
    exit 2
    ;;
esac
