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

# Start director in background (bash invocation)
nohup bash "$REPO_ROOT/scripts/lib/director.sh" >/dev/null 2>&1 &
PID=$!

AUDITS="$DEV_AUDITS_DIR/director-heartbeats.jsonl"
WAIT=0
FOUND1=0
# wait up to 15s for at least one state_start audit
while [ $WAIT -lt 15 ]; do
  if [ -f "$AUDITS" ] && grep -q '"event":"state_start"' "$AUDITS" 2>/dev/null; then
    FOUND1=1
    break
  fi
  sleep 1
  WAIT=$((WAIT+1))
done

# Tear down first run
kill "$PID" 2>/dev/null || true
sleep 0.5
rm -rf "$TEST_RUN_DIR" "$TEST_LOG_DIR" 2>/dev/null || true

# Second run: test invoking via 'sh' to exercise re-exec-to-bash path
TEST_RUN_DIR2="$REPO_ROOT/run/test-director-sh-$(date +%s)"
TEST_LOG_DIR2="$REPO_ROOT/logs/test-director-sh-$(date +%s)"
mkdir -p "$TEST_RUN_DIR2" "$TEST_LOG_DIR2"
export RUN_DIR="$TEST_RUN_DIR2"
export LOG_DIR="$TEST_LOG_DIR2"
TEST_AUDITS_DIR2="$TEST_RUN_DIR2/audits"
mkdir -p "$TEST_AUDITS_DIR2"
export DEV_AUDITS_DIR="$TEST_AUDITS_DIR2"

# Start director using sh (should re-exec to bash inside the script)
nohup sh "$REPO_ROOT/scripts/lib/director.sh" >/dev/null 2>&1 &
PID2=$!

AUDITS2="$DEV_AUDITS_DIR/director-heartbeats.jsonl"
WAIT=0
FOUND2=0
# wait up to 15s for at least one state_start audit
while [ $WAIT -lt 15 ]; do
  if [ -f "$AUDITS2" ] && grep -q '"event":"state_start"' "$AUDITS2" 2>/dev/null; then
    FOUND2=1
    break
  fi
  sleep 1
  WAIT=$((WAIT+1))
done

# Tear down second run
kill "$PID2" 2>/dev/null || true
sleep 0.5
rm -rf "$TEST_RUN_DIR2" "$TEST_LOG_DIR2" 2>/dev/null || true

if [ "$FOUND1" -eq 1 ] && [ "$FOUND2" -eq 1 ]; then
  echo "Director HFSM test passed (bash + sh invocation)"
  exit 0
else
  echo "Director HFSM test failed: bash_found=$FOUND1 sh_found=$FOUND2" >&2
  exit 2
fi
