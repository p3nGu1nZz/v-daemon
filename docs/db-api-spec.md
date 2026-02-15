# db.sh CLI Specification (v-daemon)

## Overview

Location: scripts/db.sh
Wrapper: scripts/skills/db-api.py (Python)
Shell wrapper: scripts/skills/db-api.sh

Purpose: Provide a simple CLI for listing tables, querying, and performing limited CRUD operations against the repository SQLite DB (run/v-daemon.db by default).

## Commands and behavior

- list-tables
  - Description: list all tables in the DB
  - Output: one table name per line

- show-table <table>
  - Description: shows CREATE SQL for the table and prints first 50 rows
  - Output: CREATE TABLE statement, then a separator, then rows

- query <SQL>
  - Description: run arbitrary SQL (administrative; avoid untrusted input)
  - Output: sqlite3 formatted output

- insert-row <table> col=val [...]
  - Description: insert a single row using provided column/value pairs

- update-row <table> <where> col=val [...]
  - Description: update rows matching WHERE clause

- delete-row <table> <where>
  - Description: delete rows matching WHERE clause

- create-table <table> "<col_defs>"
  - Description: create table with column definitions, e.g. "id TEXT PRIMARY KEY, name TEXT"

- drop-table <table>
  - Description: drop table if exists

- status
  - Description: prints DB path, size, last modified/access, tables, per-table row counts, PRAGMA status (journal_mode, foreign_keys, busy_timeout), and connected processes (via lsof if available)

## PRAGMA and safety notes

- scripts/lib/sql.sh applies per-connection PRAGMAs (attempts WAL, enables foreign_keys and sets busy_timeout). PRAGMA values are not global across separate sqlite3 invocations; callers should set PRAGMA foreign_keys=ON when using sqlite3 directly.

- Do not execute untrusted SQL via the `query` command; prefer parameterized programmatic access for complex operations.

## Examples

- List tables:
  sh scripts/db.sh list-tables

- Insert a todo:
  sh scripts/db.sh insert-row todos id=todo-123 title='Example' description='...' status=pending

- Show status:
  sh scripts/db.sh status

## Acceptance criteria / tests

- `list-tables` returns at least `todos` and `todo_deps` after initialization.
- `insert-row` then `update-row` then `delete-row` operate as expected and change the count reported by `status`.
- `status` reports a non-empty table_count and sensible PRAGMA values or warnings when PRAGMAs cannot be set.

## Security

- Limit usage of the `query` command to trusted operators or agent workflows with proper authorization checks.
- Consider adding an ACL around scripts/db.sh for production deployments.
