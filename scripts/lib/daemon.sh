#!/usr/bin/env sh
# Minimal daemon loop. Replace loop body with self-improving logic later.
set -eu

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  cat <<'USAGE'
Usage: sh scripts/lib/daemon.sh

Minimal daemon loop that writes heartbeat to ./logs/daemon.log and PID to /tmp/v-daemon.pid.
Intended to be managed by scripts/run.sh supervisor.
USAGE
  exit 0
fi

PIDFILE="/tmp/v-daemon.pid"
trap 'rm -f "$PIDFILE"; exit 0' INT TERM EXIT
echo $$ >"$PIDFILE"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Repo root is two levels up from scripts/lib
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
mkdir -p "$REPO_ROOT/logs"
LOGFILE="${REPO_ROOT}/logs/daemon.log"

while true; do
  printf '%s: heartbeat\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >>"$LOGFILE"
  # TODO: insert build / test / self-update steps here
  sleep 60
done
