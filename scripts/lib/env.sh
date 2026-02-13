#!/usr/bin/env sh
# Environment initialization for v-daemon scripts.
# Usage: env_init REPO_ROOT
env_init() {
  # Idempotent: avoid re-running init when sourced multiple times during command invocation
  if [ "${_V_DAEMON_ENV_INIT_DONE:-}" = "1" ]; then
    return 0
  fi

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
  # Load console, logger, and centralized prompts so callers get consistent helpers
  if [ -f "$REPO_ROOT/scripts/lib/console.sh" ]; then
    . "$REPO_ROOT/scripts/lib/console.sh"
  fi
  if [ -f "$REPO_ROOT/scripts/lib/logger.sh" ]; then
    . "$REPO_ROOT/scripts/lib/logger.sh"
  fi
  # Load centralized prompts (prompts.sh) for AI prompt reuse
  if [ -f "$REPO_ROOT/scripts/lib/prompts.sh" ]; then
    . "$REPO_ROOT/scripts/lib/prompts.sh"
  fi

  _V_DAEMON_ENV_INIT_DONE=1
}
