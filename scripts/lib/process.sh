#!/usr/bin/env sh
# Process controller: utility functions to manage processes started by scripts.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUN_DIR="$REPO_ROOT/run"
LOG_DIR="$REPO_ROOT/logs"
mkdir -p "$RUN_DIR" "$LOG_DIR"

# Portable ps wrapper: attempt GNU-style 'ps -eo' then BSD/macOS-style 'ps -ax -o' as fallback.
ps_fallback() {
  fmt="$1"
  # prefer GNU-style ps -eo if available
  if ps -eo "$fmt" >/dev/null 2>&1; then
    ps -eo "$fmt" 2>/dev/null || true
  else
    # fallback to BSD-style ps -ax -o
    ps -ax -o "$fmt" 2>/dev/null || ps -eo "$fmt" 2>/dev/null || true
  fi
}


# Check if a pid corresponds to a running process
proc_is_running() {
  pid="$1"
  if [ -z "$pid" ]; then
    return 1
  fi
  if kill -0 "$pid" 2>/dev/null; then
    return 0
  fi
  return 1
}

# Stop a process by pidfile path (removes pidfile)
stop_by_pidfile() {
  pidfile="$1"
  if [ -z "$pidfile" ] || [ ! -f "$pidfile" ]; then
    return 1
  fi
  pid=$(cat "$pidfile" 2>/dev/null || true)
  if [ -n "$pid" ] && proc_is_running "$pid"; then
    kill "$pid" 2>/dev/null || true
    sleep 0.1
    if proc_is_running "$pid"; then
      kill -TERM "$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null || true
    fi
  fi
  rm -f "$pidfile" 2>/dev/null || true
  return 0
}

# Register a run pid in ./run/<name>.pid
proc_register() {
  name="$1"
  pid="$2"
  if [ -z "$name" ] || [ -z "$pid" ]; then
    return 1
  fi
  mkdir -p "$RUN_DIR"
  echo "$pid" >"$RUN_DIR/$name.pid"
  return 0
}

# Start command and register under name; logs to ./logs/<name>.log
proc_start_and_register() {
  name="$1"
  shift
  if [ -z "$name" ] || [ $# -eq 0 ]; then
    return 1
  fi
  cmd="$*"
  log="$LOG_DIR/$name.log"
  nohup sh -c "$cmd" >>"$log" 2>&1 &
  pid=$!
  proc_register "$name" "$pid"
  echo "$pid"
  return 0
}

# Stop registered process by name (removes ./run/<name>.pid)
proc_stop_registered() {
  name="$1"
  pidfile="$RUN_DIR/$name.pid"
  if [ -f "$pidfile" ]; then
    pid=$(cat "$pidfile" 2>/dev/null || true)
    if [ -n "$pid" ] && proc_is_running "$pid"; then
      kill "$pid" 2>/dev/null || true
      sleep 0.1
      if proc_is_running "$pid"; then
        kill -TERM "$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null || true
      fi
    fi
    rm -f "$pidfile" 2>/dev/null || true
    return 0
  fi
  return 1
}

# Stop all registered names
proc_stop_all_registered() {
  mkdir -p "$RUN_DIR"
  for f in "$RUN_DIR"/*.pid; do
    [ -f "$f" ] || continue
    nm=$(basename "$f" .pid)
    proc_stop_registered "$nm" || true
  done
  return 0
}

# List registered processes
proc_list_registered() {
  mkdir -p "$RUN_DIR"
  for f in "$RUN_DIR"/*.pid; do
    [ -f "$f" ] || continue
    nm=$(basename "$f" .pid)
    pid=$(cat "$f" 2>/dev/null || true)
    printf '%s %s\n' "$nm" "$pid"
  done
}

# Kill a process and its descendant process tree (children first).
# Attempts to discover descendants via ps and kill them in reverse order.
proc_kill_tree() {
  root="$1"
  if [ -z "$root" ]; then
    return 1
  fi
  tmp="$(mktemp "/tmp/proc_kill_XXXXXX")" || tmp="/tmp/proc_kill_$root"
  echo "$root" >"$tmp"

  # Expand children until stable
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

  # Kill in reverse order (children first)
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
