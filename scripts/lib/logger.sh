#!/usr/bin/env sh
# Simple logger API for v-daemon scripts.
: "${LOG_DIR:=./logs}"
LOGFILE="${LOGFILE:-$LOG_DIR/daemon.log}"
SUP_LOGFILE="${SUP_LOGFILE:-$LOG_DIR/supervisor.log}"
DIRECTOR_LOG="${DIRECTOR_LOG:-$LOG_DIR/director.log}"
# Default system log: prefer LOG_DIR so system.log lives with other logs; fall back to RUN_DIR
SYSTEM_LOGFILE="${SYSTEM_LOGFILE:-${LOG_DIR}/system.log}"

# Ensure log directories exist; do NOT truncate an existing system log (preserve prior contents)
mkdir -p "$LOG_DIR" 2>/dev/null || true
mkdir -p "$(dirname "$SYSTEM_LOGFILE")" 2>/dev/null || true

log_write() {
  file="$1"; shift
  tag="$1"; shift
  msg="$*"
  ts="$(date +'%Y-%m-%dT%H:%M:%S%z')"
  printf '%s [%s] %s\n' "$ts" "$tag" "$msg" >>"$file" 2>/dev/null || true
  # Also append to combined system log, avoid duplication if target is system log
  if [ "$file" != "$SYSTEM_LOGFILE" ]; then
    printf '%s [%s] %s\n' "$ts" "$tag" "$msg" >>"$SYSTEM_LOGFILE" 2>/dev/null || true
  fi
}

log_info() { log_write "$LOGFILE" "INFO" "$*"; }
log_warn() { log_write "$LOGFILE" "WARN" "$*"; }
log_error() { log_write "$LOGFILE" "ERROR" "$*"; }
log_supervisor() { log_write "$SUP_LOGFILE" "SUPERVISOR" "$*"; }
log_director() { log_write "$DIRECTOR_LOG" "AGENT-DIRECTOR" "$*"; }

# Backwards-compatible printf helper
log_printf() {
  file="$1"; shift
  printf '%s %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$*" >>"$file" 2>/dev/null || true
  if [ "$file" != "$SYSTEM_LOGFILE" ]; then
    printf '%s %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$*" >>"$SYSTEM_LOGFILE" 2>/dev/null || true
  fi
}
