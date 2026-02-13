#!/usr/bin/env sh
# Lightweight sql-agent: ensures sqlite DB is initialized and performs light maintenance.
set -eu

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  cat <<'USAGE'
Usage: sh scripts/lib/sql-agent.sh
Lightweight sql-agent: ensures sqlite DB exists and performs periodic maintenance.
USAGE
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUN_DIR="${RUN_DIR:-$REPO_ROOT/run}"
mkdir -p "$RUN_DIR" "$REPO_ROOT/logs"

PIDFILE="${RUN_DIR}/v-sql-agent.pid"
LOCKDIR="${RUN_DIR}/v-sql-agent.lock"
LOGFILE="${REPO_ROOT}/logs/sql-agent.log"

# Acquire lock helper (same strategy as daemon)
acquire_lock() {
  for i in 0 1 2; do
    if mkdir "$LOCKDIR" 2>/dev/null; then
      echo "$$" > "$LOCKDIR/pid"
      return 0
    fi
    OWNER_PID="$(cat "$LOCKDIR/pid" 2>/dev/null || true)"
    if [ -n "$OWNER_PID" ] && kill -0 "$OWNER_PID" 2>/dev/null; then
      return 1
    fi
    rm -rf "$LOCKDIR" 2>/dev/null || true
    sleep 0.1
  done
  if mkdir "$LOCKDIR" 2>/dev/null; then
    echo "$$" > "$LOCKDIR/pid"
    return 0
  fi
  return 1
}

cleanup() {
  if [ -f "$PIDFILE" ] && [ "$(cat "$PIDFILE" 2>/dev/null || true)" = "$$" ]; then
    rm -f "$PIDFILE" 2>/dev/null || true
  fi
  if [ -f "$LOCKDIR/pid" ] && [ "$(cat "$LOCKDIR/pid" 2>/dev/null || true)" = "$$" ]; then
    rm -rf "$LOCKDIR" 2>/dev/null || true
  fi
  exit 0
}
trap 'cleanup' INT TERM EXIT

if ! acquire_lock; then
  echo "Another sql-agent instance appears to be running; exiting" >&2
  exit 0
fi

echo "$$" > "$PIDFILE"

# Source env and sql helpers if available
if [ -f "$REPO_ROOT/scripts/lib/env.sh" ]; then
  . "$REPO_ROOT/scripts/lib/env.sh"
fi
if [ -f "$REPO_ROOT/scripts/lib/sql.sh" ]; then
  . "$REPO_ROOT/scripts/lib/sql.sh"
fi

log() {
  msg="$1"
  printf '%s %s\n' "$(date +'%Y-%m-%dT%H:%M:%SZ')" "$msg" >>"$LOGFILE"
  if [ -t 1 ]; then
    printf '%s %s\n' "$(date +'%Y-%m-%dT%H:%M:%SZ')" "$msg"
  fi
}

# Try to initialize DB if possible
if command -v sqlite3 >/dev/null 2>&1; then
  if sql_init 2>/dev/null; then
    log "[SQL-AGENT] DB initialized (${DB_PATH:-$RUN_DIR/v-daemon.db})"
  else
    log "[SQL-AGENT] DB initialization attempted but failed"
  fi
else
  log "[SQL-AGENT] sqlite3 not available yet"
fi

# Simple main loop: ensure DB exists and sleep.
while true; do
  if command -v sqlite3 >/dev/null 2>&1; then
    sql_init >/dev/null 2>&1 || true
    # TODO: process queue files in run/skills/sql-agent/queue/ and ingest tasks via sql_insert_todo
  fi
  sleep 10
done
