#!/usr/bin/env sh
# Minimal daemon loop. Replace loop body with self-improving logic later.
set -eu

PIDFILE="/tmp/v-daemon.pid"
trap 'rm -f "$PIDFILE"; exit 0' INT TERM EXIT
echo $$ >"$PIDFILE"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGFILE="${SCRIPT_DIR}/daemon.log"

while true; do
  printf '%s: heartbeat\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >>"$LOGFILE"
  # TODO: insert build / test / self-update steps here
  sleep 60
done
