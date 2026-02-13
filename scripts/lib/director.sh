#!/usr/bin/env sh
# Director agent: HFSM-based director coordinating worker skills (stubbed states)
set -eu

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  cat <<'USAGE'
Usage: sh scripts/lib/director.sh

Director HFSM stub: runs a sequence of states and invokes skills when available.
States (simple cycle): load_actions -> summarize -> next_steps -> select_task -> patch_repo -> merge_up -> sleep -> summarize
USAGE
  exit 0
fi

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if [ -f "$REPO_ROOT/scripts/lib/config.sh" ]; then
  . "$REPO_ROOT/scripts/lib/config.sh"
  config_init "$REPO_ROOT"
fi
# Ensure RUN_DIR falls back to repo run/ if not set by config
RUN_DIR="${RUN_DIR:-$REPO_ROOT/run}"
PIDFILE="${RUN_DIR}/v-director.pid"
LOCKDIR="${RUN_DIR}/v-director.lock"
SCRIPT_NAME="$(basename "$0")"

# Acquire a simple lock using mkdir to avoid concurrent director instances
acquire_lock() {
  for i in 0 1 2; do
    if mkdir "$LOCKDIR" 2>/dev/null; then
      echo "$$" > "$LOCKDIR/pid"
      return 0
    fi
    OWNER_PID="$(cat "$LOCKDIR/pid" 2>/dev/null || true)"
    if [ -n "$OWNER_PID" ] && kill -0 "$OWNER_PID" 2>/dev/null; then
      cmdline="$(ps -p "$OWNER_PID" -o args= 2>/dev/null || true)"
      if [ -n "$cmdline" ] && echo "$cmdline" | grep -F -q "$SCRIPT_NAME"; then
        return 1
      else
        rm -rf "$LOCKDIR" 2>/dev/null || true
        sleep 0.1
        continue
      fi
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

# If a director is already running, exit to avoid multiple instances
if [ -f "$PIDFILE" ]; then
  EXIST_PID=$(cat "$PIDFILE" 2>/dev/null || true)
  if [ -n "$EXIST_PID" ] && kill -0 "$EXIST_PID" 2>/dev/null; then
    echo "Director already running (PID $EXIST_PID)" >&2
    exit 0
  else
    rm -f "$PIDFILE" 2>/dev/null || true
  fi
fi

# Acquire lock
if ! acquire_lock; then
  echo "Another director instance appears to be running; exiting" >&2
  exit 0
fi

cleanup() {
  if [ -f "$PIDFILE" ] && [ "$(cat "$PIDFILE" 2>/dev/null || true)" = "$$" ]; then
    rm -f "$PIDFILE"
  fi
  if [ -f "$LOCKDIR/pid" ] && [ "$(cat "$LOCKDIR/pid" 2>/dev/null || true)" = "$$" ]; then
    rm -rf "$LOCKDIR" 2>/dev/null || true
  fi
  exit 0
}
trap 'cleanup' INT TERM EXIT

echo $$ >"$PIDFILE"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
mkdir -p "$REPO_ROOT/logs"
DEV_AUDITS_DIR="$REPO_ROOT/audits"
mkdir -p "$DEV_AUDITS_DIR"
LOGFILE="${REPO_ROOT}/logs/director.log"

echo "$(date +'%Y-%m-%dT%H:%M:%S%z') [AGENT-DIRECTOR] director HFSM starting (PID $$)" >>"$LOGFILE"

# Helper to emit audit+log
log() {
  ts="$(date +'%Y-%m-%dT%H:%M:%S%z')"
  msg="$1"
  echo "$ts [AGENT-DIRECTOR] $msg" >>"$LOGFILE"
  printf '%s\n' "{\"ts\":\"$ts\",\"event\":\"$msg\",\"role\":\"director\",\"pid\":$$}" >>"$DEV_AUDITS_DIR/director-heartbeats.jsonl" || true
}

# HFSM state functions: each echoes the next state name
state_load_actions() {
  log "state=load_actions: loading actions.sh if present"
  if [ -f "$SCRIPT_DIR/actions.sh" ]; then
    # shellcheck source=/dev/null
    . "$SCRIPT_DIR/actions.sh"
    log "sourced actions.sh"
  else
    log "actions.sh not present; using mock actions"
  fi
  echo "summarize"
}

state_summarize() {
  log "state=summarize"
  if command -v run_autopilot_summary >/dev/null 2>&1; then
    log "invoking run_autopilot_summary"
    ( run_autopilot_summary ) >/dev/null 2>&1 || log "run_autopilot_summary failed"
  else
    log "mock summarize: no run_autopilot_summary available"
  fi
  echo "next_steps"
}

state_next_steps() {
  log "state=next_steps"
  if [ -f "$REPO_ROOT/scripts/skills/next-steps.sh" ]; then
    log "running skills/next-steps.sh"
    sh "$REPO_ROOT/scripts/skills/next-steps.sh" || log "next-steps skill failed"
  else
    log "mock next-steps"
  fi
  echo "select_task"
}

state_select_task() {
  log "state=select_task"
  # Placeholder selection logic: always attempt patch_repo then merge_up in this stub
  echo "patch_repo"
}

state_patch_repo() {
  log "state=patch_repo"
  if [ -f "$REPO_ROOT/scripts/skills/patch-repo.sh" ]; then
    log "invoking skills/patch-repo.sh"
    sh "$REPO_ROOT/scripts/skills/patch-repo.sh" || log "patch-repo skill returned error"
  else
    log "mock patch-repo: script not found"
  fi
  echo "merge_up"
}

state_merge_up() {
  log "state=merge_up"
  if [ -f "$REPO_ROOT/scripts/skills/merge-up.sh" ]; then
    log "invoking skills/merge-up.sh"
    sh "$REPO_ROOT/scripts/skills/merge-up.sh" || log "merge-up skill returned error"
  else
    log "mock merge-up: script not found"
  fi
  echo "sleep"
}

state_sleep() {
  interval="${DIRECTOR_INTERVAL_SECONDS:-60}"
  log "state=sleep (sleeping $interval seconds)"
  sleep "$interval"
  echo "summarize"
}

# Initial HFSM state
CURRENT_STATE="load_actions"

while true; do
  # heartbeat
  log "heartbeat"
  case "$CURRENT_STATE" in
    load_actions)
      CURRENT_STATE="$(state_load_actions)" ;;
    summarize)
      CURRENT_STATE="$(state_summarize)" ;;
    next_steps)
      CURRENT_STATE="$(state_next_steps)" ;;
    select_task)
      CURRENT_STATE="$(state_select_task)" ;;
    patch_repo)
      CURRENT_STATE="$(state_patch_repo)" ;;
    merge_up)
      CURRENT_STATE="$(state_merge_up)" ;;
    sleep)
      CURRENT_STATE="$(state_sleep)" ;;
    *)
      log "unknown state '$CURRENT_STATE', resetting to summarize"
      CURRENT_STATE="summarize" ;;
  esac
done
