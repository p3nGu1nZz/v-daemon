#!/bin/sh
set -eu

usage() {
  echo "Usage: $0 --name AGENT_NAME [--desc DESCRIPTION] [--no-script]"
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

AGENT_NAME=$(printf "%s" "$NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g')
timestamp=$(date -u +"%Y%m%dT%H%M%SZ")
out="run/skills/create-agent/$timestamp"
mkdir -p "$out"

agent_dir=".github/agents"
agent_file="$agent_dir/${AGENT_NAME}.agent.md"
script_file="scripts/agents/${AGENT_NAME}.sh"

if [ -f "$agent_file" ]; then
  printf '%s\n' "agent_exists:$agent_file" >"$out/report.txt"
  cat >"$out/report.json" <<JSON
{"agent":"$AGENT_NAME","created":false,"reason":"agent_exists","path":"$agent_file"}
JSON
  echo "Agent already exists: $agent_file"
  exit 0
fi

mkdir -p "$agent_dir"
cat > "$agent_file" <<AGENT_MD
---
name: $AGENT_NAME
description: "${DESC:-No description provided.}"
type: agent
entrypoint: "$script_file"
---
# Agent: $AGENT_NAME

Purpose:
- ${DESC:-No description provided.}

Notes:
- This file was scaffolded by scripts/skills/create-agent.sh
- Implement agent behavior in $script_file
AGENT_MD

created="$agent_file"

if [ "$CREATE_SCRIPT" -eq 1 ]; then
  mkdir -p "$(dirname "$script_file")"
  if [ ! -f "$script_file" ]; then
    cat > "$script_file" <<AG_SCRIPT
#!/bin/sh
set -eu
echo "Agent $AGENT_NAME placeholder script"
AG_SCRIPT
    chmod +x "$script_file" || true
    created="$created\n$script_file"
  fi
fi

printf '%s\n' "$created" >"$out/report.txt"
files_json=$(printf '%s\n' "$created" | awk 'BEGIN{first=1; printf "["} {gsub(/\"/,"\\\""); if (!first) printf(","); printf("\"%s\"", $0); first=0} END{print "]"}')
cat >"$out/report.json" <<JSON
{"agent":"$AGENT_NAME","created":true,"files":$files_json}
JSON

echo "Created agent $AGENT_NAME. See $out for details."