#!/usr/bin/env sh
# Test: start a director instance with isolated RUN_DIR and verify HFSM audit events
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEST_RUN_DIR="$REPO_ROOT/run/test-director-$(date +%s)"
TEST_LOG_DIR="$REPO_ROOT/logs/test-director-$(date +%s)"
mkdir -p "$TEST_RUN_DIR" "$TEST_LOG_DIR"
export RUN_DIR="$TEST_RUN_DIR"
export LOG_DIR="$TEST_LOG_DIR"

# Use a test-local audits dir so tests don't interfere with a running director
TEST_AUDITS_DIR="$TEST_RUN_DIR/audits"
mkdir -p "$TEST_AUDITS_DIR"
export DEV_AUDITS_DIR="$TEST_AUDITS_DIR"

# Start director in background
nohup bash "$REPO_ROOT/scripts/lib/director.sh" >/dev/null 2>&1 &
PID=$!

AUDITS="$DEV_AUDITS_DIR/director-heartbeats.jsonl"
WAIT=0
FOUND=0
# wait up to 15s for at least one state_start audit
while [ $WAIT -lt 15 ]; do
  if [ -f "$AUDITS" ] && grep -q '"event":"state_start"' "$AUDITS" 2>/dev/null; then
    FOUND=1
    break
  fi
  sleep 1
  WAIT=$((WAIT+1))
done

# Tear down
kill "$PID" 2>/dev/null || true
sleep 0.5
rm -rf "$TEST_RUN_DIR" "$TEST_LOG_DIR" 2>/dev/null || true

if [ "$FOUND" -eq 1 ]; then
  echo "Director HFSM test passed"
  exit 0
else
  echo "Director HFSM test failed: no state_start events detected" >&2
  exit 2
fi
