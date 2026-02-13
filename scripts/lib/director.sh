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

# Runtime helpers: timeout wrapper, structured state audits, and backoff files
run_with_timeout() {
  timeout_secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$timeout_secs" "$@"
    return $?
  fi
  tmpout="$(mktemp -t vdaemon.out.XXXXXX 2>/dev/null || mktemp)"
  tmperr="$(mktemp -t vdaemon.err.XXXXXX 2>/dev/null || mktemp)"
  "$@" >"$tmpout" 2>"$tmperr" &
  cmdpid=$!
  (
    sleep "$timeout_secs"
    if kill -0 "$cmdpid" 2>/dev/null; then
      kill "$cmdpid" 2>/dev/null || true
      sleep 0.1
      kill -9 "$cmdpid" 2>/dev/null || true
    fi
  ) &
  killer=$!
  wait "$cmdpid" 2>/dev/null || rc=$?
  rc=${rc:-0}
  kill "$killer" 2>/dev/null || true
  if [ -s "$tmpout" ]; then
    cat "$tmpout" >>"$LOGFILE" 2>/dev/null || true
  fi
  if [ -s "$tmperr" ]; then
    cat "$tmperr" >>"$LOGFILE" 2>/dev/null || true
  fi
  rm -f "$tmpout" "$tmperr" 2>/dev/null || true
  return "$rc"
}

audit_state_start() {
  s="$1"
  epoch="$(date +%s)"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "{\"ts\":\"$ts\",\"event\":\"state_start\",\"state\":\"$s\",\"epoch\":$epoch,\"pid\":$$}" >>"$DEV_AUDITS_DIR/director-heartbeats.jsonl" || true
  printf '%s' "$epoch" >"$RUN_DIR/director_state_${s}_start" 2>/dev/null || true
}

audit_state_end() {
  s="$1"; next="$2"; status="$3"; err="$4"
  end_epoch="$(date +%s)"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  start_epoch="$(cat "$RUN_DIR/director_state_${s}_start" 2>/dev/null || echo 0)"
  dur=0
  if [ -n "$start_epoch" ] && [ "$start_epoch" -gt 0 ] 2>/dev/null; then
    dur=$((end_epoch - start_epoch))
  fi
  err_esc="$(printf '%s' "$err" | tr '\n' ' ' | sed 's/"/\\"/g')"
  echo "{\"ts\":\"$ts\",\"event\":\"state_end\",\"state\":\"$s\",\"next\":\"$next\",\"status\":\"$status\",\"error\":\"$err_esc\",\"duration_seconds\":$dur,\"pid\":$$}" >>"$DEV_AUDITS_DIR/director-heartbeats.jsonl" || true
  rm -f "$RUN_DIR/director_state_${s}_start" 2>/dev/null || true
}

# Backoff control for patch failures
PATCH_BACKOFF_FILE="${RUN_DIR}/v-director-backoff"
PATCH_BACKOFF_BASE="${PATCH_BACKOFF_BASE:-10}"
PATCH_BACKOFF_MAX="${PATCH_BACKOFF_MAX:-600}"
SLEEP_OVERRIDE_FILE="${RUN_DIR}/v-director-sleep-override"

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
  audit_state_start "summarize"
  log "state=summarize"
  status="ok"
  err=""
  if command -v run_autopilot_summary >/dev/null 2>&1; then
    log "invoking run_autopilot_summary"
    if run_with_timeout "${DIRECTOR_SKILL_TIMEOUT_SECONDS:-30}" run_autopilot_summary >/dev/null 2>&1; then
      log "run_autopilot_summary succeeded"
    else
      log "run_autopilot_summary failed or timed out"
      status="error"
      err="run_autopilot_summary failed or timed out"
    fi
  else
    log "mock summarize: no run_autopilot_summary available"
  fi
  audit_state_end "summarize" "next_steps" "$status" "$err"
  echo "next_steps"
}

state_next_steps() {
  audit_state_start "next_steps"
  log "state=next_steps"
  status="ok"
  err=""
  if [ -f "$REPO_ROOT/scripts/skills/next-steps.sh" ]; then
    log "running skills/next-steps.sh"
    if run_with_timeout "${DIRECTOR_SKILL_TIMEOUT_SECONDS:-60}" sh "$REPO_ROOT/scripts/skills/next-steps.sh" >/dev/null 2>&1; then
      log "next-steps succeeded"
    else
      log "next-steps skill failed or timed out"
      status="error"
      err="next-steps failed or timed out"
    fi
  else
    log "mock next-steps"
  fi
  audit_state_end "next_steps" "select_task" "$status" "$err"
  echo "select_task"
}

state_select_task() {
  audit_state_start "select_task"
  log "state=select_task"
  # Placeholder selection logic: always attempt patch_repo then merge_up in this stub
  audit_state_end "select_task" "patch_repo" "ok" ""
  echo "patch_repo"
}

state_patch_repo() {
  audit_state_start "patch_repo"
  log "state=patch_repo"
  status="ok"
  err=""
  next_state="merge_up"
  if [ -f "$REPO_ROOT/scripts/skills/patch-repo.sh" ]; then
    log "invoking skills/patch-repo.sh"
    if run_with_timeout "${DIRECTOR_SKILL_TIMEOUT_SECONDS:-120}" sh "$REPO_ROOT/scripts/skills/patch-repo.sh" >/dev/null 2>&1; then
      log "patch-repo succeeded"
      printf '0' >"$PATCH_BACKOFF_FILE" 2>/dev/null || true
      rm -f "$SLEEP_OVERRIDE_FILE" 2>/dev/null || true
    else
      log "patch-repo failed or timed out; will back off and skip merge_up"
      status="error"
      err="patch-repo failed or timed out"
      old="$(cat "$PATCH_BACKOFF_FILE" 2>/dev/null || echo 0)"
      old=${old:-0}
      new=$((old + PATCH_BACKOFF_BASE))
      if [ "$new" -gt "$PATCH_BACKOFF_MAX" ]; then new=$PATCH_BACKOFF_MAX; fi
      printf '%s' "$new" >"$PATCH_BACKOFF_FILE" 2>/dev/null || true
      printf '%s' "$new" >"$SLEEP_OVERRIDE_FILE" 2>/dev/null || true
      next_state="sleep"
    fi
  else
    log "mock patch-repo: script not found"
  fi
  audit_state_end "patch_repo" "$next_state" "$status" "$err"
  echo "$next_state"
}

state_merge_up() {
  audit_state_start "merge_up"
  log "state=merge_up"
  status="ok"
  err=""
  if [ -f "$REPO_ROOT/scripts/skills/merge-up.sh" ]; then
    log "invoking skills/merge-up.sh"
    if run_with_timeout "${DIRECTOR_SKILL_TIMEOUT_SECONDS:-60}" sh "$REPO_ROOT/scripts/skills/merge-up.sh" >/dev/null 2>&1; then
      log "merge-up succeeded"
    else
      log "merge-up failed or timed out"
      status="error"
      err="merge-up failed or timed out"
    fi
  else
    log "mock merge-up: script not found"
  fi
  audit_state_end "merge_up" "sleep" "$status" "$err"
  echo "sleep"
}

state_sleep() {
  audit_state_start "sleep"
  interval="${DIRECTOR_INTERVAL_SECONDS:-60}"
  if [ -f "$SLEEP_OVERRIDE_FILE" ]; then
    interval="$(cat "$SLEEP_OVERRIDE_FILE" 2>/dev/null || echo "$interval")"
    rm -f "$SLEEP_OVERRIDE_FILE" 2>/dev/null || true
  fi
  log "state=sleep (sleeping ${interval}s)"
  sleep "$interval"
  audit_state_end "sleep" "summarize" "ok" ""
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
