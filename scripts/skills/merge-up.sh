#!/usr/bin/env sh
# merge-up skill: merge active remote branches into main and clean up merged branches
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

LOGFILE="$REPO_ROOT/logs/merge-up.log"
mkdir -p "$(dirname "$LOGFILE")"

echo "$(date +'%Y-%m-%dT%H:%M:%S%z') [MERGE-UP] starting" >>"$LOGFILE"

MAIN_BRANCH="${1:-main}"

# Fetch all remotes and prune deleted refs
if ! git fetch --all --prune --quiet 2>>"$LOGFILE"; then
  echo "$(date +'%Y-%m-%dT%H:%M:%S%z') [MERGE-UP] git fetch failed" >>"$LOGFILE"
fi

# Gather remote branches (origin/*) excluding HEAD and main/master
# Use for-each-ref for reliable listing
branches="$(git for-each-ref --format='%(refname:short)' refs/remotes/origin/* 2>/dev/null | sed 's@^origin/@@' | grep -v '^HEAD$' | grep -v -E '^(main|master|origin)$' || true)"

if [ -z "$(echo "$branches" | tr -d '[:space:]')" ]; then
  echo "$(date +'%Y-%m-%dT%H:%M:%S%z') [MERGE-UP] no branches to merge" >>"$LOGFILE"
  exit 0
fi

# Ensure local main exists and is checked out
if git rev-parse --verify "$MAIN_BRANCH" >/dev/null 2>&1; then
  git checkout "$MAIN_BRANCH" >/dev/null 2>&1 || git checkout -B "$MAIN_BRANCH" origin/"$MAIN_BRANCH" >/dev/null 2>&1 || true
else
  # Try to create from origin/main, fall back to a new branch
  git checkout -b "$MAIN_BRANCH" origin/"$MAIN_BRANCH" >/dev/null 2>&1 || git checkout -b "$MAIN_BRANCH" >/dev/null 2>&1 || true
fi

merged_list=""
failed_branches=""

for br in $branches; do
  # skip empty entries and main
  if [ -z "$br" ] || [ "$br" = "$MAIN_BRANCH" ]; then
    continue
  fi
  echo "$(date +'%Y-%m-%dT%H:%M:%S%z') [MERGE-UP] merging origin/$br into $MAIN_BRANCH" >>"$LOGFILE"
  if git merge --no-edit --no-ff origin/"$br" >/dev/null 2>&1; then
    echo "$(date +'%Y-%m-%dT%H:%M:%S%z') [MERGE-UP] merged origin/$br" >>"$LOGFILE"
    merged_list="$merged_list $br"
  else
    echo "$(date +'%Y-%m-%dT%H:%M:%S%z') [MERGE-UP] conflict merging origin/$br" >>"$LOGFILE"
    # Attempt to run patch-repo skill to resolve conflicts if available
    if [ -f "$REPO_ROOT/scripts/skills/patch-repo.sh" ]; then
      echo "$(date +'%Y-%m-%dT%H:%M:%S%z') [MERGE-UP] running patch-repo to attempt resolution" >>"$LOGFILE"
      sh "$REPO_ROOT/scripts/skills/patch-repo.sh" || true
      git add -A || true
      if git commit -m "Resolve merge conflicts for origin/$br" >/dev/null 2>&1; then
        echo "$(date +'%Y-%m-%dT%H:%M:%S%z') [MERGE-UP] committed conflict resolution for $br" >>"$LOGFILE"
      fi
      # Attempt merge again
      if git merge --no-edit --no-ff origin/"$br" >/dev/null 2>&1; then
        echo "$(date +'%Y-%m-%dT%H:%M:%S%z') [MERGE-UP] merged origin/$br after patch" >>"$LOGFILE"
        merged_list="$merged_list $br"
      else
        echo "$(date +'%Y-%m-%dT%H:%M:%S%z') [MERGE-UP] failed to merge origin/$br after patch" >>"$LOGFILE"
        failed_branches="$failed_branches $br"
      fi
    else
      echo "$(date +'%Y-%m-%dT%H:%M:%S%z') [MERGE-UP] patch-repo skill not found; marking $br as failed" >>"$LOGFILE"
      failed_branches="$failed_branches $br"
    fi
  fi
done

# Push main branch and verify
echo "$(date +'%Y-%m-%dT%H:%M:%S%z') [MERGE-UP] pushing $MAIN_BRANCH to origin" >>"$LOGFILE"
if git push origin "$MAIN_BRANCH" >/dev/null 2>&1; then
  echo "$(date +'%Y-%m-%dT%H:%M:%S%z') [MERGE-UP] pushed $MAIN_BRANCH" >>"$LOGFILE"
else
  echo "$(date +'%Y-%m-%dT%H:%M:%S%z') [MERGE-UP] push failed for $MAIN_BRANCH; attempting patch-repo and retry" >>"$LOGFILE"
  if [ -f "$REPO_ROOT/scripts/skills/patch-repo.sh" ]; then
    sh "$REPO_ROOT/scripts/skills/patch-repo.sh" || true
    git add -A || true
    git commit -m "Fix push issues after merge-up" >/dev/null 2>&1 || true
    git push origin "$MAIN_BRANCH" >/dev/null 2>&1 || echo "$(date +'%Y-%m-%dT%H:%M:%S%z') [MERGE-UP] push retry failed" >>"$LOGFILE"
  fi
fi

# Ensure on main branch
git checkout "$MAIN_BRANCH" >/dev/null 2>&1 || true

# Delete merged branches locally and remotely
for b in $merged_list; do
  if [ -z "$b" ]; then
    continue
  fi
  echo "$(date +'%Y-%m-%dT%H:%M:%S%z') [MERGE-UP] deleting branch $b locally and remotely" >>"$LOGFILE"
  if git rev-parse --verify "$b" >/dev/null 2>&1; then
    git branch -D "$b" >/dev/null 2>&1 || true
  fi
  git push origin --delete "$b" >/dev/null 2>&1 || true
done

if [ -n "$(echo "$failed_branches" | tr -d '[:space:]')" ]; then
  echo "$(date +'%Y-%m-%dT%H:%M:%S%z') [MERGE-UP] completed with failures: $failed_branches" >>"$LOGFILE"
  exit 2
fi

echo "$(date +'%Y-%m-%dT%H:%M:%S%z') [MERGE-UP] complete; merged:$merged_list" >>"$LOGFILE"
exit 0
