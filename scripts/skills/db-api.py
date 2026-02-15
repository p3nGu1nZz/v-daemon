#!/usr/bin/env python3
"""
Simple wrapper for scripts/db.sh to be used by agent skills.
Usage: scripts/skills/db-api.py <command> [args...]
"""
import os
import sys
import subprocess

def main():
    here = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.abspath(os.path.join(here, '..', '..'))
    dbsh = os.path.join(repo_root, 'scripts', 'db.sh')
    if not os.path.exists(dbsh):
        print(f"db.sh not found at {dbsh}", file=sys.stderr)
        return 2
    if len(sys.argv) <= 1:
        print("Usage: db-api.py <command> [args...]")
        print("Examples: list-tables, status, show-table <table>, view <table> [limit|'all'] [format], query <SQL>")
        return 2
    cmd = [dbsh] + sys.argv[1:]
    try:
        p = subprocess.run(cmd, check=False, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        print(p.stdout, end='')
        return p.returncode
    except Exception as e:
        print(f"Error running db.sh: {e}", file=sys.stderr)
        return 1

if __name__ == '__main__':
    sys.exit(main())
