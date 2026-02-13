#!/bin/sh
set -eu

usage() { echo "Usage: $0 [--summary_path PATH] [--max-tasks N] [--output json|text]"; exit 1; }
SUMMARY_PATH=""
MAX_TASKS=6
OUT_FMT="text"

while [ $# -gt 0 ]; do
  case "$1" in
    --summary_path) SUMMARY_PATH="$2"; shift 2 ;;
    --max-tasks) MAX_TASKS="$2"; shift 2 ;;
    --output) OUT_FMT="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) shift ;;
  esac
done

if [ -z "$SUMMARY_PATH" ]; then
  # find latest summary.json
  SUMMARY_PATH=$(printf "%s\n" run/skills/review-repo/*/summary.json 2>/dev/null | head -n1 || true)
fi

timestamp=$(date -u +"%Y%m%dT%H%M%SZ")
out="run/skills/next-steps/$timestamp"
mkdir -p "$out"

# build a couple of default tasks
cat >"$out/tasks.json" <<EOF
[
  { "id":"add-skill-scripts", "title":"Add helper scripts for SKILLs", "description":"Ensure each SKILL.md has a companion scripts/skills/<name>.sh that emits outputs to run/skills/<name>/<timestamp>/ (automated generator exists)", "priority":1, "estimate":"1h", "files":["scripts/skills/"], "branch":"chore/add-skill-scripts", "commit_msg":"chore(skills): add helper scripts for skills" },
  { "id":"add-ci-setup-check", "title":"Add CI job to run scripts/setup.sh --check", "description":"Add a CI workflow that runs scripts/setup.sh --check to validate environment and prevent regressions.", "priority":2, "estimate":"2h", "files":["scripts/setup.sh", ".github/workflows/"], "branch":"chore/add-ci-setup-check", "commit_msg":"chore(ci): add workflow to run scripts/setup.sh --check" }
]
EOF

# human text
{
  echo "Generated next-steps (defaults):"
  printf "1. Add helper scripts for SKILLs - chore/add-skill-scripts (estimate: 1h)\n"
  printf "2. Add CI job to run scripts/setup.sh --check - chore/add-ci-setup-check (estimate: 2h)\n"
} >"$out/tasks.txt"

if [ "$OUT_FMT" = "json" ]; then
  cat "$out/tasks.json"
else
  cat "$out/tasks.txt"
fi

echo "Wrote outputs to $out"
