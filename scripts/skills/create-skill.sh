#!/bin/sh
set -eu

usage() {
  echo "Usage: $0 --name SKILL_NAME [--desc DESCRIPTION] [--no-script]"
  exit 1
}

NAME=""
DESC=""
CREATE_SCRIPT=1

while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    --desc) DESC="$2"; shift 2 ;;
    --no-script) CREATE_SCRIPT=0; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

[ -n "$NAME" ] || usage

SKILL_NAME=$(printf "%s" "$NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g')

timestamp=$(date -u +"%Y%m%dT%H%M%SZ")
out="run/skills/create-skill/$timestamp"
mkdir -p "$out"

skill_dir=".github/skills/$SKILL_NAME"
skill_file="$skill_dir/SKILL.md"
script_file="scripts/skills/$SKILL_NAME.sh"

if [ -f "$skill_file" ]; then
  printf '%s\n' "skill_exists:$skill_file" >"$out/report.txt"
  cat >"$out/report.json" <<JSON
{"skill":"$SKILL_NAME","created":false,"reason":"skill_exists","path":"$skill_file"}
JSON
  echo "SKILL already exists: $skill_file"
  exit 0
fi

mkdir -p "$skill_dir"
cat > "$skill_file" <<SKILL_MD
---
name: $SKILL_NAME
description: "${DESC:-No description provided.}"
---
# SKILL: $SKILL_NAME

## Summary

Create-skill creates a new SKILL entry and optional companion helper script.

## When to run

- When adding a new SKILL to the repository.

## Inputs

- name (string) - required
- description (string) - optional
- create_script (bool) - whether to create companion script

## Outputs

- run/skills/$SKILL_NAME/<timestamp>/report.txt
- run/skills/create-skill/<timestamp>/report.json

## Implementation notes

- Created by scripts/skills/create-skill.sh
SKILL_MD

created_files="$skill_file"

if [ "$CREATE_SCRIPT" -eq 1 ]; then
  if [ -f "$script_file" ]; then
    printf '%s\n' "script_exists:$script_file" >>"$out/report.txt"
  else
    mkdir -p "$(dirname "$script_file")"
    cat > "$script_file" <<'SCRIPT_CHILD'
#!/bin/sh
set -eu
ts=$(date -u +"%Y%m%dT%H%M%SZ")
out="run/skills/REPLACE_NAME/$ts"
mkdir -p "$out"
echo "Placeholder report for skill REPLACE_NAME at $ts" >"$out/report.txt"
cat >"$out/report.json" <<JSON
{"skill":"REPLACE_NAME","timestamp":"$ts","note":"placeholder script created by create-skill"}
JSON
echo "Wrote $out/report.txt and $out/report.json"
SCRIPT_CHILD
    sed -i "s/REPLACE_NAME/$SKILL_NAME/g" "$script_file" || true
    chmod +x "$script_file"
    created_files="$created_files
$script_file"
  fi
fi

# write created files list
printf '%s\n' "$created_files" >"$out/report.txt"
files_json=$(printf '%s\n' "$created_files" | awk 'BEGIN{first=1; printf "["} {gsub(/"/,"\\\""); if (!first) printf(","); printf("\"%s\"", $0); first=0} END{print "]"}')
if [ -z "$files_json" ]; then files_json="[]"; fi
cat >"$out/report.json" <<JSON
{"skill":"$SKILL_NAME","created":true,"files":$files_json}
JSON

echo "Created skill $SKILL_NAME. See $out for details."
