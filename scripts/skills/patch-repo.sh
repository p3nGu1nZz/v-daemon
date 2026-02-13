#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/skills/patch-repo.sh [--help] [--no-push]

Automate a simple git patch workflow and capture outputs under run/skills/patch-repo/<timestamp>/.

Options:
  --help      Show this help message and exit.
  --no-push   Do not push the committed change to the remote; only create the commit locally.

Notes:
  - The commit message uses the index tree hash (git write-tree) to uniquely identify the snapshot: update:<tree-hash>
  - If the current branch has no upstream, the script will run: git push -u origin <branch>
  - This script assumes it's run from inside a git repository and that git is configured.
USAGE
}

NO_PUSH=false
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --no-push)
      NO_PUSH=true
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

# Ensure we are in a git repo
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: not inside a git repository." >&2
  exit 1
fi

# Compute root and prepare output dir for this skill run
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TIMESTAMP="$(date -u +"%Y%m%dT%H%M%SZ")"
OUTDIR="$ROOT_DIR/run/skills/patch-repo/$TIMESTAMP"
mkdir -p "$OUTDIR"

STDOUT_FILE="$OUTDIR/stdout.txt"
STDERR_FILE="$OUTDIR/stderr.txt"
CMD_FILE="$OUTDIR/command.txt"

# Save the invoked command for audit
printf '%s\n' "$0 $*" >"$CMD_FILE"

# Capture all subsequent stdout/stderr to files while still showing to console
# Use process substitution with tee (bash required)
exec > >(tee -a "$STDOUT_FILE") 2> >(tee -a "$STDERR_FILE" >&2)

echo "patch-repo starting: $TIMESTAMP"

echo "Staging all changes..."
git add .

# If there is nothing staged, exit (but still write status and report)
if git diff --cached --quiet; then
  echo "No staged changes to commit. Nothing to do."
  git --no-pager status >"$OUTDIR/status.txt" || true
  commit="$(git rev-parse --short HEAD 2>/dev/null || true)"
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  # Precompute args string and JSON-friendly pushed boolean to avoid nested command substitutions
args_string="$(printf '%s ' "$@" | sed -e 's/"/\"/g')"
if [ "$pushed" = true ]; then
  pushed_json=true
else
  pushed_json=false
fi
cat >"$OUTDIR/report.json" <<JSON
{
  "timestamp": "$TIMESTAMP",
  "script": "scripts/skills/patch-repo.sh",
  "args": "$(printf '%s ' "$@" | sed -e "s/\\"/\\\\\"/g")",
  "exit_code": 0,
  "commit": "$commit",
  "branch": "$branch",
  "message": "no changes"
}
JSON
  exit 0
fi

# Create a tree object hash from the current index to use in the commit message
echo "Computing tree hash for current index..."
if ! tree_hash=$(git write-tree 2>/dev/null); then
  echo "Error: failed to write tree." >&2
  # write status and report
  git --no-pager status >"$OUTDIR/status.txt" || true
  cat >"$OUTDIR/report.json" <<JSON
{
  "timestamp": "$TIMESTAMP",
  "script": "scripts/skills/patch-repo.sh",
  "args": "$(printf '%s ' "$@" | sed -e "s/\\"/\\\\\"/g")",
  "exit_code": 1,
  "error": "failed to write tree"
}
JSON
  exit 1
fi

commit_msg="update:${tree_hash}"

# Create the commit
echo "Committing with message: $commit_msg"
if ! git commit -m "$commit_msg"; then
  echo "git commit failed." >&2
  git --no-pager status >"$OUTDIR/status.txt" || true
  cat >"$OUTDIR/report.json" <<JSON
{
  "timestamp": "$TIMESTAMP",
  "script": "scripts/skills/patch-repo.sh",
  "args": "$(printf '%s ' "$@" | sed -e "s/\\"/\\\\\"/g")",
  "exit_code": 1,
  "error": "git commit failed"
}
JSON
  exit 1
fi

new_commit_short=$(git rev-parse --short HEAD)

echo "Created commit $new_commit_short"

pushed=false
if [ "$NO_PUSH" = "true" ]; then
  echo "Created commit $new_commit_short (not pushed)."
else
  # Push to upstream (or set upstream if missing)
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || true)
  if [ -z "$upstream" ]; then
    echo "No upstream configured for branch '$current_branch'. Pushing and setting upstream to origin/$current_branch..."
    if git push -u origin "$current_branch"; then
      pushed=true
    else
      echo "git push failed." >&2
    fi
  else
    echo "Pushing to upstream..."
    if git push; then
      pushed=true
    else
      echo "git push failed." >&2
    fi
  fi
fi

pushed_commit_short=$(git rev-parse --short HEAD)

git --no-pager status >"$OUTDIR/status.txt" || true

commit="$(git rev-parse --short HEAD 2>/dev/null || true)"
branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
exit_code=0

# Write a structured JSON report
cat >"$OUTDIR/report.json" <<JSON
{
  "timestamp": "$TIMESTAMP",
  "script": "scripts/skills/patch-repo.sh",
  "args": "$(printf '%s ' "$@" | sed -e "s/\\"/\\\\\"/g")",
  "exit_code": $exit_code,
  "commit": "$commit",
  "branch": "$branch",
  "pushed": $pushed_json,
  "stdout": "$STDOUT_FILE",
  "stderr": "$STDERR_FILE",
  "status_file": "$OUTDIR/status.txt"
}
JSON

# Human-friendly summary
if [ "$pushed" = true ]; then
  echo "Pushed commit: $pushed_commit_short"
else
  echo "Created commit $new_commit_short (not pushed)."
fi

echo "Outputs written to: $OUTDIR"

exit $exit_code
