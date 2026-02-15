# db-api (v-daemon)

This document describes the db CLI (scripts/db.sh) and how agents can interact with the local SQLite database.

Overview
--------
- scripts/db.sh: POSIX shell CLI for listing tables, querying, inserting, updating, deleting rows, creating/dropping tables, and status diagnostics.
- scripts/skills/db-api.py: small Python wrapper intended for agents to call the CLI programmatically.

Commands
--------
- list-tables: list all tables
- show-table <table>: show CREATE statement and first 50 rows
- query <SQL>: run arbitrary SQL (be careful with untrusted input)
- insert-row <table> col=val [...]: insert a row
- update-row <table> <where> col=val [...]: update rows matching WHERE
- delete-row <table> <where>: delete rows
- create-table <table> "<col_defs>": create a table
- drop-table <table>: drop table
- status: prints DB stats (size, table count, row counts, PRAGMAs, connected processes)

Agent access and usage
----------------------
- Agents should call `scripts/skills/db-api.py <command> ...` for convenience.
- Ensure the runtime user has access to the DB file (see scripts/lib/sql.sh DB_PATH and permissions).
- PRAGMAs (foreign_keys, busy_timeout) are applied by the SQL helper per-connection; callers that use sqlite3 directly should set PRAGMA foreign_keys=ON as needed.

Security and best-practices
--------------------------
- Avoid running untrusted SQL via `query`.
- Prefer parameterized access layers in code that needs more complex DB interactions.
- Rotate and archive logs regularly; consider restricting DB file permissions to the service account.

Troubleshooting
---------------
- If `sqlite3` is missing, install it (scripts/setup.sh can help).
- If WAL cannot be enabled, move the DB to a filesystem that supports WAL (notably avoid some CIFS mounts).
- If connections are blocked, check `lsof <DB_PATH>` for other processes.
