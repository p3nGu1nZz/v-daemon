#!/usr/bin/env bash
# If invoked with a POSIX sh (not bash), re-exec with bash to ensure required features are available.
if [ -z "${BASH_VERSION:-}" ]; then
  if command -v bash >/dev/null 2>&1; then
    exec bash "$0" "$@"
  else
    echo "Error: bash is required to run this script." >&2
    exit 1
  fi
fi
set -euo pipefail

# YOLO default true (allow pushing). If set to false/0/no, skip pushing upstream but still commit and attempt local merges.
YOLO="${YOLO:-true}"
YOLO_LC="$(printf '%s' "$YOLO" | tr '[:upper:]' '[:lower:]')"
if [ "$YOLO_LC" = "false" ] || [ "$YOLO_LC" = "0" ] || [ "$YOLO_LC" = "no" ] || [ "$YOLO_LC" = "n" ]; then
  YOLO=false
else
  YOLO=true
fi



usage() {
  cat <<'USAGE'
Usage: scripts/skills/patch-repo.sh [--help]

Automate a simple git patch workflow and capture outputs under run/skills/patch-repo/<timestamp>/.

Options:
  --help      Show this help message and exit.

Notes:
  - The commit message uses the index tree hash (git write-tree) to uniquely identify the snapshot: update:<tree-hash>
  - If the current branch has no upstream, the script will run: git push -u origin <branch>
  - This script assumes it's run from inside a git repository and that git is configured.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
  shift
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
args_string="$(printf '%s ' "$@" | sed -e 's/"/\\"/g')"
pushed_json=false

echo "patch-repo starting: $TIMESTAMP"

echo "Staging all changes..."
git add .

# If there is nothing staged, check for unpushed local commits and attempt to push them
if git diff --cached --quiet; then
  echo "No staged changes to commit."
  git --no-pager status >"$OUTDIR/status.txt" || true
  commit="$(git rev-parse --short HEAD 2>/dev/null || true)"
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"

  # Detect if local branch is ahead of upstream using git status parsing
  status_line="$(git status --porcelain --branch --untracked-files=no 2>/dev/null | sed -n '1p' || true)"
  ahead=0
  if echo "$status_line" | grep -q 'ahead'; then
    ahead="$(echo "$status_line" | sed -n 's/.*ahead \([0-9]\+\).*/\1/p')"
  fi

  if [ -n "$ahead" ] && [ "$ahead" -gt 0 ]; then
    echo "Local branch '$branch' is ahead by $ahead commit(s);"
    if [ "$YOLO" = true ]; then
      echo "attempting to push..."
      current_branch="$branch"
      upstream="$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || true)"
      MAX_RETRIES=3
      attempt=1
      pushed=false
      while [ $attempt -le $MAX_RETRIES ]; do
        if [ -z "$upstream" ] && [ $attempt -eq 1 ]; then
          echo "No upstream configured for branch '$current_branch'. Pushing and setting upstream to origin/$current_branch..."
          if git push -u origin "$current_branch"; then
            pushed=true
            break
          else
            echo "git push attempt $attempt failed." >&2
          fi
        else
          echo "Pushing to upstream (attempt $attempt)..."
          if git push; then
            pushed=true
            break
          else
            echo "git push attempt $attempt failed." >&2
          fi
        fi
        attempt=$((attempt+1))
        sleep 1
      done

      git --no-pager status >"$OUTDIR/status.txt" || true
      commit="$(git rev-parse --short HEAD 2>/dev/null || true)"
      branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
      if [ "$pushed" = true ]; then
        pushed_json=true
        exit_code=0
      else
        pushed_json=false
        exit_code=1
      fi
      cat >"$OUTDIR/report.json" <<JSON
{
  "timestamp": "$TIMESTAMP",
  "script": "scripts/skills/patch-repo.sh",
  "args": "$args_string",
  "exit_code": $exit_code,
  "commit": "$commit",
  "branch": "$branch",
  "pushed": $pushed_json,
  "status_file": "$OUTDIR/status.txt"
}
JSON
      if [ "$pushed" = true ]; then
        echo "Pushed commit: $(git rev-parse --short HEAD)"
        exit 0
      else
        echo "Created commit $commit (push failed)."
        exit 1
      fi
    else
      echo "YOLO=false; skipping automatic push of local commits. Please run 'git push' manually to publish changes."
      git --no-pager status >"$OUTDIR/status.txt" || true
      commit="$(git rev-parse --short HEAD 2>/dev/null || true)"
      branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
      pushed_json=false
      exit_code=0
      cat >"$OUTDIR/report.json" <<JSON
{
  "timestamp": "$TIMESTAMP",
  "script": "scripts/skills/patch-repo.sh",
  "args": "$args_string",
  "exit_code": $exit_code,
  "commit": "$commit",
  "branch": "$branch",
  "pushed": $pushed_json,
  "message": "skipped push due to YOLO=false",
  "status_file": "$OUTDIR/status.txt"
}
JSON
      echo "No staged changes to commit. Nothing to do."
      exit 0
    fi
  fi

  # not ahead and no staged changes
  cat >"$OUTDIR/report.json" <<JSON
{
  "timestamp": "$TIMESTAMP",
  "script": "scripts/skills/patch-repo.sh",
  "args": "$args_string",
  "exit_code": 0,
  "commit": "$commit",
  "branch": "$branch",
  "message": "no changes"
}
JSON
  echo "No staged changes to commit. Nothing to do."
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
  "args": "$args_string",
  "exit_code": 1,
  "error": "failed to write tree"
}
JSON
  exit 1
fi

commit_msg="update:${tree_hash}"
TRAILER='Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'

# Create the commit
echo "Committing with message: $commit_msg"
if ! git commit -m "$commit_msg" -m "$TRAILER"; then
  echo "git commit failed." >&2
  git --no-pager status >"$OUTDIR/status.txt" || true
  cat >"$OUTDIR/report.json" <<JSON
{
  "timestamp": "$TIMESTAMP",
  "script": "scripts/skills/patch-repo.sh",
  "args": "$args_string",
  "exit_code": 1,
  "error": "git commit failed"
}
JSON
  exit 1
fi

new_commit_short=$(git rev-parse --short HEAD)

echo "Created commit $new_commit_short"

pushed=false
current_branch=$(git rev-parse --abbrev-ref HEAD)
upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || true)
if [ "$YOLO" = true ]; then
  # Attempt to push the created commit; retry up to 3 times on failure.
  MAX_RETRIES=3
  attempt=1
  while [ $attempt -le $MAX_RETRIES ]; do
    if [ -z "$upstream" ] && [ $attempt -eq 1 ]; then
      echo "No upstream configured for branch '$current_branch'. Pushing and setting upstream to origin/$current_branch..."
      if git push -u origin "$current_branch"; then
        pushed=true
        break
      else
        echo "git push attempt $attempt failed." >&2
      fi
    else
      echo "Pushing to upstream (attempt $attempt)..."
      if git push; then
        pushed=true
        break
      else
        echo "git push attempt $attempt failed." >&2
      fi
    fi
    attempt=$((attempt+1))
    sleep 1
  done
  if [ "$pushed" = true ]; then
    echo "Pushed commit: $(git rev-parse --short HEAD)"
  else
    echo "All push attempts failed after $MAX_RETRIES tries." >&2
  fi
else
  echo "YOLO=false; skipping push of created commit."
  pushed=false
fi

pushed_commit_short=$(git rev-parse --short HEAD)

git --no-pager status >"$OUTDIR/status.txt" || true

commit="$(git rev-parse --short HEAD 2>/dev/null || true)"
branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [ "$YOLO" = false ]; then
  pushed_json=false
  exit_code=0
else
  if [ "$pushed" = true ]; then
    pushed_json=true
    exit_code=0
  else
    pushed_json=false
    exit_code=1
  fi
fi

# Write a structured JSON report
# Attempt to merge the pushed branch into main/master locally or on origin if appropriate.
merge_attempted_json=false
merge_result="skipped"
merge_branch=""
current_branch="$(git rev-parse --abbrev-ref HEAD)"
if [ "$pushed" = true ] || [ "$YOLO" = false ]; then
  if [ "$current_branch" != "main" ] && [ "$current_branch" != "master" ]; then
    merge_attempted_json=true
    MAIN_BRANCH="main"
    if ! git ls-remote --exit-code --heads origin "$MAIN_BRANCH" >/dev/null 2>&1; then
      if git ls-remote --exit-code --heads origin master >/dev/null 2>&1; then
        MAIN_BRANCH="master"
      fi
    fi
    echo "Attempting to merge branch '$current_branch' into '$MAIN_BRANCH'..."

    if [ "$pushed" = true ]; then
      # remote-based merge workflow
      if git fetch origin "$MAIN_BRANCH" "$current_branch" >/dev/null 2>&1; then
        # ensure a clean local MAIN_BRANCH reflecting origin
        if git show-ref --verify --quiet refs/heads/"$MAIN_BRANCH"; then
          git checkout "$MAIN_BRANCH"
          git reset --hard "origin/$MAIN_BRANCH"
        else
          git checkout -b "$MAIN_BRANCH" "origin/$MAIN_BRANCH"
        fi

        echo "Merging origin/$current_branch into $MAIN_BRANCH"
        if git merge --no-ff --no-edit "origin/$current_branch" >/dev/null 2>&1; then
          echo "Merge succeeded. Pushing $MAIN_BRANCH to origin..."
          if git push origin "$MAIN_BRANCH" >/dev/null 2>&1; then
            merge_result="merged_and_pushed"
          else
            merge_result="merged_push_failed"
          fi
        else
          echo "Merge reported conflicts; attempting automated 'theirs' strategy..."
          if git merge -s recursive -X theirs --no-edit "origin/$current_branch" >/dev/null 2>&1; then
            echo "Automated 'theirs' merge succeeded. Pushing $MAIN_BRANCH..."
            if git push origin "$MAIN_BRANCH" >/dev/null 2>&1; then
              merge_result="automated_resolved_and_pushed"
            else
              merge_result="automated_resolved_push_failed"
            fi
          else
            echo "Automated resolution failed; aborting merge and creating merge branch for manual resolution."
            git merge --abort >/dev/null 2>&1 || true
            MERGE_FAIL_BRANCH="merge/${current_branch}-into-${MAIN_BRANCH}-${TIMESTAMP}"
            git checkout -b "$MERGE_FAIL_BRANCH"
            if git push -u origin "$MERGE_FAIL_BRANCH" >/dev/null 2>&1; then
              merge_result="conflicts_push_merge_branch_created"
              merge_branch="$MERGE_FAIL_BRANCH"
            else
              merge_result="conflicts_push_merge_branch_failed"
              merge_branch="$MERGE_FAIL_BRANCH"
            fi
          fi
        fi

        # switch back to the original branch
        git checkout "$current_branch" >/dev/null 2>&1 || true
      else
        echo "Warning: failed to fetch remote branches; skipping merge."
        merge_result="fetch_failed"
      fi
    else
      # YOLO=false: perform a local merge into MAIN_BRANCH but do not push
      if git show-ref --verify --quiet refs/heads/"$MAIN_BRANCH"; then
        git checkout "$MAIN_BRANCH"
      else
        if git ls-remote --exit-code --heads origin "$MAIN_BRANCH" >/dev/null 2>&1; then
          git fetch origin "$MAIN_BRANCH" >/dev/null 2>&1
          git checkout -b "$MAIN_BRANCH" "origin/$MAIN_BRANCH"
        else
          git checkout -b "$MAIN_BRANCH"
        fi
      fi
      echo "Merging $current_branch into local $MAIN_BRANCH"
      if git merge --no-ff --no-edit "$current_branch" >/dev/null 2>&1; then
        merge_result="merged_locally"
      else
        echo "Merge reported conflicts; attempting automated 'theirs' strategy..."
        if git merge -s recursive -X theirs --no-edit "$current_branch" >/dev/null 2>&1; then
          merge_result="automated_resolved_locally"
        else
          git merge --abort >/dev/null 2>&1 || true
          MERGE_FAIL_BRANCH="merge/${current_branch}-into-${MAIN_BRANCH}-${TIMESTAMP}"
          git checkout -b "$MERGE_FAIL_BRANCH"
          merge_result="conflicts_local_merge_branch_created"
          merge_branch="$MERGE_FAIL_BRANCH"
        fi
      fi
      # do not push when YOLO=false
      git checkout "$current_branch" >/dev/null 2>&1 || true
    fi
  else
    echo "Current branch is '$current_branch' (main/master); skipping merge."
    merge_result="skipped_main_branch"
  fi
fi

# Write a structured JSON report including merge metadata
cat >"$OUTDIR/report.json" <<JSON
{
  "timestamp": "$TIMESTAMP",
  "script": "scripts/skills/patch-repo.sh",
  "args": "$args_string",
  "exit_code": $exit_code,
  "commit": "$commit",
  "branch": "$branch",
  "pushed": $pushed_json,
  "merge_attempted": $merge_attempted_json,
  "merge_result": "$merge_result",
  "merge_branch": "$merge_branch",
  "stdout": "$STDOUT_FILE",
  "stderr": "$STDERR_FILE",
  "status_file": "$OUTDIR/status.txt"
}
JSON

# Human-friendly summary
if [ "$pushed" = true ]; then
  pushed_commit_short=$(git rev-parse --short HEAD)
  echo "Pushed commit: $pushed_commit_short"
else
  echo "Created commit $new_commit_short (push failed)."
fi

echo "Outputs written to: $OUTDIR"

exit $exit_code
