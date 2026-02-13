#!/usr/bin/env sh
# Create director-related todos in the SQLite DB via scripts/lib/sql.sh
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SQL_SH="$REPO_ROOT/scripts/lib/sql.sh"
if [ ! -f "$SQL_SH" ]; then
  echo "sql helper missing: $SQL_SH" >&2
  exit 1
fi
# shellcheck disable=SC1090
. "$SQL_SH"

sql_init || { echo "sql_init failed or sqlite3 not available" >&2; exit 1; }

# Insert todos: id, title, description, status
sql_insert_todo "director-structured-logging" "Add structured state start/end audit logs in director" "Implement audit_state_start/audit_state_end JSON logs for director" "done"
sql_insert_todo "director-timeouts" "Add timeouts to external skill invocations" "Wrap skill calls with timeout wrapper (timeout or portable fallback)" "done"
sql_insert_todo "director-conditional-transitions" "Make patch_repo failures skip merge_up" "If patch-repo fails, skip merge_up and backoff" "done"
sql_insert_todo "director-backoff-retry" "Implement backoff for failed patch attempts" "Increase sleep on consecutive patch-repo failures" "done"
sql_insert_todo "director-adopt-hfsm" "Adopt hfsm.sh for director state machine" "Refactor director to use hfsm.sh API for enter/exit/handlers" "pending"

printf '%s\n' "Inserted director todos into $DB_PATH"
sql_list_todos || true
