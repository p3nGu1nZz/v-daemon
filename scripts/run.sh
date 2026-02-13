#!/usr/bin/env sh
# Simple run helper: start/stop/status the daemon
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DAEMON="${SCRIPT_DIR}/daemon.sh"
PIDFILE="/tmp/v-daemon.pid"
LOGFILE="${SCRIPT_DIR}/daemon.log"

usage() {
  echo "Usage: $0 {start|stop|status|run-foreground}"
  exit 1
}

case "${1:-}" in
  start)
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
      echo "Daemon already running (PID $(cat "$PIDFILE"))"
      exit 0
    fi
    nohup sh "$DAEMON" >>"$LOGFILE" 2>&1 &
    echo $! >"$PIDFILE"
    echo "Started daemon (PID $(cat $PIDFILE))"
    ;;
  stop)
    if [ -f "$PIDFILE" ]; then
      PID=$(cat "$PIDFILE")
      if kill "$PID" 2>/dev/null; then
        rm -f "$PIDFILE"
        echo "Stopped daemon (PID $PID)"
      else
        echo "Failed to stop daemon; it may not be running"
      fi
    else
      echo "Daemon not running"
    fi
    ;;
  status)
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
      echo "Running (PID $(cat "$PIDFILE"))"
    else
      echo "Not running"
      [ -f "$PIDFILE" ] && echo "Stale PID file at $PIDFILE"
      exit 1
    fi
    ;;
  run-foreground)
    sh "$DAEMON"
    ;;
  *)
    usage
    ;;
esac
