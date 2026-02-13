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
  # Start supervisor in background
  nohup sh "$SCRIPT_DIR/lib/supervise.sh" >>"$SUP_LOGFILE" 2>&1 &
  BG_PID=$!

  # Wait for supervise.sh to write its pidfile and a startup entry in SUP_LOGFILE
  TIMEOUT=10
  waited=0
  SUPPID=""
  while [ $waited -lt $TIMEOUT ]; do
    if [ -f "$SUP_PIDFILE" ]; then
      SUPPID=$(cat "$SUP_PIDFILE" 2>/dev/null || true)
      if [ -n "$SUPPID" ] && kill -0 "$SUPPID" 2>/dev/null; then
        if grep -q "Supervisor: started" "$SUP_LOGFILE" 2>/dev/null; then
          echo "Started supervisor (PID $SUPPID)"
          return
        fi
      fi
    fi
    sleep 0.2
    waited=$((waited+1))
  done

  # Fallback: report background PID if supervise didn't populate pidfile
  if [ -n "$SUPPID" ]; then
    echo "Started supervisor (PID $SUPPID)"
  else
    echo "Started supervisor (PID $BG_PID) (SUP_PIDFILE not found)"
    # write bg pidfile for convenience
    echo "$BG_PID" >"$SUP_PIDFILE" || true
  fi
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

cleanup_and_exit() {
  echo "Caught interrupt; shutting down supervisor and daemon..." >&2

  # Kill any tails streaming logs
  [ -n "${TAIL_D:-}" ] && kill "$TAIL_D" 2>/dev/null || true
  [ -n "${TAIL_S:-}" ] && kill "$TAIL_S" 2>/dev/null || true

  # Stop supervisor if running
  if [ -f "$SUP_PIDFILE" ]; then
    SUPPID=$(cat "$SUP_PIDFILE" 2>/dev/null || true)
    if [ -n "$SUPPID" ] && kill -0 "$SUPPID" 2>/dev/null; then
      echo "Stopping supervisor (PID $SUPPID)" >&2
      kill "$SUPPID" 2>/dev/null || true
      sleep 1
      if kill -0 "$SUPPID" 2>/dev/null; then
        kill -TERM "$SUPPID" 2>/dev/null || kill -9 "$SUPPID" 2>/dev/null || true
      fi
    fi
    rm -f "$SUP_PIDFILE" 2>/dev/null || true
  fi

  # Stop daemon if running
  if [ -f "$DAEMON_PIDFILE" ]; then
    DPID=$(cat "$DAEMON_PIDFILE" 2>/dev/null || true)
    if [ -n "$DPID" ] && kill -0 "$DPID" 2>/dev/null; then
      echo "Stopping daemon (PID $DPID)" >&2
      kill "$DPID" 2>/dev/null || true
      sleep 1
      if kill -0 "$DPID" 2>/dev/null; then
        kill -TERM "$DPID" 2>/dev/null || kill -9 "$DPID" 2>/dev/null || true
      fi
    fi
    rm -f "$DAEMON_PIDFILE" 2>/dev/null || true
  fi

  exit 130
}

monitor_foreground() {
  echo "Monitor: streaming daemon and supervisor logs (press Ctrl-C to exit)"
  touch "$LOGFILE" "$SUP_LOGFILE"

  # Start tails: daemon directly (no extra prefix), supervisor prefixed only when missing
  tail -n 0 -F "$LOGFILE" 2>/dev/null &
  TAIL_D=$!
  tail -n 0 -F "$SUP_LOGFILE" 2>/dev/null | sed '/\[SUPERVISOR\]/! s/^/[SUPERVISOR] /' &
  TAIL_S=$!

  # Ensure Ctrl-C triggers clean shutdown of supervisor and daemon
  trap 'cleanup_and_exit' INT TERM

  # Print a single system status line at monitor start
  SUP_RUNNING="not running"
  DAEMON_RUNNING="not running"
  if [ -f "$SUP_PIDFILE" ] && kill -0 "$(cat "$SUP_PIDFILE")" 2>/dev/null; then
    SUP_RUNNING="running (PID $(cat "$SUP_PIDFILE"))"
  fi
  if [ -f "$DAEMON_PIDFILE" ] && kill -0 "$(cat "$DAEMON_PIDFILE")" 2>/dev/null; then
    DAEMON_RUNNING="running (PID $(cat "$DAEMON_PIDFILE"))"
  fi
  printf '%s [SYSTEM] Supervisor: %s | Daemon: %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$SUP_RUNNING" "$DAEMON_RUNNING"
  # Wait on background tails; trap will handle cleanup on INT/TERM
  wait

}

case "${1:-}" in
  start)
    if [ -f "$SUP_PIDFILE" ] && kill -0 "$(cat "$SUP_PIDFILE")" 2>/dev/null; then
      echo "Supervisor already running (PID $(cat "$SUP_PIDFILE"))"
      exit 0
    fi
    # Rotate logs before starting a fresh supervisor
    if [ -x "$SCRIPT_DIR/rotate_logs.sh" ]; then
      sh "$SCRIPT_DIR/rotate_logs.sh" || echo "Log rotation failed" >&2
    fi
    start_supervisor_bg
    if [ "$MONITOR" -eq 1 ]; then
      monitor_foreground
    fi
    ;;
  stop)
    # Stop supervisor via pidfile if present
    if [ -f "$SUP_PIDFILE" ]; then
      SUPPID=$(cat "$SUP_PIDFILE")
      if kill "$SUPPID" 2>/dev/null; then
        echo "Stopped supervisor (PID $SUPPID)"
      else
        echo "Failed to stop supervisor; it may not be running"
      fi
      rm -f "$SUP_PIDFILE"
    else
      echo "Supervisor not running (no pidfile)"
    fi

    # Also kill any orphaned supervise.sh processes under this repo
    echo "Looking for orphaned supervisor processes..." >&2
    PIDS="$(ps -eo pid,args | awk -v pat="$SCRIPT_DIR/lib/supervise.sh" '$0 ~ pat {print $1}')"
    if [ -n "$PIDS" ]; then
      for p in $PIDS; do
        if [ -z "$p" ]; then
          continue
        fi
        if kill -0 "$p" 2>/dev/null; then
          echo "Stopping orphaned supervisor process PID $p" >&2
          kill "$p" 2>/dev/null || true
          # wait up to ~3s (15 * 0.2s) for process to exit
          WAITED=0
          while kill -0 "$p" 2>/dev/null && [ $WAITED -lt 15 ]; do
            sleep 0.2
            WAITED=$((WAITED+1))
          done
          if kill -0 "$p" 2>/dev/null; then
            echo "Force-killing orphaned supervisor process PID $p" >&2
            kill -9 "$p" 2>/dev/null || true
          else
            echo "Stopped orphaned supervisor process PID $p" >&2
          fi
        fi
      done
    fi

    # Stop daemon via pidfile if present
    if [ -f "$DAEMON_PIDFILE" ]; then
      DPID=$(cat "$DAEMON_PIDFILE")
      if kill "$DPID" 2>/dev/null; then
        echo "Stopped daemon (PID $DPID)"
      else
        echo "Failed to stop daemon; it may not be running"
      fi
      rm -f "$DAEMON_PIDFILE"
    else
      echo "Daemon not running (no pidfile)"
    fi

    # Kill any orphaned daemon processes under this repo
    echo "Looking for orphaned daemon processes..." >&2
    PIDS="$(ps -eo pid,args | awk -v pat="$DAEMON" '$0 ~ pat {print $1}')"
    if [ -n "$PIDS" ]; then
      for p in $PIDS; do
        if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
          echo "Killing orphaned daemon process PID $p" >&2
          kill "$p" 2>/dev/null || true
          sleep 1
          if kill -0 "$p" 2>/dev/null; then
            kill -TERM "$p" 2>/dev/null || kill -9 "$p" 2>/dev/null || true
          fi
        fi
      done
    fi

    # Rotate logs after stopping supervisor/daemon
    if [ -x "$SCRIPT_DIR/rotate_logs.sh" ]; then
      sh "$SCRIPT_DIR/rotate_logs.sh" || echo "Log rotation failed" >&2
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



  *)
    usage
    ;;
esac
