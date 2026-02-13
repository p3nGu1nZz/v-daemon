#!/usr/bin/env sh
# Supervisor and run helper: starts and monitors the daemon (scripts/lib/daemon.sh)
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DAEMON="${SCRIPT_DIR}/lib/daemon.sh"
DAEMON_PIDFILE="/tmp/v-daemon.pid"
SUP_PIDFILE="/tmp/v-daemon-supervisor.pid"
mkdir -p "$REPO_ROOT/logs"
LOGFILE="${REPO_ROOT}/logs/daemon.log"
SUP_LOGFILE="${REPO_ROOT}/logs/supervisor.log"
CHECK_INTERVAL="${CHECK_INTERVAL:-30}"

usage() {
  cat <<'USAGE'
Usage: sh scripts/run.sh [--monitor] <command>

Commands:
  start           Start the supervisor (background).
  stop            Stop supervisor and daemon.
  status          Print supervisor and daemon status.
  supervise       Internal supervisor loop (used by start).

Options:
  --monitor, -m   After running the command, stream daemon and supervisor logs and print status lines (runs in foreground).

Environment:
  CHECK_INTERVAL  Seconds between supervisor checks (default: 30).

Logs:
  ./logs/daemon.log
  ./logs/supervisor.log
USAGE
  exit 0
}

start_supervisor_bg() {
  nohup sh "$SCRIPT_DIR/run.sh" supervise >>"$SUP_LOGFILE" 2>&1 &
  echo $! >"$SUP_PIDFILE"
  echo "Started supervisor (PID $(cat "$SUP_PIDFILE"))"
}

# Parse optional --monitor flag anywhere in args and rebuild positional params without it
MONITOR=0
for a in "$@"; do
  if [ "$a" = "--monitor" ] || [ "$a" = "-m" ]; then
    MONITOR=1
  fi
done

REMAINING=""
while [ $# -gt 0 ]; do
  case "$1" in
    --monitor|-m)
      shift;;
    -h|--help)
      usage;;
    *)
      # escape any double quotes in the arg
      esc=$(printf '%s' "$1" | sed 's/"/\\"/g')
      REMAINING="$REMAINING \"$esc\""
      shift;;
  esac
done

# restore positional params to remaining non-flag args
if [ -n "$REMAINING" ]; then
  eval set -- $REMAINING
else
  set --
fi

monitor_foreground() {
  echo "Monitor: streaming daemon and supervisor logs (press Ctrl-C to exit)"
  touch "$LOGFILE" "$SUP_LOGFILE"

  # Start tails with prefixes
  tail -n 0 -F "$LOGFILE" 2>/dev/null | sed "s/^/[DAEMON] /" &
  TAIL_D=$!
  tail -n 0 -F "$SUP_LOGFILE" 2>/dev/null | sed "s/^/[SUP] /" &
  TAIL_S=$!

  trap 'kill "$TAIL_D" "$TAIL_S" 2>/dev/null || true; exit 0' INT TERM EXIT

  # Periodic status updates (will intermix with logs)
  while true; do
    SUP_RUNNING="not running"
    DAEMON_RUNNING="not running"
    if [ -f "$SUP_PIDFILE" ] && kill -0 "$(cat "$SUP_PIDFILE")" 2>/dev/null; then
      SUP_RUNNING="running (PID $(cat "$SUP_PIDFILE"))"
    fi
    if [ -f "$DAEMON_PIDFILE" ] && kill -0 "$(cat "$DAEMON_PIDFILE")" 2>/dev/null; then
      DAEMON_RUNNING="running (PID $(cat "$DAEMON_PIDFILE"))"
    fi
    printf '%s [STATUS] Supervisor: %s | Daemon: %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$SUP_RUNNING" "$DAEMON_RUNNING"
    sleep "$CHECK_INTERVAL"
  done
}

case "${1:-}" in
  start)
    if [ -f "$SUP_PIDFILE" ] && kill -0 "$(cat "$SUP_PIDFILE")" 2>/dev/null; then
      echo "Supervisor already running (PID $(cat "$SUP_PIDFILE"))"
      exit 0
    fi
    start_supervisor_bg
    if [ "$MONITOR" -eq 1 ]; then
      monitor_foreground
    fi
    ;;
  stop)
    # Stop supervisor
    if [ -f "$SUP_PIDFILE" ]; then
      SUPPID=$(cat "$SUP_PIDFILE")
      if kill "$SUPPID" 2>/dev/null; then
        echo "Stopped supervisor (PID $SUPPID)"
      else
        echo "Failed to stop supervisor; it may not be running"
      fi
      rm -f "$SUP_PIDFILE"
    else
      echo "Supervisor not running"
    fi
    # Stop daemon
    if [ -f "$DAEMON_PIDFILE" ]; then
      DPID=$(cat "$DAEMON_PIDFILE")
      if kill "$DPID" 2>/dev/null; then
        echo "Stopped daemon (PID $DPID)"
      else
        echo "Failed to stop daemon; it may not be running"
      fi
      rm -f "$DAEMON_PIDFILE"
    else
      echo "Daemon not running"
    fi
    if [ "$MONITOR" -eq 1 ]; then
      monitor_foreground
    fi
    ;;
  status)
    if [ -f "$SUP_PIDFILE" ] && kill -0 "$(cat "$SUP_PIDFILE")" 2>/dev/null; then
      echo "Supervisor running (PID $(cat "$SUP_PIDFILE"))"
    else
      echo "Supervisor not running"
    fi
    if [ -f "$DAEMON_PIDFILE" ] && kill -0 "$(cat "$DAEMON_PIDFILE")" 2>/dev/null; then
      echo "Daemon running (PID $(cat "$DAEMON_PIDFILE"))"
    else
      echo "Daemon not running"
    fi
    if [ "$MONITOR" -eq 1 ]; then
      monitor_foreground
    fi
    ;;


  supervise)
    # Supervisor loop: ensure daemon is running, restart if it dies, stream logs to console
    echo $$ >"$SUP_PIDFILE"
    trap 'rm -f "$SUP_PIDFILE"; exit 0' INT TERM EXIT

    # Ensure log files exist
    touch "$LOGFILE" "$SUP_LOGFILE"

    # Start tail to stream daemon logs to console (non-blocking)
    tail -n 0 -F "$LOGFILE" 2>/dev/null &
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
          printf '%s Supervisor: daemon running (PID %s)\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$DPID" >>"$SUP_LOGFILE"
        else
          # Stale PID file
          rm -f "$DAEMON_PIDFILE" 2>/dev/null || true
          printf '%s Supervisor: starting daemon\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >>"$SUP_LOGFILE"
          nohup sh "$DAEMON" >>"$LOGFILE" 2>&1 &
          echo $! >"$DAEMON_PIDFILE"
          printf '%s Supervisor: started daemon (PID %s)\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$(cat $DAEMON_PIDFILE)" >>"$SUP_LOGFILE"
        fi
      else
        printf '%s Supervisor: starting daemon (no pidfile)\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >>"$SUP_LOGFILE"
        nohup sh "$DAEMON" >>"$LOGFILE" 2>&1 &
        echo $! >"$DAEMON_PIDFILE"
        printf '%s Supervisor: started daemon (PID %s)\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$(cat $DAEMON_PIDFILE)" >>"$SUP_LOGFILE"
      fi
      sleep "$CHECK_INTERVAL"
    done
    ;;
  *)
    usage
    ;;
esac
