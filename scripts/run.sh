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
Usage: sh scripts/run.sh [--monitor] [--yolo] <command>

Commands:
  start           Start the supervisor (background).
  stop            Stop supervisor and daemon.
  status          Print supervisor and daemon status.

Options:
  --monitor, -m   After running the command, enter monitor foreground mode (runs in foreground).
  --logs          When used with --monitor, also stream daemon and supervisor logs into the monitor.
  --yolo          Force YOLO mode for supervisor, daemon, and any spawned workers (exports YOLO=true).

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

# Parse optional --monitor and --yolo flags anywhere in args and rebuild positional params without them
MONITOR=0
YOLO_FORCE=0
for a in "$@"; do
  if [ "$a" = "--monitor" ] || [ "$a" = "-m" ]; then
    MONITOR=1
  fi
  if [ "$a" = "--yolo" ]; then
    YOLO_FORCE=1
  fi
done

REMAINING=""
while [ $# -gt 0 ]; do
  case "$1" in
    --monitor|-m)
      shift;;
    --yolo)
      shift;;
    --logs)
      STREAM_LOGS=1
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

# If run.sh was invoked with --yolo, force YOLO mode for this process and export to children
if [ "${YOLO_FORCE:-0}" -eq 1 ]; then
  YOLO=true
  export YOLO
fi

cleanup_and_exit() {
  echo "Caught interrupt; shutting down supervisor and daemon..." >&2

  # Kill any tails streaming logs
  [ -n "${TAIL_D:-}" ] && kill "$TAIL_D" 2>/dev/null || true
  [ -n "${TAIL_S:-}" ] && kill "$TAIL_S" 2>/dev/null || true
  [ -n "${TAIL_DIR:-}" ] && kill "$TAIL_DIR" 2>/dev/null || true
  [ -n "${STATUS_PID:-}" ] && kill "$STATUS_PID" 2>/dev/null || true
  [ -n "${INPUT_PID:-}" ] && kill "$INPUT_PID" 2>/dev/null || true

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

# Handle interactive commands entered in monitor mode
handle_command() {
  # Called by the input loop; safely interpret simple commands
  cmdline="$1"
  cmd="$(printf '%s' "$cmdline" | awk '{print $1}')"
  arg="$(printf '%s' "$cmdline" | awk '{print $2}')"
  printf '%s [INPUT] %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$cmdline" >&2
  case "$cmd" in
    help|\?)
      echo "Commands: ?, help, kill <id|name|agent:name>, ping <id|name>, list, select <n>, focus <cmd|tree>" >&2
      ;;
    kill)
      if [ -z "$arg" ]; then echo "Usage: kill <id|name|agent:name>" >&2; return 0; fi
      if printf '%s' "$arg" | grep -qE '^[0-9]+$'; then
        pid="$arg"
        if kill -0 "$pid" 2>/dev/null; then
          kill_pid_and_children "$pid"
          echo "Killed pid $pid" >&2
        else
          echo "Pid $pid not running" >&2
        fi
      else
        # If registered name
        if [ -f "$RUN_DIR/$arg.pid" ]; then
          if proc_stop_registered "$arg"; then
            echo "Stopped registered $arg" >&2
          else
            echo "Failed to stop $arg" >&2
          fi
        else
          # search by name (case-insensitive)
          pids=$(ps -eo pid,args 2>/dev/null | awk -v n="$arg" 'tolower($0) ~ tolower(n) {print $1}')
          if [ -z "$pids" ]; then
            echo "No process found matching $arg" >&2
          else
            for pid in $pids; do
              kill_pid_and_children "$pid" && echo "Killed $pid for $arg" >&2 || echo "Failed to kill $pid" >&2
            done
          fi
        fi
      fi
      ;;
    ping)
      if [ -z "$arg" ]; then echo "Usage: ping <id|name|agent:name>" >&2; return 0; fi
      if printf '%s' "$arg" | grep -qE '^[0-9]+$'; then
        pid="$arg"
        if kill -0 "$pid" 2>/dev/null; then
          echo "pong pid $pid" >&2
        else
          echo "no response from pid $pid" >&2
        fi
      else
        if [ -f "$RUN_DIR/$arg.pid" ]; then
          pid=$(cat "$RUN_DIR/$arg.pid" 2>/dev/null || echo "")
          if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "pong $arg pid $pid" >&2
          else
            echo "$arg (pid:$pid) not responding" >&2
          fi
        else
          pids=$(ps -eo pid,args 2>/dev/null | awk -v n="$arg" 'tolower($0) ~ tolower(n) {print $1}')
          if [ -z "$pids" ]; then
            echo "no process found matching $arg" >&2
          else
            for pid in $pids; do
              echo "pong $pid" >&2
            done
          fi
        fi
      fi
      ;;
    list)
      proc_list_registered | while read -r nm pid; do
        [ -z "$nm" ] && continue
        if [ -n "$pid" ] && proc_is_running "$pid"; then st='running'; else st='stopped'; fi
        echo "$nm $pid $st" >&2
      done
      ;;
    select)
      if printf '%s' "$arg" | grep -qE '^[0-9]+$'; then
        printf '%s' "$arg" > "$RUN_DIR/monitor_selected"
      else
        echo "select <n> (numeric)" >&2
      fi
      ;;
    focus)
      if [ "$arg" = "cmd" ] || [ "$arg" = "tree" ]; then
        printf '%s' "$arg" > "$RUN_DIR/monitor_focus"
      else
        echo "focus cmd|tree" >&2
      fi
      ;;
    *)
      echo "Unknown command: $cmdline" >&2
      ;;
  esac
}

# Input loop: reads single characters and updates shared monitor files under RUN_DIR
input_loop() {
  # Run in a subshell safe loop
  set +e
  OLDSTTY="$(stty -g 2>/dev/null || true)"
  # enable char-at-a-time, no echo
  stty -echo -icanon time 0 min 0 2>/dev/null || true

  focus_file="$RUN_DIR/monitor_focus"
  sel_file="$RUN_DIR/monitor_selected"
  buf_file="$RUN_DIR/monitor_input_buf"
  tree_count_file="$RUN_DIR/monitor_tree_count"

  printf 'cmd' > "$focus_file"
  printf '1' > "$sel_file"
  printf '' > "$buf_file"
  printf '0' > "$tree_count_file"

  ESC="$(printf '\033')"
  UP="$ESC[A"
  DOWN="$ESC[B"
  TAB="$(printf '\t')"
  DEL="$(printf '\177')"
  NL="$(printf '\n')"

  while :; do
    # read one byte (non-blocking due to stty settings)
    c="$(dd bs=1 count=1 2>/dev/null || true)"
    if [ -z "$c" ]; then
      sleep 0.05
      continue
    fi

    if [ "$c" = "$ESC" ]; then
      # attempt to read two more bytes for arrow sequences
      c2="$(dd bs=1 count=1 2>/dev/null || true)"
      c3="$(dd bs=1 count=1 2>/dev/null || true)"
      seq="$c$c2$c3"
      if [ "$seq" = "$UP" ]; then
        focus="$(cat "$focus_file" 2>/dev/null || echo cmd)"
        if [ "$focus" = "tree" ]; then
          sel="$(cat "$sel_file" 2>/dev/null || echo 1)"
          if [ "$sel" -gt 1 ]; then sel=$((sel-1)); fi
          printf '%s' "$sel" > "$sel_file"
        fi
      elif [ "$seq" = "$DOWN" ]; then
        focus="$(cat "$focus_file" 2>/dev/null || echo cmd)"
        if [ "$focus" = "tree" ]; then
          sel="$(cat "$sel_file" 2>/dev/null || echo 1)"
          max="$(cat "$tree_count_file" 2>/dev/null || echo 0)"
          if [ "$sel" -lt "$max" ]; then sel=$((sel+1)); fi
          printf '%s' "$sel" > "$sel_file"
        fi
      fi
      continue
    fi

    if [ "$c" = "$TAB" ]; then
      focus="$(cat "$focus_file" 2>/dev/null || echo cmd)"
      if [ "$focus" = "cmd" ]; then printf 'tree' > "$focus_file"; else printf 'cmd' > "$focus_file"; fi
      continue
    fi

    if [ "$c" = "$NL" ]; then
      # Enter: read buffer and handle command
      cmdline="$(cat "$buf_file" 2>/dev/null || echo '')"
      if [ -n "$cmdline" ]; then
        handle_command "$cmdline"
      fi
      # clear buffer
      printf '' > "$buf_file"
      continue
    fi

    if [ "$c" = "$DEL" ]; then
      buf="$(cat "$buf_file" 2>/dev/null || echo '')"
      # remove last char
      buf="${buf%?}"
      printf '%s' "$buf" > "$buf_file"
      continue
    fi

    # Append character to buffer
    printf '%s' "$c" >> "$buf_file"
  done

  # restore terminal
  stty "$OLDSTTY" 2>/dev/null || true
}

monitor_foreground() {
  printf 'Monitor: live swarm status (press Ctrl-C to exit)\n' >&2
  touch "$LOGFILE" "$SUP_LOGFILE" "$DIRECTOR_LOG"

  # Ensure Ctrl-C triggers clean shutdown of supervisor and daemon
  trap 'cleanup_and_exit' INT TERM

  # ANSI color codes when writing to a terminal
  if [ -t 2 ]; then
    RED='\033[31m'
    GREEN='\033[32m'
    YELLOW='\033[33m'
    RESET='\033[0m'
    INV='\033[7m'
  else
    RED=''
    GREEN=''
    YELLOW=''
    RESET=''
    INV=''
  fi

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

  # Do not stream logs by default; monitor displays live swarm status only
  STREAM_LOGS="${STREAM_LOGS:-0}"
  if [ "${STREAM_LOGS}" -eq 1 ]; then
    tail -n 0 -F "$LOGFILE" 2>/dev/null &
    TAIL_D=$!
    tail -n 0 -F "$SUP_LOGFILE" 2>/dev/null | sed '/\[SUPERVISOR\]/! s/^/[SUPERVISOR] /' &
    TAIL_S=$!
    tail -n 0 -F "$DIRECTOR_LOG" 2>/dev/null &
    TAIL_DIR=$!
  else
    TAIL_D=""
    TAIL_S=""
    TAIL_DIR=""
  fi

  # Start interactive input loop for monitor (reads single-key input and manages focus)
  input_loop &
  INPUT_PID=$!

  # Background refresher to update an anchored status line with uptime/errors/swarm state
  monitor_start_ts=$(date +%s)
  MONITOR_INTERVAL="${MONITOR_INTERVAL:-5}"
  # Record whether monitor started while swarm was active; only auto-exit if it was
  INITIAL_ACTIVE=0
  if [ "$SWARM_STATUS" != "swarm offline" ]; then
    INITIAL_ACTIVE=1
  fi
  LAST_SWARM_STATUS="$SWARM_STATUS"
  LAST_STATUS_LINE=""
  LAST_LOG_MTIME=""
  LAST_ERROR_COUNT=0

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

      # Error count from logs: recompute only when logs change (by mtime)
      mt1=$(stat -c %Y "$LOGFILE" 2>/dev/null || echo 0)
      mt2=$(stat -c %Y "$SUP_LOGFILE" 2>/dev/null || echo 0)
      mt3=$(stat -c %Y "$DIRECTOR_LOG" 2>/dev/null || echo 0)
      mt_combined="$mt1:$mt2:$mt3"
      if [ "$mt_combined" != "$LAST_LOG_MTIME" ]; then
        ERRORS=$(grep -i -E "error|failed|exception" "$LOGFILE" "$SUP_LOGFILE" "$DIRECTOR_LOG" 2>/dev/null | wc -l || true)
        LAST_LOG_MTIME="$mt_combined"
        LAST_ERROR_COUNT="$ERRORS"
      else
        ERRORS="$LAST_ERROR_COUNT"
      fi

      # Gather process list once per iteration for efficiency
      if command -v ps_fallback >/dev/null 2>&1; then
        PS_OUT=$(ps_fallback pid,args 2>/dev/null || true)
      else
        PS_OUT=$(ps -eo pid,args 2>/dev/null || true)
      fi

      # Worker count
      WORKER_COUNT=0
      WORKER_PIDS=$(printf '%s\n' "$PS_OUT" | awk 'tolower($0) ~ /worker/ {print $1}' | sort -u || true)
      for wp in $WORKER_PIDS; do
        if [ -n "$wp" ] && kill -0 "$wp" 2>/dev/null; then
          WORKER_COUNT=$((WORKER_COUNT+1))
        fi
      done

      # Supervisor and daemon checks (prefer pidfiles)
      SUP_ALIVE=0
      if [ -f "$SUP_PIDFILE" ]; then
        SUPPID=$(cat "$SUP_PIDFILE" 2>/dev/null || true)
        if [ -n "$SUPPID" ] && kill -0 "$SUPPID" 2>/dev/null; then
          SUP_ALIVE=1
        fi
      fi
      DAEMON_ALIVE=0
      if [ -f "$DAEMON_PIDFILE" ]; then
        DPID=$(cat "$DAEMON_PIDFILE" 2>/dev/null || true)
        if [ -n "$DPID" ] && kill -0 "$DPID" 2>/dev/null; then
          DAEMON_ALIVE=1
        fi
      fi

      if [ "$WORKER_COUNT" -gt 0 ] || [ "$SUP_ALIVE" -eq 1 ] || [ "$DAEMON_ALIVE" -eq 1 ]; then
        SWARM_STATUS="swarm running ($WORKER_COUNT workers)"
      else
        SWARM_STATUS="swarm offline"
      fi

      # Emit event line on status transitions
      if [ "$SWARM_STATUS" != "$LAST_SWARM_STATUS" ]; then
        if [ "$SWARM_STATUS" = "swarm offline" ]; then
          printf '%s [SYSTEM] swarm went offline\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >&2
        else
          printf '%s [SYSTEM] swarm is now running (%d workers)\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$WORKER_COUNT" >&2
        fi
        LAST_SWARM_STATUS="$SWARM_STATUS"
      fi

      status_line="[SYSTEM] Uptime: $uptime_fmt | errors: $ERRORS | $SWARM_STATUS"
      # Build a tree of registered workers and display it above the anchored status line
      tree_tmp="$(mktemp "/tmp/swarm_tree_XXXXXX" 2>/dev/null || echo "/tmp/swarm_tree_$$")"
      : > "$tree_tmp"

      if command -v proc_list_registered >/dev/null 2>&1; then
        proc_list_registered | while read -r nm pid; do
          [ -z "$nm" ] && continue
          ln=$(printf '%s' "$nm" | tr 'A-Z' 'a-z')
          icon='*'
          case "$ln" in
            *director*) icon='D' ;;
            *daemon*) icon='M' ;;
            *supervisor*|*supervise*) icon='S' ;;
            *worker*) icon='W' ;;
            *agent*) icon='A' ;;
            *container*|*docker*) icon='C' ;;
          esac

          status_plain="stopped"
          status_col="$YELLOW"
          if [ -n "$pid" ] && proc_is_running "$pid"; then
            status_plain="running"
            status_col="$GREEN"
          else
            if [ -f "$LOG_DIR/${nm}.log" ] && grep -i -E "error|failed|exception" "$LOG_DIR/${nm}.log" >/dev/null 2>&1; then
              status_plain="error"
              status_col="$RED"
            fi
          fi

          printf '%s %s (pid:%s) %s\n' "[$icon]" "$nm" "$pid" "${status_col}${status_plain}${RESET}" >> "$tree_tmp"
        done
      else
        if command -v ps_fallback >/dev/null 2>&1; then
          PS_OUT=$(ps_fallback pid,args 2>/dev/null || true)
        else
          PS_OUT=$(ps -eo pid,args 2>/dev/null || true)
        fi
        printf '%s\n' "$PS_OUT" | awk 'tolower($0) ~ /worker/ {print $1" "substr($0,index($0,$2))}' | while read -r pid args; do
          nm="worker-${pid}"
          icon='W'
          status_plain="running"
          status_col="$GREEN"
          if ! kill -0 "$pid" 2>/dev/null; then
            status_plain="stopped"
            status_col="$YELLOW"
          fi
          printf '%s %s (pid:%s) %s\n' "[$icon]" "$nm" "$pid" "${status_col}${status_plain}${RESET}" >> "$tree_tmp"
        done
      fi

      tree_count=$(wc -l <"$tree_tmp" 2>/dev/null || echo 0)
      # publish tree count for input loop to read
      printf '%s' "$tree_count" > "$RUN_DIR/monitor_tree_count" 2>/dev/null || true
      if [ "$tree_count" -eq 0 ]; then
        # Only redraw anchored status when it changes to reduce flicker
        if [ "${status_line}" != "${LAST_STATUS_LINE}" ]; then
          # when no tree, print status and leave
          printf '\033[s\033[999B\033[2K\r%s\033[u' "$status_line" >&2
          LAST_STATUS_LINE="$status_line"
        fi
      else
        # Only redraw when status or tree count changes
        if [ "${status_line}" != "${LAST_STATUS_LINE}" ] || [ "$tree_count" != "${LAST_TREE_COUNT:-}" ]; then
          # move to bottom and up by (tree_count+1) lines to leave room for an input prompt
          printf '\033[s\033[999B' >&2
          move_up=$((tree_count + 1))
          if [ "$move_up" -gt 0 ]; then
            printf '\033[%dA' "$move_up" >&2
          fi

          # read selection, focus, and buffer
          SEL="$(cat "$RUN_DIR/monitor_selected" 2>/dev/null || echo 1)"
          FOCUS="$(cat "$RUN_DIR/monitor_focus" 2>/dev/null || echo cmd)"
          BUF="$(cat "$RUN_DIR/monitor_input_buf" 2>/dev/null || echo '')"

          n=0
          total=$(wc -l <"$tree_tmp" 2>/dev/null || echo 0)
          while IFS= read -r l; do
            n=$((n+1))
            if [ "$n" -lt "$total" ]; then
              prefix='|- '
            else
              prefix='`- '
            fi
            if [ "$n" -eq "$SEL" ]; then
              sel_prefix='> '
              if [ "$FOCUS" = "tree" ]; then
                # invert colors for focused selection
                printf '\033[2K\r%s%s%s%s\033[0m\n' "$prefix" "$sel_prefix" "$INV" "$l" >&2
              else
                printf '\033[2K\r%s%s%s\n' "$prefix" "$sel_prefix" "$l" >&2
              fi
            else
              printf '\033[2K\r%s%s\n' "$prefix" "$l" >&2
            fi
          done < "$tree_tmp"

          # print input prompt line above the anchored status
          if [ "$FOCUS" = "cmd" ]; then
            prompt="(cmd) > $BUF"
          else
            prompt="(tree) > $BUF"
          fi
          printf '\033[2K\r%s\n' "$prompt" >&2

          # print final status line (no newline) and restore cursor
          printf '\033[2K\r%s\033[u' "$status_line" >&2
          LAST_STATUS_LINE="$status_line"
          LAST_TREE_COUNT="$tree_count"
        fi
      fi
      rm -f "$tree_tmp" 2>/dev/null || true

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

      # If any of the tail processes exit unexpectedly, log and exit so callers don't hang
      if [ -n "${TAIL_D:-}" ] && ! kill -0 "$TAIL_D" 2>/dev/null; then
        printf '%s [SYSTEM] daemon log tail stopped; exiting monitor\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >&2
        break
      fi
      if [ -n "${TAIL_S:-}" ] && ! kill -0 "$TAIL_S" 2>/dev/null; then
        printf '%s [SYSTEM] supervisor log tail stopped; exiting monitor\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >&2
        break
      fi
      if [ -n "${TAIL_DIR:-}" ] && ! kill -0 "$TAIL_DIR" 2>/dev/null; then
        printf '%s [SYSTEM] director log tail stopped; exiting monitor\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >&2
        break
      fi

      sleep "$MONITOR_INTERVAL"
    done
  }
  refresh_status_loop & STATUS_PID=$!

  # Wait on background tails; trap will handle cleanup on INT/TERM
  wait

  # Ensure status refresher is stopped when tails exit
  [ -n "${STATUS_PID:-}" ] && kill "$STATUS_PID" 2>/dev/null || true
  [ -n "${INPUT_PID:-}" ] && kill "$INPUT_PID" 2>/dev/null || true

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