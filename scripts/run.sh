#!/usr/bin/env sh
# Supervisor and run helper: starts and monitors the daemon (scripts/lib/daemon.sh)
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Load configuration and defaults
if [ -f "$REPO_ROOT/scripts/lib/config.sh" ]; then
  . "$REPO_ROOT/scripts/lib/config.sh"
  config_init "$REPO_ROOT"
fi
DAEMON="${SCRIPT_DIR}/lib/daemon.sh"
DIRECTOR="${SCRIPT_DIR}/lib/director.sh"
mkdir -p "$RUN_DIR" "$LOG_DIR"
DAEMON_PIDFILE="${DAEMON_PIDFILE:-$RUN_DIR/v-daemon.pid}"
DIRECTOR_PIDFILE="${DIRECTOR_PIDFILE:-$RUN_DIR/v-director.pid}"
SUP_PIDFILE="${SUP_PIDFILE:-$RUN_DIR/v-daemon-supervisor.pid}"
LOGFILE="${DAEMON_LOG:-$LOG_DIR/daemon.log}"
SUP_LOGFILE="${SUP_LOGFILE:-$LOG_DIR/supervisor.log}"
DIRECTOR_LOG="${DIRECTOR_LOG:-$LOG_DIR/director.log}"
CHECK_INTERVAL="${CHECK_INTERVAL:-30}"
# Source process controller if available
if [ -f "$SCRIPT_DIR/lib/process.sh" ]; then
  . "$SCRIPT_DIR/lib/process.sh"
fi

# Helper: verify that a PID corresponds to a running process whose args contain the expected script path
is_pid_for_script() {
  pid="$1"
  script="$2"
  if [ -z "$pid" ]; then
    return 1
  fi
  if ! kill -0 "$pid" 2>/dev/null; then
    return 1
  fi
  # Get the command line for the pid and check for the script path
  cmdline="$(ps -p "$pid" -o args= 2>/dev/null || true)"
  if [ -n "$cmdline" ] && echo "$cmdline" | grep -F -q "$script"; then
    return 0
  fi
  return 1
}

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
      if is_pid_for_script "$SUPPID" "$SCRIPT_DIR/lib/supervise.sh"; then
        if grep -q "Supervisor: started" "$SUP_LOGFILE" 2>/dev/null; then
          echo "Started supervisor (PID $SUPPID)" >&2
          return
        fi
      fi
    fi
    sleep 0.2
    waited=$((waited+1))
  done

  # Fallback: report background PID if supervise didn't populate pidfile
  if [ -n "$SUPPID" ]; then
    echo "Started supervisor (PID $SUPPID)" >&2
  else
    echo "Started supervisor (PID $BG_PID) (SUP_PIDFILE not found)" >&2
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
  [ -n "${TAIL_DIR:-}" ] && kill "$TAIL_DIR" 2>/dev/null || true

  # Try to stop supervisor/daemon processes and any orphans
  stop_all

  # Ensure director is stopped
  if [ -n "${DIRECTOR_PIDFILE:-}" ] && [ -f "$SCRIPT_DIR/lib/process.sh" ]; then
    stop_by_pidfile "$DIRECTOR_PIDFILE" || true
  fi

  exit 130
}

kill_pid_and_children() {
  target="$1"
  if [ -z "$target" ]; then
    return 1
  fi
  # Prefer using proc_kill_tree if available (sourced from process.sh)
  if command -v proc_kill_tree >/dev/null 2>&1; then
    proc_kill_tree "$target" || true
    return 0
  fi

  # Fallback: best-effort tree kill using ps
  tmp="$(mktemp "/tmp/kill_tree_XXXXXX")" || tmp="/tmp/kill_tree_$target"
  echo "$target" >"$tmp"
  while :; do
    prev=$(wc -l <"$tmp" 2>/dev/null || echo 0)
    for pid in $(cat "$tmp"); do
      for child in $(ps -eo pid,ppid 2>/dev/null | awk -v p="$pid" '$2==p {print $1}'); do
        if ! grep -q "^$child$" "$tmp" 2>/dev/null; then
          echo "$child" >>"$tmp"
        fi
      done
    done
    now=$(wc -l <"$tmp" 2>/dev/null || echo 0)
    if [ "$now" -eq "$prev" ]; then
      break
    fi
  done

  # kill in reverse order (children first)
  for pid in $(awk '{a[NR]=$0} END{for(i=NR;i>=1;i--)print a[i]}' "$tmp"); do
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
  done
  sleep 0.2
  for pid in $(awk '{a[NR]=$0} END{for(i=NR;i>=1;i--)print a[i]}' "$tmp"); do
    if kill -0 "$pid" 2>/dev/null; then
      kill -TERM "$pid" 2>/dev/null || true
      sleep 0.1
      if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null || true
      fi
    fi
  done
  rm -f "$tmp" 2>/dev/null || true
  return 0
}

stop_all() {
  MAX_ATTEMPTS=10
  ATTEMPT=0
  while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    FOUND=0

    # Stop supervisor via pidfile
    if [ -f "$SUP_PIDFILE" ]; then
      SUPPID=$(cat "$SUP_PIDFILE" 2>/dev/null || true)
      if [ -n "$SUPPID" ] && kill -0 "$SUPPID" 2>/dev/null; then
        echo "Stopping supervisor (PID $SUPPID)" >&2
        kill_pid_and_children "$SUPPID" || true
      fi
      rm -f "$SUP_PIDFILE" 2>/dev/null || true
      FOUND=1
    fi

    # Kill any orphaned supervise.sh processes under this repo
    PIDS="$(ps -eo pid,args | awk -v pat=\"$SCRIPT_DIR/lib/supervise.sh\" '$0 ~ pat {print $1}')"
    if [ -n "$PIDS" ]; then
      for p in $PIDS; do
        if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
          echo "Killing orphaned supervisor process PID $p" >&2
          kill_pid_and_children "$p" || true
          FOUND=1
        fi
      done
    fi

    # Stop daemon via pidfile
    if [ -f "$DAEMON_PIDFILE" ]; then
      DPID=$(cat "$DAEMON_PIDFILE" 2>/dev/null || true)
      if [ -n "$DPID" ] && kill -0 "$DPID" 2>/dev/null; then
        echo "Stopping daemon (PID $DPID)" >&2
        kill_pid_and_children "$DPID" || true
      fi
      rm -f "$DAEMON_PIDFILE" 2>/dev/null || true
      FOUND=1
    fi

    # Kill any orphaned daemon processes under this repo
    PIDS="$(ps -eo pid,args | awk -v pat=\"$DAEMON\" '$0 ~ pat {print $1}')"
    if [ -n "$PIDS" ]; then
      for p in $PIDS; do
        if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
          echo "Killing orphaned daemon process PID $p" >&2
          kill_pid_and_children "$p" || true
          FOUND=1
        fi
      done
    fi

    # Stop director via pidfile
    if [ -f "$DIRECTOR_PIDFILE" ]; then
      DPID2=$(cat "$DIRECTOR_PIDFILE" 2>/dev/null || true)
      if [ -n "$DPID2" ] && kill -0 "$DPID2" 2>/dev/null; then
        echo "Stopping director (PID $DPID2)" >&2
        kill_pid_and_children "$DPID2" || true
      fi
      rm -f "$DIRECTOR_PIDFILE" 2>/dev/null || true
      FOUND=1
    fi

    # Kill any orphaned director processes under this repo
    PIDS="$(ps -eo pid,args | awk -v pat=\"$DIRECTOR\" '$0 ~ pat {print $1}')"
    if [ -n "$PIDS" ]; then
      for p in $PIDS; do
        if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
          echo "Killing orphaned director process PID $p" >&2
          kill_pid_and_children "$p" || true
          FOUND=1
        fi
      done
    fi

    if [ $FOUND -eq 0 ]; then
      break
    fi
    ATTEMPT=$((ATTEMPT+1))
    sleep 0.2
  done

  if [ $ATTEMPT -ge $MAX_ATTEMPTS ]; then
    echo "Warning: some supervisor/daemon processes may still be running after $MAX_ATTEMPTS attempts" >&2
  fi
}

monitor_foreground() {
  echo "Monitor: streaming daemon and supervisor logs (press Ctrl-C to exit)" >&2
  touch "$LOGFILE" "$SUP_LOGFILE"

  # Start tails: daemon directly (no extra prefix), supervisor prefixed only when missing
  tail -n 0 -F "$LOGFILE" 2>/dev/null &
  TAIL_D=$!
  tail -n 0 -F "$SUP_LOGFILE" 2>/dev/null | sed '/\[SUPERVISOR\]/! s/^/[SUPERVISOR] /' &
  TAIL_S=$!
  touch "$DIRECTOR_LOG"
  tail -n 0 -F "$DIRECTOR_LOG" 2>/dev/null &
  TAIL_DIR=$!

  # Ensure Ctrl-C triggers clean shutdown of supervisor and daemon
  trap 'cleanup_and_exit' INT TERM

  # Print a single system status line at monitor start
  SUP_RUNNING="not running"
  DAEMON_RUNNING="not running"
  if [ -f "$SUP_PIDFILE" ]; then
    SUPPID=$(cat "$SUP_PIDFILE" 2>/dev/null || true)
    if is_pid_for_script "$SUPPID" "$SCRIPT_DIR/lib/supervise.sh"; then
      SUP_RUNNING="running (PID $SUPPID)"
    fi
  fi
  if [ -f "$DAEMON_PIDFILE" ]; then
    DPID=$(cat "$DAEMON_PIDFILE" 2>/dev/null || true)
    if is_pid_for_script "$DPID" "$DAEMON"; then
      DAEMON_RUNNING="running (PID $DPID)"
    fi
  fi
  printf '%s [SYSTEM] Supervisor: %s | Daemon: %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$SUP_RUNNING" "$DAEMON_RUNNING" >&2
  # Wait on background tails; trap will handle cleanup on INT/TERM
  wait

}

case "${1:-}" in
  start)
    if [ -f "$SUP_PIDFILE" ] && is_pid_for_script "$(cat "$SUP_PIDFILE")" "$SCRIPT_DIR/lib/supervise.sh"; then
      echo "Supervisor already running (PID $(cat "$SUP_PIDFILE"))"
      exit 0
    fi
    # Rotate logs before starting a fresh supervisor
    if [ -x "$SCRIPT_DIR/lib/rotate_logs.sh" ]; then
      sh "$SCRIPT_DIR/lib/rotate_logs.sh" || echo "Log rotation failed" >&2
    fi
    start_supervisor_bg
    if [ "$MONITOR" -eq 1 ]; then
      monitor_foreground
    fi
    ;;
  stop)
    # Stopping supervisor and daemon (including any orphaned processes) until none remain
    stop_all

    # Rotate logs after stopping supervisor/daemon
    if [ -x "$SCRIPT_DIR/lib/rotate_logs.sh" ]; then
      sh "$SCRIPT_DIR/lib/rotate_logs.sh" || echo "Log rotation failed" >&2
    fi

    if [ "$MONITOR" -eq 1 ]; then
      monitor_foreground
    fi
    ;;
  status)
    if [ -f "$SUP_PIDFILE" ] && is_pid_for_script "$(cat "$SUP_PIDFILE")" "$SCRIPT_DIR/lib/supervise.sh"; then
      echo "Supervisor running (PID $(cat "$SUP_PIDFILE"))"
    else
      echo "Supervisor not running"
    fi
    if [ -f "$DAEMON_PIDFILE" ] && is_pid_for_script "$(cat "$DAEMON_PIDFILE")" "$DAEMON"; then
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