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
DAEMON_BASENAME="$(basename "$DAEMON")"

# Helper: verify a PID corresponds to a running process whose cmdline contains the script path or basename
is_pid_for_script() {
  pid="$1"
  script="$2"
  if [ -z "$pid" ]; then
    return 1
  fi
  if ! kill -0 "$pid" 2>/dev/null; then
    return 1
  fi
  cmdline="$(ps -p "$pid" -o args= 2>/dev/null || true)"
  if [ -n "$cmdline" ] && (echo "$cmdline" | grep -F -q "$script" || echo "$cmdline" | grep -F -q "$DAEMON_BASENAME"); then
    return 0
  fi
  return 1
}

# Helper: find any existing daemon process running that matches the daemon script path or basename
find_existing_daemon() {
  EXISTING="$(ps -eo pid,args | awk -v pat1="$DAEMON" -v pat2="$DAEMON_BASENAME" '$0 ~ pat1 || $0 ~ pat2 {print $1}')"
  for p in $EXISTING; do
    if [ -z "$p" ]; then
      continue
    fi
    # skip ourselves if accidentally matched
    if [ "$p" = "$$" ] 2>/dev/null; then
      continue
    fi
    if is_pid_for_script "$p" "$DAEMON"; then
      DPID="$p"
      # create pidfile for supervisor to track if missing
      echo "$DPID" >"$DAEMON_PIDFILE" 2>/dev/null || true
      return 0
    fi
  done
  return 1
}

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
    if is_pid_for_script "$DPID" "$DAEMON"; then
      if [ "$DPID" != "$PREV_DPID" ]; then
        printf '%s [SUPERVISOR] Supervisor: daemon running (PID %s)\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$DPID" >>"$SUP_LOGFILE"
        PREV_DPID="$DPID"
      fi
    else
      # Stale PID file
      rm -f "$DAEMON_PIDFILE" 2>/dev/null || true
      PREV_DPID=""
      # Before starting, look for any running daemon processes and adopt them if found
      if find_existing_daemon; then
        printf '%s [SUPERVISOR] Supervisor: found existing daemon (PID %s)\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$DPID" >>"$SUP_LOGFILE"
        PREV_DPID="$DPID"
      else
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
            if is_pid_for_script "$DPID" "$DAEMON"; then
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
    fi
  else
    # Before starting, check for any existing daemon process matching the daemon script path
    if find_existing_daemon; then
      printf '%s [SUPERVISOR] Supervisor: found existing daemon (PID %s)\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$DPID" >>"$SUP_LOGFILE"
      PREV_DPID="$DPID"
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
          if is_pid_for_script "$DPID" "$DAEMON"; then
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
  fi
  sleep "$CHECK_INTERVAL"
done
