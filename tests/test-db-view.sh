#!/usr/bin/env sh
set -eu

TMPDIR=$(mktemp -d)
export SQL_DB_PATH="$TMPDIR/v-daemon.db"
export DB_DIR="$TMPDIR"
export SQLITE_BIN="${SQLITE_BIN:-$(command -v sqlite3 || true)}"

# Create table schema
sh scripts/db.sh create-table todos "id TEXT PRIMARY KEY, title TEXT NOT NULL, description TEXT, status TEXT DEFAULT 'pending', created_at TEXT, updated_at TEXT"

# Insert rows
sh scripts/db.sh insert-row todos id=autotest-1 title=auto description=auto status=pending
sh scripts/db.sh insert-row todos id=autotest-2 title=auto2 description=auto status=pending

# Capture and verify view output
out=$(sh scripts/db.sh view todos all)

printf '%s\n' "$out" | grep -q "autotest-1" || (printf 'autotest-1 missing\n' >&2; exit 2)
printf '%s\n' "$out" | grep -q "autotest-2" || (printf 'autotest-2 missing\n' >&2; exit 2)

printf 'OK\n'
