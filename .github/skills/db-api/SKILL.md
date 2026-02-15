---
name: db-api
description: >-
  The db-api skill exposes the repository's SQLite database to agents via a lightweight CLI (scripts/db.sh) and a small Python wrapper (scripts/skills/db-api.py). Use this skill for safe, read-first operations and limited CRUD tasks when a full service layer is not available.
---

# db-api skill

The db-api skill exposes the repository's SQLite database to agents via a lightweight CLI (scripts/db.sh) and a small Python wrapper (scripts/skills/db-api.py). Use this skill for safe, read-first operations and limited CRUD tasks when a full service layer is not available.

## Usage

- scripts/skills/db-api.py list-tables
- scripts/skills/db-api.py status
- scripts/skills/db-api.py show-table todos
- scripts/skills/db-api.py view todos [limit|'all'] [format]    # formats: pretty (default), raw, csv
- scripts/skills/db-api.py view todos all pretty
- scripts/skills/db-api.py view todos 10 csv
- scripts/skills/db-api.py query "SELECT count(*) FROM todos;"

## Output formats and status fields

- view: supports three output formats:
  - pretty: sqlite3 -header -column (human-friendly table with column headers)
  - raw: pipe-delimited values without headers (good for scripting)
  - csv: header + CSV output
- status: prints the following fields to aid agents and operators:
  - DB_PATH, size, last_modified, last_access
  - tables: list of table names
  - table_row_counts: per-table counts
  - table_count: total number of tables
  - PRAGMA values: journal_mode, foreign_keys, busy_timeout
  - connected_processes: lsof output if available

## Troubleshooting

- Ensure sqlite3 is installed and scripts/lib/sql.sh DB_PATH points to the expected DB file (default: run/v-daemon.db).
- If WAL cannot be enabled, move the DB to a WAL-capable filesystem (avoid certain CIFS mounts).
- PRAGMA settings like foreign_keys must be applied per-connection; scripts/lib/sql.sh sets sensible defaults per run.
- Check run/system.log and logs/sql-agent.log for initialization and errors.

## Notes

- Do not run untrusted SQL via the `query` endpoint; treat it as an administrative capability.
- For complex or high-frequency DB work, implement a dedicated service layer rather than giving agents direct SQL access.
- See docs/db-api.md and docs/db-api-spec.md for full reference and examples.
