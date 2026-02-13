#!/usr/bin/env sh
# Environment initialization for v-daemon scripts.
# Usage: env_init REPO_ROOT
env_init() {
  REPO_ROOT="$1"
  if [ -z "$REPO_ROOT" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
  fi
  CONFIG_FILE="${CONFIG_FILE:-$REPO_ROOT/config/settings.toml}"
  RUN_DIR="${RUN_DIR:-$REPO_ROOT/run}"
  LOG_DIR="${LOG_DIR:-$REPO_ROOT/logs}"
  CHECK_INTERVAL="${CHECK_INTERVAL:-30}"
  AUDITS_DIR="${AUDITS_DIR:-$REPO_ROOT/audits}"
  mkdir -p "$RUN_DIR" "$LOG_DIR" "$AUDITS_DIR" 2>/dev/null || true
  export REPO_ROOT CONFIG_FILE RUN_DIR LOG_DIR CHECK_INTERVAL AUDITS_DIR
}
