#!/usr/bin/env sh
# Minimal daemon loop. Replace loop body with self-improving logic later.
set -eu

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  cat <<'USAGE'
Usage: sh scripts/lib/daemon.sh

Minimal daemon loop that writes heartbeat to ./logs/daemon.log and PID to /tmp/v-daemon.pid.
Intended to be managed by scripts/run.sh supervisor.
USAGE
  exit 0
fi

PIDFILE="/tmp/v-daemon.pid"

# If a daemon is already running, exit to avoid multiple writers to the log
if [ -f "$PIDFILE" ]; then
  EXIST_PID=$(cat "$PIDFILE" 2>/dev/null || true)
  if [ -n "$EXIST_PID" ] && kill -0 "$EXIST_PID" 2>/dev/null; then
    echo "Daemon already running (PID $EXIST_PID)" >&2
    exit 0
  else
    # stale pidfile
    rm -f "$PIDFILE" 2>/dev/null || true
  fi
fi

cleanup() {
  # only remove pidfile if it belongs to this process
  if [ -f "$PIDFILE" ] && [ "$(cat "$PIDFILE" 2>/dev/null || true)" = "$$" ]; then
    rm -f "$PIDFILE"
  fi
  exit 0
}
trap 'cleanup' INT TERM EXIT

echo $$ >"$PIDFILE"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Repo root is two levels up from scripts/lib
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
mkdir -p "$REPO_ROOT/logs"
LOGFILE="${REPO_ROOT}/logs/daemon.log"

while true; do
  printf '%s: heartbeat\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >>"$LOGFILE"
  # TODO: insert build / test / self-update steps here
  sleep 60
done
