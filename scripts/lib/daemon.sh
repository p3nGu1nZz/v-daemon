#!/usr/bin/env sh
# Minimal daemon loop. Replace loop body with self-improving logic later.
set -eu

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  cat <<'USAGE'
Usage: sh scripts/lib/daemon.sh

Minimal daemon loop that writes heartbeat to ./logs/daemon.log and PID to run/v-daemon.pid.
Intended to be managed by scripts/run.sh supervisor.
USAGE
  exit 0
fi

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if [ -f "$REPO_ROOT/scripts/lib/config.sh" ]; then
  . "$REPO_ROOT/scripts/lib/config.sh"
  config_init "$REPO_ROOT"
fi
PIDFILE="${RUN_DIR}/v-daemon.pid"
LOCKDIR="${RUN_DIR}/v-daemon.lock"

# Acquire a simple lock using mkdir to avoid concurrent daemon instances
acquire_lock() {
  for i in 0 1 2; do
    if mkdir "$LOCKDIR" 2>/dev/null; then
      echo "$$" > "$LOCKDIR/pid"
      return 0
    fi
    OWNER_PID="$(cat "$LOCKDIR/pid" 2>/dev/null || true)"
    if [ -n "$OWNER_PID" ] && kill -0 "$OWNER_PID" 2>/dev/null; then
      # another active owner
      return 1
    fi
    # stale lock, remove and retry
    rm -rf "$LOCKDIR" 2>/dev/null || true
    sleep 0.1
  done
  if mkdir "$LOCKDIR" 2>/dev/null; then
    echo "$$" > "$LOCKDIR/pid"
    return 0
  fi
  return 1
}

# If a daemon is already running, exit to avoid multiple writers to the log
if [ -f "$PIDFILE" ]; then
  EXIST_PID=$(cat "$PIDFILE" 2>/dev/null || true)
  if [ -n "$EXIST_PID" ] && kill -0 "$EXIST_PID" 2>/dev/null; then
    # if the pidfile points to this process, proceed; otherwise another daemon is running
    if [ "$EXIST_PID" = "$$" ]; then
      :
    else
      echo "Daemon already running (PID $EXIST_PID)" >&2
      exit 0
    fi
  else
    # stale pidfile
    rm -f "$PIDFILE" 2>/dev/null || true
  fi
fi

# Acquire global lock to prevent concurrent startup races
if ! acquire_lock; then
  echo "Another daemon instance appears to be running; exiting" >&2
  exit 0
fi

cleanup() {
  # ensure director is stopped if we started it
  if [ -n "${DIRECTOR_PIDFILE:-}" ]; then
    if [ -f "$SCRIPT_DIR/process.sh" ]; then
      stop_by_pidfile "$DIRECTOR_PIDFILE" || true
    else
      if [ -f "$DIRECTOR_PIDFILE" ]; then
        DPID=$(cat "$DIRECTOR_PIDFILE" 2>/dev/null || true)
        if [ -n "$DPID" ] && kill -0 "$DPID" 2>/dev/null; then
          kill "$DPID" 2>/dev/null || true
        fi
        rm -f "$DIRECTOR_PIDFILE" 2>/dev/null || true
      fi
    fi
  fi

  # only remove pidfile if it belongs to this process
  if [ -f "$PIDFILE" ] && [ "$(cat "$PIDFILE" 2>/dev/null || true)" = "$$" ]; then
    rm -f "$PIDFILE"
  fi
  # remove lock if owned by this process
  if [ -f "$LOCKDIR/pid" ] && [ "$(cat "$LOCKDIR/pid" 2>/dev/null || true)" = "$$" ]; then
    rm -rf "$LOCKDIR" 2>/dev/null || true
  fi
  exit 0
}
trap 'cleanup' INT TERM EXIT

echo $$ >"$PIDFILE"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Repo root is two levels up from scripts/lib
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
mkdir -p "$REPO_ROOT/logs"
LOGFILE="${REPO_ROOT}/logs/daemon.log"
DIRECTOR="${SCRIPT_DIR}/director.sh"
DIRECTOR_PIDFILE="${RUN_DIR}/v-director.pid"
DIRECTOR_LOCK="${RUN_DIR}/v-director.lock"
DIRECTOR_LOG="${REPO_ROOT}/logs/director.log"
SQL_AGENT="${SCRIPT_DIR}/sql-agent.sh"
SQL_AGENT_PIDFILE="${RUN_DIR}/v-sql-agent.pid"
SQL_AGENT_LOCK="${RUN_DIR}/v-sql-agent.lock"
SQL_AGENT_LOG="${REPO_ROOT}/logs/sql-agent.log"
# Source process controller if available
if [ -f "$SCRIPT_DIR/process.sh" ]; then
  . "$SCRIPT_DIR/process.sh"
fi

# Helper: verify a PID corresponds to a running process whose cmdline contains the script path
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
  if [ -n "$cmdline" ] && echo "$cmdline" | grep -F -q "$script"; then
    return 0
  fi
  return 1
}

# Log helper: write to logfile and echo to stdout when interactive (avoids duplicating into logfile when stdout is redirected)
log() {
  msg="$1"
  printf '%s %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$msg" >>"$LOGFILE"
  if [ -t 1 ]; then
    printf '%s %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$msg"
  fi
}

# Ensure director process is running; function to adopt or start the director
ensure_director_running() {
  if [ -f "$DIRECTOR_PIDFILE" ]; then
    DP_EXIST=$(cat "$DIRECTOR_PIDFILE" 2>/dev/null || true)
    if is_pid_for_script "$DP_EXIST" "$DIRECTOR"; then
      return 0
    fi
    rm -f "$DIRECTOR_PIDFILE" 2>/dev/null || true
  fi

  # Try to adopt any running director matching the script
  EXIST="$(ps_fallback pid,args | awk -v pat=\"$DIRECTOR\" '$0 ~ pat {print $1}')"
  for p in $EXIST; do
    if [ -n "$p" ] && is_pid_for_script "$p" "$DIRECTOR"; then
      echo "$p" >"$DIRECTOR_PIDFILE" 2>/dev/null || true
      log "[DAEMON] director agent adopted (PID $p)"
      return 0
    fi
  done

  # If a director lock exists, adopt or skip starting to avoid races
  if [ -d "$DIRECTOR_LOCK" ]; then
    LOCK_OWNER="$(cat "$DIRECTOR_LOCK/pid" 2>/dev/null || true)"
    if [ -n "$LOCK_OWNER" ] && kill -0 "$LOCK_OWNER" 2>/dev/null; then
      if is_pid_for_script "$LOCK_OWNER" "$DIRECTOR"; then
        echo "$LOCK_OWNER" >"$DIRECTOR_PIDFILE" 2>/dev/null || true
        log "[DAEMON] director agent appears to be starting (lock owner PID $LOCK_OWNER), adopting"
        return 0
      else
        # stale or unrelated lock owner, remove it
        log "[DAEMON] director lock present but owner PID $LOCK_OWNER is not director; removing stale lock"
        rm -rf "$DIRECTOR_LOCK" 2>/dev/null || true
      fi
    else
      # stale lock, remove it
      rm -rf "$DIRECTOR_LOCK" 2>/dev/null || true
    fi
  fi

  # Start the director and wait briefly for it to create its pidfile
  log "[DAEMON] starting director agent (initiated by daemon)"
  # Ensure director runs under bash so scripts that rely on bash features (e.g., hfsm.sh)
  # are interpreted correctly. Previously this used `sh` which can be dash on many systems.
  nohup bash "$DIRECTOR" >>"$DIRECTOR_LOG" 2>&1 &
  D_START=$!
  WAITED=0
  while [ $WAITED -lt 25 ]; do
    if [ -f "$DIRECTOR_PIDFILE" ]; then
      DP_EXIST=$(cat "$DIRECTOR_PIDFILE" 2>/dev/null || true)
      if is_pid_for_script "$DP_EXIST" "$DIRECTOR"; then
        log "[DAEMON] director agent started (PID $DP_EXIST)"
        return 0
      fi
    fi
    sleep 0.2
    WAITED=$((WAITED+1))
  done

  if [ ! -f "$DIRECTOR_PIDFILE" ]; then
    # Only write fallback pidfile if the process we started still looks like the director
    if is_pid_for_script "$D_START" "$DIRECTOR"; then
      echo "$D_START" >"$DIRECTOR_PIDFILE" 2>/dev/null || true
      log "[DAEMON] director agent started (PID $D_START) (pidfile created by daemon)"
    else
      log "[DAEMON] director helper process (PID $D_START) did not match director; not writing pidfile"
    fi
  fi
  return 0
}

# Ensure sql-agent process is running; function to adopt or start the sql-agent
ensure_sql_agent_running() {
  if [ -f "$SQL_AGENT_PIDFILE" ]; then
    SP_EXIST=$(cat "$SQL_AGENT_PIDFILE" 2>/dev/null || true)
    if is_pid_for_script "$SP_EXIST" "$SQL_AGENT"; then
      return 0
    fi
    rm -f "$SQL_AGENT_PIDFILE" 2>/dev/null || true
  fi

  # Try to adopt any running sql-agent matching the script
  EXIST="$(ps_fallback pid,args | awk -v pat=\"$SQL_AGENT\" '$0 ~ pat {print $1}')"
  for p in $EXIST; do
    if [ -n "$p" ] && is_pid_for_script "$p" "$SQL_AGENT"; then
      echo "$p" >"$SQL_AGENT_PIDFILE" 2>/dev/null || true
      log "[DAEMON] sql-agent adopted (PID $p)"
      return 0
    fi
  done

  if [ -d "$SQL_AGENT_LOCK" ]; then
    LOCK_OWNER="$(cat "$SQL_AGENT_LOCK/pid" 2>/dev/null || true)"
    if [ -n "$LOCK_OWNER" ] && kill -0 "$LOCK_OWNER" 2>/dev/null; then
      if is_pid_for_script "$LOCK_OWNER" "$SQL_AGENT"; then
        echo "$LOCK_OWNER" >"$SQL_AGENT_PIDFILE" 2>/dev/null || true
        log "[DAEMON] sql-agent appears to be starting (lock owner PID $LOCK_OWNER), adopting"
        return 0
      else
        log "[DAEMON] sql-agent lock present but owner PID $LOCK_OWNER is not sql-agent; removing stale lock"
        rm -rf "$SQL_AGENT_LOCK" 2>/dev/null || true
      fi
    else
      rm -rf "$SQL_AGENT_LOCK" 2>/dev/null || true
    fi
  fi

  log "[DAEMON] starting sql-agent (initiated by daemon)"
  nohup sh "$SQL_AGENT" >>"$SQL_AGENT_LOG" 2>&1 &
  S_START=$!
  WAITED=0
  while [ $WAITED -lt 25 ]; do
    if [ -f "$SQL_AGENT_PIDFILE" ]; then
      SP_EXIST=$(cat "$SQL_AGENT_PIDFILE" 2>/dev/null || true)
      if is_pid_for_script "$SP_EXIST" "$SQL_AGENT"; then
        log "[DAEMON] sql-agent started (PID $SP_EXIST)"
        return 0
      fi
    fi
    sleep 0.2
    WAITED=$((WAITED+1))
  done

  if [ ! -f "$SQL_AGENT_PIDFILE" ]; then
    if is_pid_for_script "$S_START" "$SQL_AGENT"; then
      echo "$S_START" >"$SQL_AGENT_PIDFILE" 2>/dev/null || true
      log "[DAEMON] sql-agent started (PID $S_START) (pidfile created by daemon)"
    else
      log "[DAEMON] sql-agent helper process (PID $S_START) did not match sql-agent; not writing pidfile"
    fi
  fi
  return 0
}

# Ensure director is started immediately on daemon startup
ensure_director_running
# Ensure sql-agent is started immediately on daemon startup
ensure_sql_agent_running

while true; do
  # Periodically ensure director is running
  ensure_director_running
  # Periodically ensure sql-agent is running
  ensure_sql_agent_running

  # Heartbeat: include director status so monitor shows director health
  DPID=""
  if [ -f "$DIRECTOR_PIDFILE" ]; then
    DPID=$(cat "$DIRECTOR_PIDFILE" 2>/dev/null || true)
  fi
  if is_pid_for_script "$DPID" "$DIRECTOR"; then
    DIR_STATUS="Director: running (PID $DPID)"
  else
    DIR_STATUS="Director: not running"
  fi
  printf '%s [HEARTBEAT] daemon running on PID %s | %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$$" "$DIR_STATUS" >>"$LOGFILE"
  # Autopatch/build/test placeholder (no-op by default)
  if [ "${DAEMON_SELF_PATCH:-0}" = "1" ]; then
    # Run safe environment checks; disabled by default to avoid unexpected changes
    sh "$REPO_ROOT/scripts/setup.sh" --check || true
  fi
  sleep 20
done
