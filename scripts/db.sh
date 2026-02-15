#!/usr/bin/env sh
# db.sh - Simple DB CLI for v-daemon
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SQL_SH="$REPO_ROOT/scripts/lib/sql.sh"

if [ -f "$SQL_SH" ]; then
  # shellcheck disable=SC1090
  . "$SQL_SH"
else
  echo "Missing $SQL_SH; aborting" >&2
  exit 1
fi

usage() {
  cat <<'USAGE'
Usage: sh scripts/db.sh <command> [args...]

Commands:
  list-tables
  show-table <table>
  view <table> [limit|'all'] [format]    # format: pretty (default), raw, csv; default limit 100
  query <SQL>
  insert-row <table> col=val [col=val ...]
  update-row <table> <where> col=val [col=val ...]
  delete-row <table> <where>
  create-table <table> "<col_defs>"
  drop-table <table>
  status
  help
USAGE
}

die() { echo "$*" >&2; exit 1; }

cmd="${1:-}"
case "$cmd" in
  ""|help)
    usage
    exit 0
    ;;
  list-tables)
    sql_check || die "sqlite3 not available"
    sql_run "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;"
    ;;
  show-table)
    table="$2"
    [ -n "$table" ] || die "usage: show-table <table>"
    sql_check || die "sqlite3 not available"
    sql_run "SELECT sql FROM sqlite_master WHERE type='table' AND name='${table}';"
    echo "---- rows (first 50) ----"
    sql_run "SELECT * FROM \"${table}\" LIMIT 50;" pretty
    ;;
  view)
    table="$2"
    limit="${3:-100}"
    format="${4:-pretty}"
    [ -n "$table" ] || die "usage: view <table> [limit|'all'] [format]"
    sql_check || die "sqlite3 not available"
    # Prepare SQL (respect 'all' or numeric limit)
    if [ "$limit" = "all" ]; then
      sql="SELECT * FROM \"${table}\";"
    else
      case "$limit" in
        *[!0-9]*) die "limit must be a positive integer or 'all'" ;;
      esac
      sql="SELECT * FROM \"${table}\" LIMIT ${limit};"
    fi
    # Dispatch output format
    case "$format" in
      pretty)
        sql_run "$sql" pretty
        ;;
      raw)
        sql_run "$sql" raw
        ;;
      csv)
        printf '%s\n' "$sql" | "$SQLITE_BIN" "$DB_PATH" -header -csv
        ;;
      *)
        die "unknown format: $format (supported: pretty, raw, csv)"
        ;;
    esac
    ;;


  query)
    shift || true
    sql="$*"
    [ -n "$sql" ] || die "query requires SQL"
    sql_check || die "sqlite3 not available"
    sql_run "$sql"
    ;;
  insert-row)
    table="$2"
    shift 2 || true
    [ -n "$table" ] || die "usage: insert-row <table> col=val..."
    cols=""
    vals=""
    for kv in "$@"; do
      case "$kv" in
        *=*)
          col="${kv%%=*}"
          val="${kv#*=}"
          val_esc=$(escape_sql "$val")
          if [ -z "$cols" ]; then
            cols="$col"
            vals="'$val_esc'"
          else
            cols="$cols, $col"
            vals="$vals, '$val_esc'"
          fi
          ;;
        *) ;;
      esac
    done
    [ -n "$cols" ] || die "no columns provided"
    sql_run "INSERT INTO \"${table}\" (${cols}) VALUES (${vals});"
    ;;
  update-row)
    table="$2"; where="$3"
    shift 3 || true
    [ -n "$table" -a -n "$where" ] || die "usage: update-row <table> <where> col=val..."
    sets=""
    for kv in "$@"; do
      case "$kv" in
        *=*)
          col="${kv%%=*}"
          val="${kv#*=}"
          val_esc=$(escape_sql "$val")
          if [ -z "$sets" ]; then
            sets="$col='$val_esc'"
          else
            sets="$sets, $col='$val_esc'"
          fi
          ;;
      esac
    done
    [ -n "$sets" ] || die "no columns provided"
    sql_run "UPDATE \"${table}\" SET ${sets} WHERE ${where};"
    ;;
  delete-row)
    table="$2"; where="$3"
    [ -n "$table" -a -n "$where" ] || die "usage: delete-row <table> <where>"
    sql_run "DELETE FROM \"${table}\" WHERE ${where};"
    ;;
  create-table)
    table="$2"; shift 2 || true
    schema="$*"
    [ -n "$table" -a -n "$schema" ] || die "usage: create-table <table> \"col defs\""
    sql_run "CREATE TABLE IF NOT EXISTS \"${table}\" (${schema});"
    ;;
  drop-table)
    table="$2"
    [ -n "$table" ] || die "usage: drop-table <table>"
    sql_run "DROP TABLE IF EXISTS \"${table}\";"
    ;;
  status)
    sql_check || die "sqlite3 not available"
    echo "DB_PATH=${DB_PATH}"
    if [ -f "$DB_PATH" ]; then
      du -h "$DB_PATH" | awk '{print "size: "$1}'
      echo "last_modified: $(stat -c %y "$DB_PATH" 2>/dev/null || echo N/A)"
      echo "last_access: $(stat -c %x "$DB_PATH" 2>/dev/null || echo N/A)"
    fi
    echo "tables:"
    sql_run "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;"
    echo "table_row_counts:"
    for t in $(sql_run "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;"); do
      cnt=$(sql_run "SELECT count(*) FROM \"${t}\";" 2>/dev/null || echo "0")
      echo "  ${t}: ${cnt}"
    done
    echo "table_count: $(sql_run "SELECT count(*) FROM sqlite_master WHERE type='table';")"
    journal_mode_val=$("$SQLITE_BIN" "$DB_PATH" -batch -noheader "PRAGMA journal_mode;" 2>/dev/null || true)
    echo "journal_mode: $journal_mode_val"
    foreign_keys_val=$("$SQLITE_BIN" "$DB_PATH" -batch -noheader "PRAGMA foreign_keys;" 2>/dev/null || true)
    echo "foreign_keys: $foreign_keys_val"
    busy_timeout_val=$("$SQLITE_BIN" "$DB_PATH" -batch -noheader "PRAGMA busy_timeout;" 2>/dev/null || true)
    echo "busy_timeout: $busy_timeout_val"
    if command -v lsof >/dev/null 2>&1; then
      echo "connected_processes:"
      lsof "$DB_PATH" 2>/dev/null | sed -n '2,$p' || true
    else
      echo "connected_processes: lsof not available"
    fi
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    usage
    exit 2
    ;;
esac
