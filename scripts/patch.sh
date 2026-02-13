#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: patches.sh [--help] [--no-push]

Automate a simple git patch workflow:
  1. git add .
  2. git commit -m "update:<tree-hash>"
  3. git push (unless --no-push)

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

# Stage everything
echo "Staging all changes..."
git add .

# If there is nothing staged, exit
if git diff --cached --quiet; then
  echo "No staged changes to commit. Nothing to do."
  exit 0
fi

# Create a tree object hash from the current index to use in the commit message
echo "Computing tree hash for current index..."
if ! tree_hash=$(git write-tree 2>/dev/null); then
  echo "Error: failed to write tree." >&2
  exit 1
fi

commit_msg="update:${tree_hash}"

# Create the commit
echo "Committing with message: $commit_msg"
if ! git commit -m "$commit_msg"; then
  echo "git commit failed." >&2
  exit 1
fi

new_commit_short=$(git rev-parse --short HEAD)

if [ "$NO_PUSH" = "true" ]; then
  echo "Created commit $new_commit_short (not pushed)."
  git --no-pager status
  exit 0
fi

# Push to upstream (or set upstream if missing)
current_branch=$(git rev-parse --abbrev-ref HEAD)
upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || true)
if [ -z "$upstream" ]; then
  echo "No upstream configured for branch '$current_branch'. Pushing and setting upstream to origin/$current_branch..."
  git push -u origin "$current_branch"
else
  echo "Pushing to upstream..."
  git push
fi

pushed_commit_short=$(git rev-parse --short HEAD)
echo "Pushed commit: $pushed_commit_short"
git --no-pager status
