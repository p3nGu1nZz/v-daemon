#!/usr/bin/env sh
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Use an isolated audits dir for the test to avoid interference from any running Director
TMP_AUDITS_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t vdaemon_audits)
export DEV_AUDITS_DIR="$TMP_AUDITS_DIR"
LOCKDIR="$DEV_AUDITS_DIR/director-summary.lock"
mkdir -p "$DEV_AUDITS_DIR"
# start a background sleep process owned by current user
sleep 300 &
SLEEP_PID=$!
# create a stale lock pointing at the sleep pid (ensure lock.ts is slightly newer than process start)
rm -rf "$LOCKDIR"
mkdir -p "$LOCKDIR"
echo "$SLEEP_PID" > "$LOCKDIR/pid"
# give the process a moment so its start time predates the lock
sleep 1
# set lock timestamp to now then backdate 1 second so owner_age > 0 but proc start <= lock_ts
date -u +'%Y-%m-%dT%H:%M:%SZ' > "$LOCKDIR/ts"
if touch -d '1 second ago' "$LOCKDIR/ts" 2>/dev/null; then :; fi
ps -p "$SLEEP_PID" -o args= 2>/dev/null > "$LOCKDIR/cmdline" 2>/dev/null || true
# Make the stale threshold zero so actions.sh will attempt cleanup immediately
export DIRECTOR_LOCK_STALE_SECONDS=0
export DIRECTOR_LOCK_WAIT_SECONDS=1
# Run the autopilot summary which should detect and clean the stale lock
sh "$REPO_ROOT/scripts/lib/actions.sh" run || true
# Validate results - ensure the owner process was terminated; the lockdir may be re-acquired by this run, so don't require it to be absent
# Check that the background sleep was terminated
if kill -0 "$SLEEP_PID" 2>/dev/null; then
  echo "FAIL: owner PID $SLEEP_PID still alive"
  # cleanup
  rm -rf "$LOCKDIR" 2>/dev/null || true
  kill -9 "$SLEEP_PID" 2>/dev/null || true
  exit 2
fi
# cleanup any leftover lockdir
rm -rf "$LOCKDIR" 2>/dev/null || true
echo "PASS: owner process terminated and stale lock handled"
exit 0
