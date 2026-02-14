#!/usr/bin/env sh
# Lightweight sqlite3 helper library for v-daemon shell scripts.
# Provides simple helpers for initializing a SQLite DB and basic todo/todo_deps operations.
# Requires sqlite3 CLI. scripts/setup.sh will attempt to install sqlite3 when asked.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

DB_DIR="${DB_DIR:-$REPO_ROOT/run}"
DB_PATH="${SQL_DB_PATH:-$DB_DIR/v-daemon.db}"
SQLITE_BIN="${SQLITE_BIN:-$(command -v sqlite3 || true)}"

# Check sqlite3 is available
sql_check() {
  if [ -z "${SQLITE_BIN:-}" ]; then
    SQLITE_BIN="$(command -v sqlite3 || true)"
  fi
  if [ -z "${SQLITE_BIN:-}" ]; then
    echo "sqlite3 CLI not found. Please install sqlite3 and retry." >&2
    return 1
  fi
  return 0
}

# Escape single quotes for SQL literals
escape_sql() {
  printf '%s' "$1" | sed "s/'/''/g"
}

# Run a SQL statement against the DB and print results (no header, list mode)
sql_run() {
  sql="$1"
  sql_check || return 1
  mkdir -p "$(dirname "$DB_PATH")"
  # Ensure WAL for better concurrency; run the PRAGMA quietly to avoid printing its result
  printf '%s\n' "PRAGMA journal_mode=WAL;" | "$SQLITE_BIN" "$DB_PATH" -batch -noheader >/dev/null 2>&1
  printf '%s\n' "$sql" | "$SQLITE_BIN" "$DB_PATH" -batch -noheader
}

# Create schema for todos and dependencies
sql_create_schema() {
  sql_check || return 1
  mkdir -p "$(dirname "$DB_PATH")"
  cat <<'SQL' | "$SQLITE_BIN" "$DB_PATH"
BEGIN;
CREATE TABLE IF NOT EXISTS todos (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT,
  status TEXT DEFAULT 'pending',
  created_at TEXT,
  updated_at TEXT
);
CREATE TABLE IF NOT EXISTS todo_deps (
  todo_id TEXT,
  depends_on TEXT,
  PRIMARY KEY (todo_id, depends_on)
);
COMMIT;
SQL
}

# Insert or replace a todo item
sql_insert_todo() {
  id="$1"
  title="$2"
  description="${3:-}"
  status="${4:-pending}"
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  id_esc=$(escape_sql "$id")
  title_esc=$(escape_sql "$title")
  desc_esc=$(escape_sql "$description")
  sql_run "INSERT OR REPLACE INTO todos (id, title, description, status, created_at, updated_at) VALUES ('$id_esc','$title_esc','$desc_esc','$status','$now','$now');"
}

# Update status for existing todo
sql_update_todo_status() {
  id="$1"; status="$2"
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  id_esc=$(escape_sql "$id")
  status_esc=$(escape_sql "$status")
  sql_run "UPDATE todos SET status='$status_esc', updated_at='$now' WHERE id='$id_esc';"
}

# List todos (optionally filter by status)
sql_list_todos() {
  status="${1:-}"
  if [ -n "$status" ]; then
    status_esc=$(escape_sql "$status")
    sql_run "SELECT id, title, status, created_at, updated_at FROM todos WHERE status='$status_esc' ORDER BY created_at DESC;"
  else
    sql_run "SELECT id, title, status, created_at, updated_at FROM todos ORDER BY created_at DESC;"
  fi
}

# Add a dependency relationship
sql_add_dep() {
  todo_id="$1"; depends_on="$2"
  todo_id_esc=$(escape_sql "$todo_id")
  dep_esc=$(escape_sql "$depends_on")
  sql_run "INSERT OR IGNORE INTO todo_deps (todo_id, depends_on) VALUES ('$todo_id_esc','$dep_esc');"
}

# Generic query helper (prints raw sqlite3 output)
sql_query() {
  sql_run "$1"
}

# Initialize DB and schema (safe to call multiple times)
sql_init() {
  sql_check || return 1
  mkdir -p "$(dirname "$DB_PATH")"
  # Touch DB to ensure file exists
  "$SQLITE_BIN" "$DB_PATH" ".databases" >/dev/null 2>&1 || true
  sql_create_schema || return 1
}

# End of sql.sh
