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

  # Determine YOLO: env var overrides config, default to true if not set in either.
  # Valid true values: true, 1, yes, y; false values: false, 0, no, n
  if [ -n "${YOLO:-}" ]; then
    YOLO_VAL="$YOLO"
  else
    YOLO_VAL=""
    if [ -f "$CONFIG_FILE" ]; then
      YOLO_VAL=$(awk -F'=' '/^[[:space:]]*yolo[[:space:]]*=/ {v=$2; gsub(/^[[:space:]]+|[[:space:]]+$/,"",v); gsub(/\"|\'\''/,"",v); print tolower(v); exit}' "$CONFIG_FILE" 2>/dev/null || true)
    fi
    YOLO_VAL="${YOLO_VAL:-true}"
  fi
  case "$(printf '%s' "$YOLO_VAL" | tr '[:upper:]' '[:lower:]')" in
    "false"|"0"|"no"|"n") YOLO=false;;
    *) YOLO=true;;
  esac
  export YOLO

  # Determine DIRECTIVE: env var overrides config. Default empty string if not set.
  if [ -n "${DIRECTIVE:-}" ]; then
    DIRECTIVE_VAL="$DIRECTIVE"
  else
    DIRECTIVE_VAL=""
    if [ -f "$CONFIG_FILE" ]; then
      DIRECTIVE_VAL=$(sed -n 's/^[[:space:]]*directive[[:space:]]*=[[:space:]]*"\?\(.*\)"\?/\1/p' "$CONFIG_FILE" | sed -n '1p' || true)
    fi
  fi
  DIRECTIVE="${DIRECTIVE_VAL:-}"
  export DIRECTIVE

  # Load lightweight sqlite helper if available and initialize DB (non-fatal if sqlite missing)
  if [ -f "$REPO_ROOT/scripts/lib/sql.sh" ]; then
    # shellcheck disable=SC1090
    . "$REPO_ROOT/scripts/lib/sql.sh"
    if sql_check >/dev/null 2>&1; then
      sql_init || echo "Warning: sql_init failed (DB initialization)" >&2
    else
      echo "Info: sqlite3 not available; run scripts/setup.sh to install sqlite3 or set YOLO accordingly." >&2
    fi
  fi

  _V_DAEMON_ENV_INIT_DONE=1
}
