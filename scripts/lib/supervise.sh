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

# track last-seen daemon pid to avoid noisy repeated running logs
PREV_DPID=""

# Report startup immediately so monitors see supervisor pid before daemon heartbeats
printf '%s [SUPERVISOR] Supervisor: started (PID %s)\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$$" >>"$SUP_LOGFILE"

# Clean up on exit
cleanup() {
  rm -f "$SUP_PIDFILE"
  exit 0
}
trap 'cleanup' INT TERM EXIT

while true; do
  if [ -f "$DAEMON_PIDFILE" ]; then
    DPID=$(cat "$DAEMON_PIDFILE" 2>/dev/null || true)
    if [ -n "$DPID" ] && kill -0 "$DPID" 2>/dev/null; then
      if [ "$DPID" != "$PREV_DPID" ]; then
        printf '%s [SUPERVISOR] Supervisor: daemon running (PID %s)\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$DPID" >>"$SUP_LOGFILE"
        PREV_DPID="$DPID"
      fi
    else
      # Stale PID file
      rm -f "$DAEMON_PIDFILE" 2>/dev/null || true
      PREV_DPID=""
      printf '%s [SUPERVISOR] Supervisor: starting daemon\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >>"$SUP_LOGFILE"
      # Rotate logs before starting a new daemon if rotate script present and logfile non-empty
      if [ -x "$REPO_ROOT/scripts/rotate_logs.sh" ] && [ -s "$LOGFILE" ]; then
        sh "$REPO_ROOT/scripts/rotate_logs.sh" || true
      fi
      nohup sh "$DAEMON" >>"$LOGFILE" 2>&1 &
      DAEMON_START_PID=$!
      # wait up to ~5s for the daemon to create its own pidfile
      WAITED=0
      while [ $WAITED -lt 25 ]; do
        if [ -f "$DAEMON_PIDFILE" ]; then
          DPID=$(cat "$DAEMON_PIDFILE" 2>/dev/null || true)
          if [ -n "$DPID" ] && kill -0 "$DPID" 2>/dev/null; then
            printf '%s [SUPERVISOR] Supervisor: started daemon (PID %s)\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$DPID" >>"$SUP_LOGFILE"
            PREV_DPID="$DPID"
            break
          fi
        fi
        sleep 0.2
        WAITED=$((WAITED+1))
      done
      if [ ! -f "$DAEMON_PIDFILE" ]; then
        # fallback: write the pid we started
        echo "$DAEMON_START_PID" >"$DAEMON_PIDFILE" 2>/dev/null || true
        printf '%s [SUPERVISOR] Supervisor: started daemon (PID %s) (pidfile created by supervisor)\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$DAEMON_START_PID" >>"$SUP_LOGFILE"
        PREV_DPID="$DAEMON_START_PID"
      fi
    fi
  else
    printf '%s [SUPERVISOR] Supervisor: starting daemon (no pidfile)\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >>"$SUP_LOGFILE"
    # Rotate logs before starting a new daemon if rotate script present and logfile non-empty
    if [ -x "$REPO_ROOT/scripts/rotate_logs.sh" ] && [ -s "$LOGFILE" ]; then
      sh "$REPO_ROOT/scripts/rotate_logs.sh" || true
    fi
    nohup sh "$DAEMON" >>"$LOGFILE" 2>&1 &
    DAEMON_START_PID=$!
    WAITED=0
    while [ $WAITED -lt 25 ]; do
      if [ -f "$DAEMON_PIDFILE" ]; then
        DPID=$(cat "$DAEMON_PIDFILE" 2>/dev/null || true)
        if [ -n "$DPID" ] && kill -0 "$DPID" 2>/dev/null; then
          printf '%s [SUPERVISOR] Supervisor: started daemon (PID %s)\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$DPID" >>"$SUP_LOGFILE"
          PREV_DPID="$DPID"
          break
        fi
      fi
      sleep 0.2
      WAITED=$((WAITED+1))
    done
    if [ ! -f "$DAEMON_PIDFILE" ]; then
      echo "$DAEMON_START_PID" >"$DAEMON_PIDFILE" 2>/dev/null || true
      printf '%s [SUPERVISOR] Supervisor: started daemon (PID %s) (pidfile created by supervisor)\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$DAEMON_START_PID" >>"$SUP_LOGFILE"
      PREV_DPID="$DAEMON_START_PID"
    fi
  fi
  sleep "$CHECK_INTERVAL"
done
