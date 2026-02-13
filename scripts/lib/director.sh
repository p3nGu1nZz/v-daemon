#!/usr/bin/env bash
# Director agent: coordinates worker agents (minimal stub)
set -eu

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  cat <<'USAGE'
Usage: sh scripts/lib/director.sh

Director agent stub: writes PID to /tmp/v-director.pid and heartbeats to ./logs/director.log
USAGE
  exit 0
fi

PIDFILE="/tmp/v-director.pid"
LOCKDIR="/tmp/v-director.lock"
SCRIPT_NAME="$(basename "$0")"

# Acquire a simple lock using mkdir to avoid concurrent director instances
acquire_lock() {
  for i in 0 1 2; do
    if mkdir "$LOCKDIR" 2>/dev/null; then
      echo "$$" > "$LOCKDIR/pid"
      return 0
    fi
    OWNER_PID="$(cat "$LOCKDIR/pid" 2>/dev/null || true)"
    if [ -n "$OWNER_PID" ] && kill -0 "$OWNER_PID" 2>/dev/null; then
      # Check if the owner PID actually appears to be the director; if not, treat the lock as stale
      cmdline="$(ps -p "$OWNER_PID" -o args= 2>/dev/null || true)"
      if [ -n "$cmdline" ] && echo "$cmdline" | grep -F -q "$SCRIPT_NAME"; then
        # another active owner that looks like the director
        return 1
      else
        # Owner pid is some other process (pid reused) — remove stale lock and retry
        rm -rf "$LOCKDIR" 2>/dev/null || true
        sleep 0.1
        continue
      fi
    fi
    # stale lock, remove and retry
    rm -rf "$LOCKDIR" 2>/dev/null || true
    sleep 0.1
  done
  if mkdir "$LOCKDIR" 2>/dev/null; then
    echo "$$" > "$LOCKDIR/pid"
    return 0
  fi
  return 1
}

# If a director is already running, exit to avoid multiple instances
if [ -f "$PIDFILE" ]; then
  EXIST_PID=$(cat "$PIDFILE" 2>/dev/null || true)
  if [ -n "$EXIST_PID" ] && kill -0 "$EXIST_PID" 2>/dev/null; then
    echo "Director already running (PID $EXIST_PID)" >&2
    exit 0
  else
    # stale pidfile
    rm -f "$PIDFILE" 2>/dev/null || true
  fi
fi

# Acquire lock
if ! acquire_lock; then
  echo "Another director instance appears to be running; exiting" >&2
  exit 0
fi

cleanup() {
  if [ -f "$PIDFILE" ] && [ "$(cat "$PIDFILE" 2>/dev/null || true)" = "$$" ]; then
    rm -f "$PIDFILE"
  fi
  if [ -f "$LOCKDIR/pid" ] && [ "$(cat "$LOCKDIR/pid" 2>/dev/null || true)" = "$$" ]; then
    rm -rf "$LOCKDIR" 2>/dev/null || true
  fi
  exit 0
}
trap 'cleanup' INT TERM EXIT

echo $$ >"$PIDFILE"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
mkdir -p "$REPO_ROOT/logs"
DEV_AUDITS_DIR="$REPO_ROOT/audits"
mkdir -p "$DEV_AUDITS_DIR"
LOGFILE="${REPO_ROOT}/logs/director.log"

echo "$(date +'%Y-%m-%dT%H:%M:%S%z') [AGENT-DIRECTOR] director agent starting (PID $$)" >>"$LOGFILE"
# Source director actions (if present) and run autopilot summary asynchronously
if [ -f "$SCRIPT_DIR/director_actions.sh" ]; then
  . "$SCRIPT_DIR/director_actions.sh"
  # run in background (non-blocking) so director heartbeat continues
  run_autopilot_summary &
fi

# Main loop: emit heartbeat and placeholder for coordination logic
while true; do
  heartbeat_ts=$(date +'%Y-%m-%dT%H:%M:%S%z')
  echo "$heartbeat_ts [AGENT-DIRECTOR] heartbeat" >>"$LOGFILE"
  # Emit structured JSONL heartbeat for auditing
  printf '%s\n' "{\"ts\":\"$heartbeat_ts\",\"event\":\"heartbeat\",\"role\":\"director\",\"pid\":$$}" >>"$DEV_AUDITS_DIR/director-heartbeats.jsonl" || true
  # TODO: implement director coordination (spawn workers, RPC, task queue)
  sleep 60
done
