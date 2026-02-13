#!/usr/bin/env sh
# Supervisor loop: ensure daemon is running, restart if it dies, and log activity.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DAEMON="${SCRIPT_DIR}/daemon.sh"
DAEMON_PIDFILE="/tmp/v-daemon.pid"
SUP_PIDFILE="/tmp/v-daemon-supervisor.pid"
mkdir -p "$REPO_ROOT/logs"
LOGFILE="${REPO_ROOT}/logs/daemon.log"
SUP_LOGFILE="${REPO_ROOT}/logs/supervisor.log"
CHECK_INTERVAL="${CHECK_INTERVAL:-30}"

# Write supervisor pidfile
echo $$ >"$SUP_PIDFILE"
trap 'rm -f "$SUP_PIDFILE"; exit 0' INT TERM EXIT

# Ensure log files exist
mkdir -p "$REPO_ROOT/logs"
touch "$LOGFILE" "$SUP_LOGFILE"

# Report startup immediately so monitors see supervisor pid before daemon heartbeats
printf '%s [SUP] Supervisor: started (PID %s)\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$$" >>"$SUP_LOGFILE"

# Start tail to stream daemon logs to supervisor stdout (non-blocking)
# Prefix forwarded daemon lines so the combined supervisor log contains both [SUP] and [DAEMON] entries
tail -n 0 -F "$LOGFILE" 2>/dev/null | sed "s/^/[DAEMON] /" &
TAIL_PID=$!

# Clean up on exit
cleanup() {
  [ -n "${TAIL_PID:-}" ] && kill "$TAIL_PID" 2>/dev/null || true
  rm -f "$SUP_PIDFILE"
  exit 0
}
trap 'cleanup' INT TERM EXIT

while true; do
  if [ -f "$DAEMON_PIDFILE" ]; then
    DPID=$(cat "$DAEMON_PIDFILE" 2>/dev/null || true)
    if [ -n "$DPID" ] && kill -0 "$DPID" 2>/dev/null; then
      printf '%s [SUP] Supervisor: daemon running (PID %s)\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$DPID" >>"$SUP_LOGFILE"
    else
      # Stale PID file
      rm -f "$DAEMON_PIDFILE" 2>/dev/null || true
      printf '%s [SUP] Supervisor: starting daemon\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >>"$SUP_LOGFILE"
      nohup sh "$DAEMON" >>"$LOGFILE" 2>&1 &
      echo $! >"$DAEMON_PIDFILE"
      printf '%s [SUP] Supervisor: started daemon (PID %s)\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$(cat $DAEMON_PIDFILE)" >>"$SUP_LOGFILE"
    fi
  else
    printf '%s [SUP] Supervisor: starting daemon (no pidfile)\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >>"$SUP_LOGFILE"
    nohup sh "$DAEMON" >>"$LOGFILE" 2>&1 &
    echo $! >"$DAEMON_PIDFILE"
    printf '%s [SUP] Supervisor: started daemon (PID %s)\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$(cat $DAEMON_PIDFILE)" >>"$SUP_LOGFILE"
  fi
  sleep "$CHECK_INTERVAL"
done
