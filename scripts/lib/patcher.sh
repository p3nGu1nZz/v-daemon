#!/usr/bin/env sh
# Minimal sandboxed patcher: create a sandbox branch, create a small artifact, commit, run checks, and write artifacts.
set -eu

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <out_dir> <tasks_file> [combined_prompt] [context_file]" >&2
  exit 2
fi
OUT_DIR="$1"
TASKS_FILE="$2"
COMBINED_PROMPT="${3:-}"
CONTEXT_FILE="${4:-}"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOGFILE="$REPO_ROOT/logs/director.log"
mkdir -p "$OUT_DIR"
TS="$(date +%Y%m%dT%H%M%S)"
RESULT_FILE="$OUT_DIR/patcher_result.txt"
PATCH_DIR="$REPO_ROOT/run/selfpatch"
mkdir -p "$PATCH_DIR"

# Extract first task line
TASK_LINE="$(grep -E '^\s*-\s+' "$TASKS_FILE" 2>/dev/null | sed -n '1p' || true)"
if [ -z "$TASK_LINE" ]; then
  echo "No task lines found in $TASKS_FILE" > "$RESULT_FILE"
  exit 0
fi

TITLE="$(printf '%s' "$TASK_LINE" | sed 's/^[[:space:]]*-\s*//; s/:.*$//')"
SLUG="$(printf '%s' "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\+/-/g' | sed 's/^-//' | sed 's/-$//' | cut -c1-60)"
BRANCH_PREFIX="${DIRECTOR_SANDBOX_BRANCH_PREFIX:-director/sandbox-}"
BRANCH="${BRANCH_PREFIX}${TS}-${SLUG}"

printf '%s [PATCHER] preparing patch for: %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$TITLE" >>"$LOGFILE" 2>/dev/null || true
mkdir -p "$OUT_DIR/patcher" "$PATCH_DIR"

# If git repo available, create branch and commit a small artifact
if [ -d "$REPO_ROOT/.git" ] && command -v git >/dev/null 2>&1; then
  cd "$REPO_ROOT"
  CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  # create branch
  if git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
    git checkout "$BRANCH" >/dev/null 2>&1 || true
  else
    git checkout -b "$BRANCH" >/dev/null 2>&1 || true
  fi

  PATCH_WORK_DIR="$PATCH_DIR/$BRANCH"
  mkdir -p "$PATCH_WORK_DIR"
  printf '%s\n' "Autopatch: $TITLE" "timestamp: $(date +'%Y-%m-%dT%H:%M:%S%z')" > "$PATCH_WORK_DIR/applied.txt"
  git add "$PATCH_WORK_DIR/applied.txt" || true
  COMMIT_MSG="chore(autopatch): $TITLE"
  git commit -m "$COMMIT_MSG" >/dev/null 2>&1 || true

  # Run checks
  if [ -x "./scripts/check.sh" ] || command -v sh >/dev/null 2>&1; then
    sh scripts/check.sh >"$OUT_DIR/patcher_check.out" 2>&1 || true
    CHECK_RC=$?
  else
    echo "No check script executable; skipping checks" >"$OUT_DIR/patcher_check.out"
    CHECK_RC=127
  fi

  # Save diff
  git --no-pager diff "$CURRENT_BRANCH".."$BRANCH" > "$OUT_DIR/patch.diff" 2>/dev/null || git show HEAD > "$OUT_DIR/patch.diff" 2>/dev/null || true

  # Record result
  {
    echo "branch: $BRANCH"
    echo "title: $TITLE"
    echo "commit_msg: $COMMIT_MSG"
    echo "check_return_code: $CHECK_RC"
    echo "check_output_file: $OUT_DIR/patcher_check.out"
    echo "patch_file: $OUT_DIR/patch.diff"
  } > "$RESULT_FILE"

  printf '%s [PATCHER] patch completed: branch=%s rc=%s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$BRANCH" "$CHECK_RC" >>"$LOGFILE" 2>/dev/null || true

  # Attempt to return to previous branch
  if [ -n "$CURRENT_BRANCH" ]; then
    git checkout "$CURRENT_BRANCH" >/dev/null 2>&1 || true
  fi

  exit 0
else
  # non-git fallback: write patch artifact only
  DIR="$PATCH_DIR/${TS}-${SLUG}"
  mkdir -p "$DIR"
  printf '%s\n' "Autopatch: $TITLE" "timestamp: $(date +'%Y-%m-%dT%H:%M:%S%z')" > "$DIR/applied.txt"
  echo "note: repository is not a git repository or git not available; created artifact at $DIR" > "$RESULT_FILE"
  exit 0
fi
