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

  # Attempt to restore terminal state
  stty sane 2>/dev/null || true

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

    # Kill any orphaned worker processes under this repo
    PIDS="$(ps_fallback pid,args | awk 'tolower($0) ~ /worker/ {print $1}')"
    if [ -n "$PIDS" ]; then
      for p in $PIDS; do
        if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
          echo "Killing orphaned worker process PID $p" >&2
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
        # also focus tree for interactive navigation
        printf 'tree' > "$RUN_DIR/monitor_focus"
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
  # Run in main shell so stty changes affect the controlling terminal
  set +e
  OLDSTTY="$(stty -g 2>/dev/null || true)"
  # enable char-at-a-time, no echo; block until at least 1 byte
  stty -echo -icanon min 1 time 0 2>/dev/null || true

  focus_file="$RUN_DIR/monitor_focus"
  sel_file="$RUN_DIR/monitor_selected"
  buf_file="$RUN_DIR/monitor_input_buf"
  tree_count_file="$RUN_DIR/monitor_tree_count"

  printf 'cmd' > "$focus_file"
  printf '1' > "$sel_file"
  printf '' > "$buf_file"
  printf '0' > "$tree_count_file"

  ESC="$(printf '\\033')"
  UP="$ESC[A"
  DOWN="$ESC[B"
  TAB="$(printf '\\t')"
  DEL="$(printf '\\177')"
  NL="$(printf '\\n')"
  CR="$(printf '\\r')"

  while :; do
    # determine controlling terminal to read from (fallback to stdin)
    if [ -t 0 ]; then TTY="/dev/tty"; else TTY="/dev/stdin"; fi

    # detect if current shell supports 'read -n' for single-char reads (portable fallback to dd otherwise)
    if [ -z "${READ_CAN_N:-}" ]; then
      if sh -c 'printf x | { read -r -n1 c 2>/dev/null && exit 0 || exit 1; }' 2>/dev/null; then
        READ_CAN_N=1
      else
        READ_CAN_N=0
      fi
    fi

    # read one byte (blocking until input available) from the controlling terminal
    if [ "${READ_CAN_N:-0}" -eq 1 ]; then
      # use shell builtin read when available to better handle interactive input
      IFS= read -r -n1 c < "$TTY" 2>/dev/null || c=''
    else
      c="$(dd bs=1 count=1 2>/dev/null < "$TTY" || true)"
    fi

    if [ -z "$c" ]; then
      continue
    fi

    if [ "$c" = "$ESC" ]; then
      # read next bytes for escape sequences (supports longer sequences like ESC[1;5A)
      if [ "${READ_CAN_N:-0}" -eq 1 ]; then
        # read first two bytes to avoid blocking for long sequences
        IFS= read -r -n2 seq_tail < "$TTY" 2>/dev/null || seq_tail=''
        # attempt to read any remaining bytes quickly (non-blocking short timeout)
        # accumulate up to 5 extra bytes; safe if read -t unsupported (it will just fail fast)
        for i in 1 2 3 4 5; do
          if IFS= read -r -t 0.01 -n1 ch < "$TTY" 2>/dev/null; then
            seq_tail="$seq_tail$ch"
          else
            break
          fi
        done
      else
        # fallback: read a few bytes (may block until bytes available)
        seq_tail="$(dd bs=1 count=3 2>/dev/null < "$TTY" || true)"
      fi
      seq="$c$seq_tail"
      # determine final byte to detect arrow direction (handles sequences like ESC[A, ESC[1;5A, ESCOA)
      last_ch="$(printf '%s' "$seq" | tail -c 1 2>/dev/null || true)"

      # Only adjust selection when tree has focus; clamp sel against tree_count for robust behavior
      focus="$(cat "$focus_file" 2>/dev/null || echo cmd)"
      if [ "$focus" = "tree" ]; then
        sel="$(cat "$sel_file" 2>/dev/null || echo 1)"
        max="$(cat "$tree_count_file" 2>/dev/null || echo 0)"
        # sanitize numeric values
        case "$sel" in ''|*[!0-9]*) sel=1 ;; esac
        case "$max" in ''|*[!0-9]*) max=0 ;; esac
        # clamp sel to max when possible
        if [ "$max" -gt 0 ] && [ "$sel" -gt "$max" ]; then sel="$max"; fi

        if [ "$last_ch" = 'A' ] || [ "$last_ch" = 'a' ]; then
          if [ "$sel" -gt 1 ]; then
            sel=$((sel-1))
          else
            sel=1
          fi
        elif [ "$last_ch" = 'B' ] || [ "$last_ch" = 'b' ]; then
          if [ "$max" -gt 0 ] && [ "$sel" -lt "$max" ]; then
            sel=$((sel+1))
          fi
        fi
        printf '%s' "$sel" > "$sel_file"
      fi
      continue
    fi

    # support j/k as up/down navigation in tree focus as a fallback for terminals where arrow keys are unreliable
    if [ "$c" = 'k' ] || [ "$c" = 'K' ]; then
      focus="$(cat "$focus_file" 2>/dev/null || echo cmd)"
      if [ "$focus" = "tree" ]; then
        sel="$(cat "$sel_file" 2>/dev/null || echo 1)"
        case "$sel" in ''|*[!0-9]*) sel=1 ;; esac
        if [ "$sel" -gt 1 ]; then sel=$((sel-1)); fi
        printf '%s' "$sel" > "$sel_file"
        continue
      fi
    fi
    if [ "$c" = 'j' ] || [ "$c" = 'J' ]; then
      focus="$(cat "$focus_file" 2>/dev/null || echo cmd)"
      if [ "$focus" = "tree" ]; then
        sel="$(cat "$sel_file" 2>/dev/null || echo 1)"
        max="$(cat "$tree_count_file" 2>/dev/null || echo 0)"
        case "$sel" in ''|*[!0-9]*) sel=1 ;; esac
        case "$max" in ''|*[!0-9]*) max=0 ;; esac
        if [ "$max" -gt 0 ] && [ "$sel" -lt "$max" ]; then sel=$((sel+1)); fi
        printf '%s' "$sel" > "$sel_file"
        continue
      fi
    fi

    if [ "$c" = "$TAB" ]; then
      focus="$(cat "$focus_file" 2>/dev/null || echo cmd)"
      if [ "$focus" = "cmd" ]; then printf 'tree' > "$focus_file"; else printf 'cmd' > "$focus_file"; fi
      continue
    fi

    if [ "$c" = "$NL" ] || [ "$c" = "$CR" ]; then
      # Enter: read buffer, strip CRs, and handle command (capture stderr to monitor_last_msg)
      cmdline="$(cat "$buf_file" 2>/dev/null || echo '')"
      # strip any stray CRs
      cmdline="$(printf '%s' "$cmdline" | tr -d '\\r')"
      if [ -n "$cmdline" ]; then
        handle_command "$cmdline" 2> "$RUN_DIR/monitor_last_msg" || true
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
    # If a Tab ended up in the buffer as first char (some terminals/pipes), treat it as a focus toggle and strip it
    first="$(head -c 1 "$buf_file" 2>/dev/null || true)"
    if [ -n "$first" ] && [ "$first" = "$TAB" ]; then
      focus="$(cat "$focus_file" 2>/dev/null || echo cmd)"
      if [ "$focus" = "cmd" ]; then printf 'tree' > "$focus_file"; else printf 'cmd' > "$focus_file"; fi
      # remove first character from buffer
      rest="$(tail -c +2 "$buf_file" 2>/dev/null || true)"
      printf '%s' "$rest" > "$buf_file"
    fi
  done

  # restore terminal
  stty "$OLDSTTY" 2>/dev/null || true
}

monitor_foreground() {
  printf '\033[H\033[2J' >&2
  printf 'Monitor: live swarm status (press Ctrl-C to exit)\n' >&2
  touch "$LOGFILE" "$SUP_LOGFILE" "$DIRECTOR_LOG"

  # Ensure Ctrl-C triggers clean shutdown of supervisor and daemon
  trap 'cleanup_and_exit' INT TERM

  # ANSI color codes when writing to a terminal
  if [ -t 2 ]; then
    ESC="$(printf '\033')"
    RED="${ESC}[31m"
    GREEN="${ESC}[32m"
    YELLOW="${ESC}[33m"
    RESET="${ESC}[0m"
    INV="${ESC}[7m"
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

  if [ "$WORKER_COUNT" -gt 0 ] || ([ -f "$SUP_PIDFILE" ] && kill -0 "$(cat "$SUP_PIDFILE")" 2>/dev/null); then
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
  # If no swarm nodes are online, show zero uptime to emphasize swarm offline state
  if [ "$SWARM_STATUS" = "swarm offline" ]; then
    UPTIME_FMT="0:00:00"
  fi

  printf '%s [SYSTEM] Supervisor: %s | Daemon: %s | Uptime: %s | %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$SUP_RUNNING" "$DAEMON_RUNNING" "$UPTIME_FMT" "$SWARM_STATUS" >&2

  # By default, monitor-only mode should not spawn extra processes; require --logs to stream tails
  STREAM_LOGS="${STREAM_LOGS:-0}"
  if [ "${STREAM_LOGS}" -eq 1 ]; then
    LOG_TAIL_FILE="$RUN_DIR/monitor_tail_daemon"
    SUP_TAIL_FILE="$RUN_DIR/monitor_tail_supervisor"
    DIR_TAIL_FILE="$RUN_DIR/monitor_tail_director"
    :> "$LOG_TAIL_FILE" 2>/dev/null || true
    :> "$SUP_TAIL_FILE" 2>/dev/null || true
    :> "$DIR_TAIL_FILE" 2>/dev/null || true
    # write tail output into files; refresher will render them to the controlled layout
    tail -n 10 -F "$LOGFILE" 2>/dev/null >>"$LOG_TAIL_FILE" &
    TAIL_D=$!
    tail -n 10 -F "$SUP_LOGFILE" 2>/dev/null | sed '/\[SUPERVISOR\]/! s/^/[SUPERVISOR] /' >>"$SUP_TAIL_FILE" &
    TAIL_S=$!
    tail -n 10 -F "$DIRECTOR_LOG" 2>/dev/null >>"$DIR_TAIL_FILE" &
    TAIL_DIR=$!
  else
    LOG_TAIL_FILE=""
    SUP_TAIL_FILE=""
    DIR_TAIL_FILE=""
    TAIL_D=""
    TAIL_S=""
    TAIL_DIR=""
  fi

  # Start interactive input loop for monitor (reads single-key input and manages focus)
  # input_loop will be launched in the foreground after the refresher is started

  # Background refresher to update an anchored status line with uptime/errors/swarm state
  monitor_start_ts=$(date +%s)
  MONITOR_INTERVAL="${MONITOR_INTERVAL:-0.12}"
  # Record whether monitor started while swarm was active; only auto-exit if it was
  INITIAL_ACTIVE=0
  if [ "$SWARM_STATUS" != "swarm offline" ]; then
    INITIAL_ACTIVE=1
  fi
  LAST_SWARM_STATUS="$SWARM_STATUS"
  LAST_STATUS_LINE=""
  LAST_LOG_MTIME=""
  LAST_ERROR_COUNT=0
  CURSOR_TOG=1
  LAST_SEL=""
  LAST_FOCUS=""
  LAST_BUF=""
  LAST_CURSOR_TOG="${CURSOR_TOG:-1}"

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
      # If swarm is offline, force displayed uptime to zero
      if [ "$SWARM_STATUS" = "swarm offline" ]; then
        uptime_fmt="0:00:00"
      fi

      # Emit event line on status transitions
      if [ "$SWARM_STATUS" != "$LAST_SWARM_STATUS" ]; then
        if [ "${STREAM_LOGS:-0}" -eq 1 ]; then
          if [ "$SWARM_STATUS" = "swarm offline" ]; then
            printf '%s [SYSTEM] swarm went offline\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >&2
          else
            printf '%s [SYSTEM] swarm is now running (%d workers)\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$WORKER_COUNT" >&2
          fi
        fi
        LAST_SWARM_STATUS="$SWARM_STATUS"
      fi

      status_line="[SYSTEM] Uptime: $uptime_fmt | errors: $ERRORS | $SWARM_STATUS"
      # Build a hierarchical tree of swarm components and display it above the anchored status line
      tree_tmp="$(mktemp "/tmp/swarm_tree_XXXXXX" 2>/dev/null || echo "/tmp/swarm_tree_$$")"
      : > "$tree_tmp"

      if command -v proc_list_registered >/dev/null 2>&1; then
        regtmp="$(mktemp "/tmp/rv_reg_XXXXXX" 2>/dev/null || echo "/tmp/rv_reg_$$")"
        proc_list_registered > "$regtmp" 2>/dev/null || true

        # Root header
        printf '%s\n' "[v] v-daemon | $SWARM_STATUS | uptime: $uptime_fmt" >> "$tree_tmp"

        # Supervisor entry
        if grep -i -q -E 'supervisor|supervise' "$regtmp" 2>/dev/null; then
          grep -i -E 'supervisor|supervise' "$regtmp" 2>/dev/null | while read -r nm pid; do
            [ -z "$nm" ] && continue
            status_plain="stopped"; status_col="$YELLOW"
            if [ -n "$pid" ] && proc_is_running "$pid"; then
              status_plain="running"; status_col="$GREEN"
            else
              if [ -f "$LOG_DIR/${nm}.log" ] && grep -i -E "error|failed|exception" "$LOG_DIR/${nm}.log" >/dev/null 2>&1; then
                status_plain="error"; status_col="$RED"
              fi
            fi
            printf '%s\n' "  [S] $nm (pid:${pid:-}) ${status_col}${status_plain}${RESET}" >> "$tree_tmp"
          done
        else
          sup_pid=""
          [ -f "$SUP_PIDFILE" ] && sup_pid="$(cat "$SUP_PIDFILE" 2>/dev/null || true)"
          if [ -n "$sup_pid" ] && kill -0 "$sup_pid" 2>/dev/null; then status_plain="running"; status_col="$GREEN"; else status_plain="stopped"; status_col="$YELLOW"; fi
          printf '%s\n' "  [S] supervisor (pid:${sup_pid:-}) ${status_col}${status_plain}${RESET}" >> "$tree_tmp"
        fi

        # Daemon entry
        if grep -i -q -E '(^| )daemon($| )|v-daemon' "$regtmp" 2>/dev/null; then
          grep -i -E '(^| )daemon($| )|v-daemon' "$regtmp" 2>/dev/null | while read -r nm pid; do
            [ -z "$nm" ] && continue
            status_plain="stopped"; status_col="$YELLOW"
            if [ -n "$pid" ] && proc_is_running "$pid"; then status_plain="running"; status_col="$GREEN"; else
              if [ -f "$LOG_DIR/${nm}.log" ] && grep -i -E "error|failed|exception" "$LOG_DIR/${nm}.log" >/dev/null 2>&1; then
                status_plain="error"; status_col="$RED"
              fi
            fi
            printf '%s\n' "  [M] $nm (pid:${pid:-}) ${status_col}${status_plain}${RESET}" >> "$tree_tmp"
          done
        else
          dm_pid=""
          [ -f "$DAEMON_PIDFILE" ] && dm_pid="$(cat "$DAEMON_PIDFILE" 2>/dev/null || true)"
          if [ -n "$dm_pid" ] && kill -0 "$dm_pid" 2>/dev/null; then status_plain="running"; status_col="$GREEN"; else status_plain="stopped"; status_col="$YELLOW"; fi
          printf '%s\n' "  [M] daemon (pid:${dm_pid:-}) ${status_col}${status_plain}${RESET}" >> "$tree_tmp"
        fi

        # Director entry
        if grep -i -q 'director' "$regtmp" 2>/dev/null; then
          grep -i 'director' "$regtmp" 2>/dev/null | while read -r nm pid; do
            [ -z "$nm" ] && continue
            status_plain="stopped"; status_col="$YELLOW"
            if [ -n "$pid" ] && proc_is_running "$pid"; then
              status_plain="running"; status_col="$GREEN"
            else
              # check for recent errors in director logs
              if [ -f "$LOG_DIR/${nm}.log" ] && grep -i -E "error|failed|exception" "$LOG_DIR/${nm}.log" >/dev/null 2>&1; then
                status_plain="error"; status_col="$RED"
              elif [ -f "$DIRECTOR_LOG" ] && grep -i -E "error|failed|exception" "$DIRECTOR_LOG" >/dev/null 2>&1; then
                status_plain="error"; status_col="$RED"
              fi
            fi
            printf '%s\n' "  [D] $nm (pid:${pid:-}) ${status_col}${status_plain}${RESET}" >> "$tree_tmp"
          done
        else
          dir_pid=""
          [ -f "$DIRECTOR_PIDFILE" ] && dir_pid="$(cat "$DIRECTOR_PIDFILE" 2>/dev/null || true)"
          if [ -n "$dir_pid" ] && kill -0 "$dir_pid" 2>/dev/null; then
            status_plain="running"; status_col="$GREEN"
          else
            status_plain="stopped"; status_col="$YELLOW"
            if [ -f "$DIRECTOR_LOG" ] && grep -i -E "error|failed|exception" "$DIRECTOR_LOG" >/dev/null 2>&1; then
              status_plain="error"; status_col="$RED"
            fi
          fi
          printf '%s\n' "  [D] director (pid:${dir_pid:-}) ${status_col}${status_plain}${RESET}" >> "$tree_tmp"
        fi

        # Workers group
        if grep -i -q 'worker' "$regtmp" 2>/dev/null; then
          printf '%s\n' "  workers/" >> "$tree_tmp"
          grep -i 'worker' "$regtmp" 2>/dev/null | while read -r wnm wpid; do
            [ -z "$wnm" ] && continue
            status_plain="stopped"; status_col="$YELLOW"
            if [ -n "$wpid" ] && proc_is_running "$wpid"; then status_plain="running"; status_col="$GREEN"; fi
            printf '%s\n' "    [W] $wnm (pid:${wpid:-}) ${status_col}${status_plain}${RESET}" >> "$tree_tmp"
          done
        fi

        rm -f "$regtmp" 2>/dev/null || true

      else
        # Fallback: build a minimal tree from ps output
        printf '%s\n' "[v] v-daemon | $SWARM_STATUS | uptime: $uptime_fmt" >> "$tree_tmp"
        sup_pid=""
        [ -f "$SUP_PIDFILE" ] && sup_pid="$(cat "$SUP_PIDFILE" 2>/dev/null || true)"
        if [ -n "$sup_pid" ] && kill -0 "$sup_pid" 2>/dev/null; then status_plain="running"; status_col="$GREEN"; else status_plain="stopped"; status_col="$YELLOW"; fi
        printf '%s\n' "  [S] supervisor (pid:${sup_pid:-}) ${status_col}${status_plain}${RESET}" >> "$tree_tmp"

        dm_pid=""
        [ -f "$DAEMON_PIDFILE" ] && dm_pid="$(cat "$DAEMON_PIDFILE" 2>/dev/null || true)"
        if [ -n "$dm_pid" ] && kill -0 "$dm_pid" 2>/dev/null; then status_plain="running"; status_col="$GREEN"; else status_plain="stopped"; status_col="$YELLOW"; fi
        printf '%s\n' "  [M] daemon (pid:${dm_pid:-}) ${status_col}${status_plain}${RESET}" >> "$tree_tmp"

        dir_pid=""
        [ -f "$DIRECTOR_PIDFILE" ] && dir_pid="$(cat "$DIRECTOR_PIDFILE" 2>/dev/null || true)"
        if [ -n "$dir_pid" ] && kill -0 "$dir_pid" 2>/dev/null; then status_plain="running"; status_col="$GREEN"; else status_plain="stopped"; status_col="$YELLOW"; fi
        printf '%s\n' "  [D] director (pid:${dir_pid:-}) ${status_col}${status_plain}${RESET}" >> "$tree_tmp"

        printf '%s\n' "  workers/" >> "$tree_tmp"
        printf '%s\n' "$PS_OUT" | awk 'tolower($0) ~ /worker/ {print $1" "substr($0,index($0,$2))}' | while read -r pid args; do
          nm="worker-${pid}"
          if kill -0 "$pid" 2>/dev/null; then status_plain="running"; status_col="$GREEN"; else status_plain="stopped"; status_col="$YELLOW"; fi
          printf '%s\n' "    [W] $nm (pid:${pid:-}) ${status_col}${status_plain}${RESET}" >> "$tree_tmp"
        done
      fi

      tree_count=$(wc -l <"$tree_tmp" 2>/dev/null || echo 0)
      # publish tree count for input loop to read
      printf '%s' "$tree_count" > "$RUN_DIR/monitor_tree_count" 2>/dev/null || true
      if [ "$tree_count" -eq 0 ]; then
        # Only redraw anchored status when it changes to reduce flicker
        if [ "${status_line}" != "${LAST_STATUS_LINE}" ]; then
          # when no tree, print status and leave
          printf '\033[s\033[999B\033[2K\r%s\n\033[u' "$status_line" >&2
          LAST_STATUS_LINE="$status_line"
        fi
      else
        # Redraw when status, tree count, selection, focus, buffer, or cursor state changes
        SEL="$(cat "$RUN_DIR/monitor_selected" 2>/dev/null || echo 1)"
        FOCUS="$(cat "$RUN_DIR/monitor_focus" 2>/dev/null || echo cmd)"
        BUF="$(cat "$RUN_DIR/monitor_input_buf" 2>/dev/null || echo '')"
        # If buffer starts with a Tab (some terminals/pipes deliver it into the buffer), toggle focus and strip it
        if [ -n "$BUF" ]; then
          first_ch="$(printf '%s' "$BUF" | head -c 1)"
          TAB_CH="$(printf '\t')"
          if [ "$first_ch" = "$TAB_CH" ]; then
            # toggle focus
            cur_focus="$(cat "$RUN_DIR/monitor_focus" 2>/dev/null || echo cmd)"
            if [ "$cur_focus" = "cmd" ]; then printf 'tree' > "$RUN_DIR/monitor_focus"; else printf 'cmd' > "$RUN_DIR/monitor_focus"; fi
            # strip leading tab from buffer both in-memory and on-disk
            BUF="$(printf '%s' "$BUF" | tail -c +2)"
            printf '%s' "$BUF" > "$RUN_DIR/monitor_input_buf"
            FOCUS="$(cat "$RUN_DIR/monitor_focus" 2>/dev/null || echo cmd)"
          fi
        fi
        if [ "${status_line}" != "${LAST_STATUS_LINE}" ] || [ "$tree_count" != "${LAST_TREE_COUNT:-}" ] || [ "$SEL" != "${LAST_SEL:-}" ] || [ "$FOCUS" != "${LAST_FOCUS:-}" ] || [ "$BUF" != "${LAST_BUF:-}" ] || [ "${CURSOR_TOG:-0}" != "${LAST_CURSOR_TOG:-}" ]; then
          # full-screen redraw: move cursor home and clear screen, then print status header
          printf '\033[H\033[2J' >&2
          printf '%s\n' "$status_line" >&2

          # compute message count (last command output) and include in move calculation
          if [ -f "$RUN_DIR/monitor_last_msg" ]; then
            message_count=$(wc -l < "$RUN_DIR/monitor_last_msg" 2>/dev/null || echo 0)
          else
            message_count=0
          fi

          # compute tail lines to display from log tail files
          log_tail_count=0
          tail_buf=""
          if [ -f "$LOG_TAIL_FILE" ] || [ -f "$SUP_TAIL_FILE" ] || [ -f "$DIR_TAIL_FILE" ]; then
            tail_buf="$( ( [ -f "$LOG_TAIL_FILE" ] && tail -n 6 "$LOG_TAIL_FILE" || true; [ -f "$SUP_TAIL_FILE" ] && tail -n 6 "$SUP_TAIL_FILE" || true; [ -f "$DIR_TAIL_FILE" ] && tail -n 6 "$DIR_TAIL_FILE" || true ) | tail -n 6 )"
            log_tail_count=$(printf '%s\n' "$tail_buf" | sed '/^$/d' | wc -l 2>/dev/null || echo 0)
          fi


          n=0
          total=$(wc -l <"$tree_tmp" 2>/dev/null || echo 0)
          # clamp selection to valid range
          case "$SEL" in ''|*[!0-9]*) SEL=1 ;; esac
          if [ "$SEL" -lt 1 ]; then SEL=1; fi
          if [ "$total" -gt 0 ] && [ "$SEL" -gt "$total" ]; then SEL="$total"; fi
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

          # print log tail lines (rendered from background tail files)
          if [ -n "$tail_buf" ]; then
            printf '%s\n' "$tail_buf" | while IFS= read -r tl; do
              printf '\033[2K\r%s\n' "   $tl" >&2
            done
          fi

          # print any last command output lines (from handle_command)
          if [ -f "$RUN_DIR/monitor_last_msg" ]; then
            while IFS= read -r ml; do
              printf '\033[2K\r%s\n' "$ml" >&2
            done < "$RUN_DIR/monitor_last_msg"
          fi

          # print input prompt line above the anchored status
          if [ "$FOCUS" = "cmd" ]; then
            prefix='$'
          else
            prefix='(tree)'
          fi

          # Build cursor (blink state toggled each refresh)
          if [ "$FOCUS" = "cmd" ]; then
            if [ "${CURSOR_TOG:-1}" -eq 1 ]; then
              cursor="${INV} ${RESET}"
            else
              cursor=' '
            fi
            prompt="${prefix} > ${BUF}${cursor}"
          else
            prompt="${prefix} > ${BUF}"
          fi
          printf '\033[2K\r%s\n' "$prompt" >&2

          # print final status line and restore cursor
          # status_line already printed earlier in full-screen redraw
          LAST_STATUS_LINE="$status_line"
          LAST_TREE_COUNT="$tree_count"
          LAST_SEL="$SEL"
          LAST_FOCUS="$FOCUS"
          LAST_BUF="$BUF"
          LAST_CURSOR_TOG="${CURSOR_TOG:-0}"
        fi
      fi
      rm -f "$tree_tmp" 2>/dev/null || true

      # If the swarm was active when the monitor started but is now offline, exit monitor gracefully
      if [ "$INITIAL_ACTIVE" -eq 1 ] && [ "$SWARM_STATUS" = "swarm offline" ]; then
        # Kill tails to allow monitor to exit cleanly
        [ -n "${TAIL_D:-}" ] && kill "$TAIL_D" 2>/dev/null || true
        [ -n "${TAIL_S:-}" ] && kill "$TAIL_S" 2>/dev/null || true
        [ -n "${TAIL_DIR:-}" ] && kill "$TAIL_DIR" 2>/dev/null || true
        # Update anchored status line to reflect final state and exit (no log output by default)
        printf '\033[s\033[999B\033[2K\r%s\033[u' "[SYSTEM] swarm offline" >&2
        break
      fi

      # If any of the tail processes exit unexpectedly, log and exit so callers don't hang
      if [ -n "${TAIL_D:-}" ] && ! kill -0 "$TAIL_D" 2>/dev/null; then
        if [ "${STREAM_LOGS:-0}" -eq 1 ]; then
          printf '%s [SYSTEM] daemon log tail stopped; exiting monitor\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >&2
        fi
        break
      fi
      if [ -n "${TAIL_S:-}" ] && ! kill -0 "$TAIL_S" 2>/dev/null; then
        if [ "${STREAM_LOGS:-0}" -eq 1 ]; then
          printf '%s [SYSTEM] supervisor log tail stopped; exiting monitor\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >&2
        fi
        break
      fi
      if [ -n "${TAIL_DIR:-}" ] && ! kill -0 "$TAIL_DIR" 2>/dev/null; then
        if [ "${STREAM_LOGS:-0}" -eq 1 ]; then
          printf '%s [SYSTEM] director log tail stopped; exiting monitor\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >&2
        fi
        break
      fi

      sleep "$MONITOR_INTERVAL"
    done
  }
  refresh_status_loop & STATUS_PID=$!
  # Run input loop in foreground so it can read the terminal reliably
  input_loop

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