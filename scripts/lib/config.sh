#!/usr/bin/env sh
# Configuration loader: reads ./config/settings.toml and exposes runtime variables.
# Usage: . "$REPO_ROOT/scripts/lib/config.sh"; config_init "$REPO_ROOT"

# Minimal TOML reader for simple key = "value" entries under sections.
_toml_get() {
  cfg="$1"; key="$2"; file="$3"
  awk -v sec="[$cfg]" -v key="$key" '
    $0 ~ sec {insec=1; next}
    /^\[/ {insec=0}
    insec && $0 ~ "^[[:space:]]*"key"[[:space:]]*=" {
      val=$0
      sub(/^[^=]*=[[:space:]]*/,"",val)
      gsub(/^[[:space:]]*\"?|\"?[[:space:]]*$/,"",val)
      print val
      exit
    }
  ' "$file" 2>/dev/null || true
}

config_init() {
  # Optional arg: repo root
  if [ -n "${1:-}" ]; then
    REPO_ROOT="$1"
  fi
  if [ -z "${REPO_ROOT:-}" ]; then
    REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  fi

  CONFIG_FILE="$REPO_ROOT/config/settings.toml"

  # Defaults
  RUN_DIR="$REPO_ROOT/run"
  LOG_DIR="$REPO_ROOT/logs"
  DAEMON_PIDFILE="$RUN_DIR/v-daemon.pid"
  SUP_PIDFILE="$RUN_DIR/v-daemon-supervisor.pid"
  DIRECTOR_PIDFILE="$RUN_DIR/v-director.pid"
  DAEMON_LOG="$LOG_DIR/daemon.log"
  SUP_LOGFILE="$LOG_DIR/supervisor.log"
  DIRECTOR_LOG="$LOG_DIR/director.log"
  HEARTBEAT_INTERVAL="${HEARTBEAT_INTERVAL:-30}"

  if [ -f "$CONFIG_FILE" ]; then
    run_val="$(_toml_get paths run "$CONFIG_FILE")"
    if [ -n "$run_val" ]; then
      case "$run_val" in
        /*) RUN_DIR="$run_val" ;;
        *) RUN_DIR="$REPO_ROOT/${run_val#./}" ;;
      esac
    fi

    log_val="$(_toml_get paths logs "$CONFIG_FILE")"
    if [ -n "$log_val" ]; then
      case "$log_val" in
        /*) LOG_DIR="$log_val" ;;
        *) LOG_DIR="$REPO_ROOT/${log_val#./}" ;;
      esac
    fi

    daemon_pid_val="$(_toml_get pid_files daemon "$CONFIG_FILE")"
    if [ -n "$daemon_pid_val" ]; then
      case "$daemon_pid_val" in
        /*) DAEMON_PIDFILE="$daemon_pid_val" ;;
        *) DAEMON_PIDFILE="$REPO_ROOT/${daemon_pid_val#./}" ;;
      esac
    fi

    supervisor_pid_val="$(_toml_get pid_files supervisor "$CONFIG_FILE")"
    if [ -n "$supervisor_pid_val" ]; then
      case "$supervisor_pid_val" in
        /*) SUP_PIDFILE="$supervisor_pid_val" ;;
        *) SUP_PIDFILE="$REPO_ROOT/${supervisor_pid_val#./}" ;;
      esac
    fi

    director_pid_val="$(_toml_get pid_files director "$CONFIG_FILE")"
    if [ -n "$director_pid_val" ]; then
      case "$director_pid_val" in
        /*) DIRECTOR_PIDFILE="$director_pid_val" ;;
        *) DIRECTOR_PIDFILE="$REPO_ROOT/${director_pid_val#./}" ;;
      esac
    fi

    daemon_log_val="$(_toml_get logs daemon "$CONFIG_FILE")"
    if [ -n "$daemon_log_val" ]; then
      case "$daemon_log_val" in
        /*) DAEMON_LOG="$daemon_log_val" ;;
        *) DAEMON_LOG="$REPO_ROOT/${daemon_log_val#./}" ;;
      esac
    fi

    sup_log_val="$(_toml_get logs supervisor "$CONFIG_FILE")"
    if [ -n "$sup_log_val" ]; then
      case "$sup_log_val" in
        /*) SUP_LOGFILE="$sup_log_val" ;;
        *) SUP_LOGFILE="$REPO_ROOT/${sup_log_val#./}" ;;
      esac
    fi

    director_log_val="$(_toml_get logs director "$CONFIG_FILE")"
    if [ -n "$director_log_val" ]; then
      case "$director_log_val" in
        /*) DIRECTOR_LOG="$director_log_val" ;;
        *) DIRECTOR_LOG="$REPO_ROOT/${director_log_val#./}" ;;
      esac
    fi

    hb_val="$(_toml_get runtime heartbeat_interval_seconds "$CONFIG_FILE")"
    if [ -n "$hb_val" ]; then
      HEARTBEAT_INTERVAL="$hb_val"
    fi

    # Director-specific runtime settings
    director_allow_val="$(_toml_get director allow_execute "$CONFIG_FILE")"
    if [ -n "$director_allow_val" ]; then
      DIRECTOR_ALLOW_EXECUTE="$director_allow_val"
    else
      DIRECTOR_ALLOW_EXECUTE="${DIRECTOR_ALLOW_EXECUTE:-0}"
    fi

    director_prefix_val="$(_toml_get director sandbox_branch_prefix "$CONFIG_FILE")"
    if [ -n "$director_prefix_val" ]; then
      DIRECTOR_SANDBOX_BRANCH_PREFIX="$director_prefix_val"
    else
      DIRECTOR_SANDBOX_BRANCH_PREFIX="${DIRECTOR_SANDBOX_BRANCH_PREFIX:-director/sandbox-}"
    fi

    director_interval_val="$(_toml_get director interval_seconds "$CONFIG_FILE")"
    if [ -n "$director_interval_val" ]; then
      DIRECTOR_INTERVAL_SECONDS="$director_interval_val"
    else
      DIRECTOR_INTERVAL_SECONDS="${DIRECTOR_INTERVAL_SECONDS:-60}"
    fi
  fi

  # Ensure directories exist
  mkdir -p "$RUN_DIR" "$LOG_DIR"

  export REPO_ROOT RUN_DIR LOG_DIR DAEMON_PIDFILE SUP_PIDFILE DIRECTOR_PIDFILE DAEMON_LOG SUP_LOGFILE DIRECTOR_LOG HEARTBEAT_INTERVAL DIRECTOR_ALLOW_EXECUTE DIRECTOR_SANDBOX_BRANCH_PREFIX DIRECTOR_INTERVAL_SECONDS
}
