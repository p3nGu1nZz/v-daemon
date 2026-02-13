#!/usr/bin/env sh
# Lightweight test runner for repository scripts. Supports --sql to run SQLite smoke test.
set -eu

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  cat <<'USAGE'
Usage: sh scripts/test.sh [--sql]

Runs repository tests; --sql runs the sqlite smoke test (default behavior is to run SQL tests).
USAGE
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd || printf '%s' "$(pwd)")"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd || printf '%s' "$(pwd)")"

# Load env and sql helpers if present
if [ -f "$REPO_ROOT/scripts/lib/env.sh" ]; then
  . "$REPO_ROOT/scripts/lib/env.sh"
fi
if [ -f "$REPO_ROOT/scripts/lib/sql.sh" ]; then
  . "$REPO_ROOT/scripts/lib/sql.sh"
else
  echo "scripts/lib/sql.sh not found; cannot run SQL tests" >&2
  exit 2
fi

# parse args
RUN_SQL=0
RUN_DIRECTOR=0
for arg in "$@"; do
  case "$arg" in
    --sql)
      RUN_SQL=1
      ;;
    --director)
      RUN_DIRECTOR=1
      ;;
    --help|-h)
      ;;
    *)
      ;;
  esac
done

# Default: run SQL tests by default unless a different test is explicitly requested
if [ "$RUN_SQL" -eq 0 ] && [ "$RUN_DIRECTOR" -eq 0 ]; then
  RUN_SQL=1
fi

if [ "$RUN_SQL" -eq 1 ]; then
  if ! sql_check; then
    echo "sqlite3 CLI not found; sql tests skipped" >&2
    exit 1
  fi
  sql_init || { echo "sql_init failed" >&2; exit 1; }
  id="test-sql-$(date +%s)"
  sql_insert_todo "$id" "test-sql" "automated sql test" "pending"
  id_esc=$(escape_sql "$id")
  out=$(sql_query "SELECT id FROM todos WHERE id='$id_esc' LIMIT 1;")
  if [ "$(printf "%s" "$out")" = "$id" ]; then
    echo "SQL smoke test passed: $id"
  else
    echo "SQL smoke test failed" >&2
    exit 3
  fi
fi

if [ "$RUN_DIRECTOR" -eq 1 ]; then
  if [ -f "$REPO_ROOT/scripts/tests/test-director-hfsm.sh" ]; then
    sh "$REPO_ROOT/scripts/tests/test-director-hfsm.sh"
    exit $?
  else
    echo "Director test script missing: $REPO_ROOT/scripts/tests/test-director-hfsm.sh" >&2
    exit 2
  fi
fi

echo "No tests to run"