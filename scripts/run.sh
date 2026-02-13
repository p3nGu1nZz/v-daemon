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
# Load environment helper which sets RUN_DIR, LOG_DIR, etc.
if [ -f "$REPO_ROOT/scripts/lib/env.sh" ]; then
  . "$REPO_ROOT/scripts/lib/env.sh"
  env_init "$REPO_ROOT"
fi
# console/logger/prompts are loaded by env_init in scripts/lib/env.sh
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
  # Get the command line for the pid and check for the script path or basename
  cmdline="$(ps -p "$pid" -o args= 2>/dev/null || true)"
  script_base="$(basename "$script")"
  if [ -n "$cmdline" ] && (echo "$cmdline" | grep -F -q "$script" || echo "$cmdline" | grep -F -q "$script_base"); then
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
      # Accept if pidfile points to a live process even when cmdline matching fails
      if [ -n "$SUPPID" ] && ( is_pid_for_script "$SUPPID" "$SCRIPT_DIR/lib/supervise.sh" || kill -0 "$SUPPID" 2>/dev/null ); then
        if grep -q "Supervisor: started" "$SUP_LOGFILE" 2>/dev/null; then
          printf 'Started supervisor (PID %s)\n' "$SUPPID" >&2
          return
        fi
      fi
    fi
    sleep 0.2
    waited=$((waited+1))
  done

  # Fallback: report background PID if supervise didn't populate pidfile
  if [ -n "$SUPPID" ]; then
    if ( is_pid_for_script "$SUPPID" "$SCRIPT_DIR/lib/supervise.sh" || kill -0 "$SUPPID" 2>/dev/null ); then
      printf 'Started supervisor (PID %s)\n' "$SUPPID" >&2
    else
      printf 'Started supervisor (PID %s) (pidfile present but process not running)\n' "$SUPPID" >&2
    fi
  else
    printf 'Started supervisor (PID %s) (SUP_PIDFILE not found)\n' "$BG_PID" >&2
    # write bg pidfile for convenience
    printf '%s\n' "$BG_PID" >"$SUP_PIDFILE" || true
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
  [ -n "${STATUS_PID:-}" ] && kill "$STATUS_PID" 2>/dev/null || true

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
      for child in $(ps_fallback pid,ppid | awk -v p="$pid" '$2==p {print $1}'); do
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
    PIDS="$(ps_fallback pid,args | awk -v pat=\"$SCRIPT_DIR/lib/supervise.sh\" '$0 ~ pat {print $1}')"
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
    PIDS="$(ps_fallback pid,args | awk -v pat=\"$DAEMON\" '$0 ~ pat {print $1}')"
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
    PIDS="$(ps_fallback pid,args | awk -v pat=\"$DIRECTOR\" '$0 ~ pat {print $1}')"
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
  printf 'Monitor: streaming daemon and supervisor logs (press Ctrl-C to exit)\n' >&2
  touch "$LOGFILE" "$SUP_LOGFILE" "$DIRECTOR_LOG"

  # Ensure Ctrl-C triggers clean shutdown of supervisor and daemon
  trap 'cleanup_and_exit' INT TERM

  # Print an initial system status line (before starting tails to avoid interleaving)
  SUP_RUNNING="not running"
  DAEMON_RUNNING="not running"
  if [ -f "$SUP_PIDFILE" ]; then
    SUPPID=$(cat "$SUP_PIDFILE" 2>/dev/null || true)
    if [ -n "$SUPPID" ] && ( is_pid_for_script "$SUPPID" "$SCRIPT_DIR/lib/supervise.sh" || ps -p "$SUPPID" >/dev/null 2>&1 ); then
      SUP_RUNNING="running (PID $SUPPID)"
    fi
  fi
  if [ -f "$DAEMON_PIDFILE" ]; then
    DPID=$(cat "$DAEMON_PIDFILE" 2>/dev/null || true)
    if [ -n "$DPID" ] && ( is_pid_for_script "$DPID" "$DAEMON" || ps -p "$DPID" >/dev/null 2>&1 ); then
      DAEMON_RUNNING="running (PID $DPID)"
    fi
  fi

  # Compute initial worker count
  WORKER_COUNT=0
  if command -v ps_fallback >/dev/null 2>&1; then
    WORKER_PIDS="$(ps_fallback pid,args 2>/dev/null | awk 'tolower($0) ~ /worker/ {print $1}' | sort -u)"
  else
    WORKER_PIDS="$(ps -eo pid,args 2>/dev/null | awk 'tolower($0) ~ /worker/ {print $1}' | sort -u)"
  fi
  for wp in $WORKER_PIDS; do
    if [ -n "$wp" ] && kill -0 "$wp" 2>/dev/null; then
      WORKER_COUNT=$((WORKER_COUNT+1))
    fi
  done

  if [ "$WORKER_COUNT" -gt 0 ] || ([ -f "$SUP_PIDFILE" ] && kill -0 "$(cat \"$SUP_PIDFILE\")" 2>/dev/null); then
    SWARM_STATUS="swarm running ($WORKER_COUNT workers)"
  else
    SWARM_STATUS="swarm offline"
  fi

  # Initial uptime: prefer daemon pidfile mtime when available
  UPTIME_FMT="0:00:00"
  if [ -f "$DAEMON_PIDFILE" ]; then
    pf_mtime=$(stat -c %Y "$DAEMON_PIDFILE" 2>/dev/null || true)
    if [ -n "$pf_mtime" ]; then
      now_ts=$(date +%s)
      uptime_secs=$((now_ts - pf_mtime))
      h=$((uptime_secs/3600)); m=$(((uptime_secs%3600)/60)); s=$((uptime_secs%60))
      UPTIME_FMT=$(printf '%d:%02d:%02d' $h $m $s)
    fi
  fi

  printf '%s [SYSTEM] Supervisor: %s | Daemon: %s | Uptime: %s | %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$SUP_RUNNING" "$DAEMON_RUNNING" "$UPTIME_FMT" "$SWARM_STATUS" >&2

  # Start tails after printing status so outputs don't interleave with the status line
  tail -n 0 -F "$LOGFILE" 2>/dev/null &
  TAIL_D=$!
  tail -n 0 -F "$SUP_LOGFILE" 2>/dev/null | sed '/\[SUPERVISOR\]/! s/^/[SUPERVISOR] /' &
  TAIL_S=$!
  tail -n 0 -F "$DIRECTOR_LOG" 2>/dev/null &
  TAIL_DIR=$!

  # Background refresher to update an anchored status line with uptime/errors/swarm state
  monitor_start_ts=$(date +%s)
  # Record whether monitor started while swarm was active; only auto-exit if it was
  INITIAL_ACTIVE=0
  if [ "$SWARM_STATUS" != "swarm offline" ]; then
    INITIAL_ACTIVE=1
  fi

  refresh_status_loop() {
    while :; do
      now_ts=$(date +%s)
      # Uptime: prefer daemon pidfile mtime, fall back to monitor runtime
      if [ -f "$DAEMON_PIDFILE" ]; then
        pf_mtime=$(stat -c %Y "$DAEMON_PIDFILE" 2>/dev/null || true)
        if [ -n "$pf_mtime" ]; then
          uptime_secs=$((now_ts - pf_mtime))
        else
          uptime_secs=$((now_ts - monitor_start_ts))
        fi
      else
        uptime_secs=$((now_ts - monitor_start_ts))
      fi
      h=$((uptime_secs/3600)); m=$(((uptime_secs%3600)/60)); s=$((uptime_secs%60))
      uptime_fmt=$(printf '%d:%02d:%02d' $h $m $s)

      # Error count from logs (case-insensitive match on error/failed/exception)
      ERRORS=0
      ERRORS=$(grep -i -E "error|failed|exception" "$LOGFILE" "$SUP_LOGFILE" "$DIRECTOR_LOG" 2>/dev/null | wc -l || true)

      # Worker count
      WORKER_COUNT=0
      if command -v ps_fallback >/dev/null 2>&1; then
        WORKER_PIDS="$(ps_fallback pid,args 2>/dev/null | awk 'tolower($0) ~ /worker/ {print $1}' | sort -u)"
      else
        WORKER_PIDS="$(ps -eo pid,args 2>/dev/null | awk 'tolower($0) ~ /worker/ {print $1}' | sort -u)"
      fi
      for wp in $WORKER_PIDS; do
        if [ -n "$wp" ] && kill -0 "$wp" 2>/dev/null; then
          WORKER_COUNT=$((WORKER_COUNT+1))
        fi
      done

      if [ "$WORKER_COUNT" -gt 0 ] || ([ -f "$SUP_PIDFILE" ] && kill -0 "$(cat \"$SUP_PIDFILE\")" 2>/dev/null); then
        SWARM_STATUS="swarm running ($WORKER_COUNT workers)"
      else
        SWARM_STATUS="swarm offline"
      fi

      status_line="[SYSTEM] Uptime: $uptime_fmt | errors: $ERRORS | $SWARM_STATUS"
      # Save cursor, move to bottom, clear line, print status, restore cursor
      printf '\033[s\033[999B\033[2K\r%s\033[u' "$status_line" >&2

      # If the swarm was active when the monitor started but is now offline, exit monitor gracefully
      if [ "$INITIAL_ACTIVE" -eq 1 ] && [ "$SWARM_STATUS" = "swarm offline" ]; then
        printf '%s [SYSTEM] Detected external shutdown; exiting monitor\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >&2
        # Kill tails to allow monitor to exit cleanly
        [ -n "${TAIL_D:-}" ] && kill "$TAIL_D" 2>/dev/null || true
        [ -n "${TAIL_S:-}" ] && kill "$TAIL_S" 2>/dev/null || true
        [ -n "${TAIL_DIR:-}" ] && kill "$TAIL_DIR" 2>/dev/null || true
        # Clear anchored status line with final state
        printf '\033[s\033[999B\033[2K\r%s\033[u' "[SYSTEM] swarm offline -- monitor exiting" >&2
        break
      fi

      sleep "${CHECK_INTERVAL:-5}"
    done
  }
  refresh_status_loop & STATUS_PID=$!

  # Wait on background tails; trap will handle cleanup on INT/TERM
  wait

  # Ensure status refresher is stopped when tails exit
  [ -n "${STATUS_PID:-}" ] && kill "$STATUS_PID" 2>/dev/null || true

}

case "${1:-}" in
  start)
    if [ -f "$SUP_PIDFILE" ] && is_pid_for_script "$(cat "$SUP_PIDFILE")" "$SCRIPT_DIR/lib/supervise.sh"; then
      printf 'Supervisor already running (PID %s)\n' "$(cat "$SUP_PIDFILE")" >&2
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
    # Count worker processes (case-insensitive match on 'worker' in process args)
    WORKER_COUNT=0
    if command -v ps_fallback >/dev/null 2>&1; then
      WORKER_PIDS="$(ps_fallback pid,args 2>/dev/null | awk 'tolower($0) ~ /worker/ {print $1}' | sort -u)"
    else
      WORKER_PIDS="$(ps -eo pid,args 2>/dev/null | awk 'tolower($0) ~ /worker/ {print $1}' | sort -u)"
    fi
    for wp in $WORKER_PIDS; do
      if [ -n "$wp" ] && kill -0 "$wp" 2>/dev/null; then
        WORKER_COUNT=$((WORKER_COUNT+1))
      fi
    done
    if [ "$WORKER_COUNT" -gt 0 ]; then
      echo "Workers running ($WORKER_COUNT)"
    else
      echo "Workers not running"
    fi
    if [ "$MONITOR" -eq 1 ]; then
      monitor_foreground
    fi
    ;;



  *)
    usage
    ;;
esac