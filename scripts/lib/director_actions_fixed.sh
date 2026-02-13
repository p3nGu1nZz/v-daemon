#!/usr/bin/env sh
# Minimal Director actions (fixed, lightweight autopilot) for environments without Copilot CLI.
# Produces a small summary and a simple prioritized tasks list based on TODO markers and README.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOGFILE="${REPO_ROOT}/logs/director.log"
DEV_AUDITS_DIR="$REPO_ROOT/audits"
mkdir -p "$DEV_AUDITS_DIR"

run_autopilot_plan() {
  out_dir="$1"
  summary_file="$2"
  context_file="$3"
  combined_prompt="$4"

  plan_tasks="$out_dir/tasks.txt"
  # Simple plan: collect TODO/FIXME markers across the repo
  : >"$plan_tasks"
  # Find up to 50 TODO/FIXME occurrences
  grep -RIn --line-number -E 'TODO|FIXME' "$REPO_ROOT" 2>/dev/null | sed -n '1,50p' | while IFS= read -r l; do
    # convert to a short bullet
    # l is like path:line:content
    file="$(printf '%s' "$l" | cut -d: -f1)"
    lineno="$(printf '%s' "$l" | cut -d: -f2)"
    text="$(printf '%s' "$l" | cut -d: -f3- | sed 's/^\s*//')"
    printf '- Fix: %s:%s — %s\n' "$(basename "$file")" "$lineno" "$text" >>"$plan_tasks"
  done

  if [ ! -s "$plan_tasks" ]; then
    # No TODOs found: add a default maintenance task
    printf '%s\n' "- Run repository checks: sh scripts/check.sh and address failures" >"$plan_tasks"
  fi

  return 0
}

run_autopilot_summary() {
  run_ts="$(date +%Y%m%dT%H%M%S)"
  run_id="director-summary-$run_ts"
  out_dir="$DEV_AUDITS_DIR/$run_id"
  mkdir -p "$out_dir"
  summary_file="$out_dir/summary.txt"
  context_file="$out_dir/context.txt"
  combined_prompt="$out_dir/combined_prompt.txt"

  # Build a small summary from README and TODO
  {
    printf 'AUTOPILOT SUMMARY %s\n' "$run_ts"
    if [ -r "$REPO_ROOT/README.md" ]; then
      printf '\n--- README.md (first 80 lines) ---\n'
      sed -n '1,80p' "$REPO_ROOT/README.md" || true
      printf '\n'
    fi
    if [ -r "$REPO_ROOT/TODO.md" ]; then
      printf '\n--- TODO.md (first 80 lines) ---\n'
      sed -n '1,80p' "$REPO_ROOT/TODO.md" || true
      printf '\n'
    fi
    printf '\n--- SCRIPTS LIST ---\n'
    ls -1 "$REPO_ROOT/scripts" 2>/dev/null | sed -n '1,200p' || true
  } > "$summary_file"

  # Write a small context file
  {
    printf 'SUMMARY generated at: %s\n' "$(date -u +%Y%m%dT%H%M%SZ)"
    printf 'HEAD: ' 2>/dev/null || true
    if command -v git >/dev/null 2>&1 && [ -d "$REPO_ROOT/.git" ]; then
      git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true
      git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || true
    fi
  } > "$context_file"

  # Generate plan/tasks
  run_autopilot_plan "$out_dir" "$summary_file" "$context_file" "$combined_prompt"

  # Optionally attempt sandboxed patching if allowed
  if [ "${V_DAEMON_ALLOW_EXECUTE:-}" = "1" ] || [ "${DIRECTOR_ALLOW_EXECUTE:-}" = "1" ] || [ "${DIRECTOR_ALLOW_EXECUTE:-}" = "true" ]; then
    if [ -x "$REPO_ROOT/scripts/lib/patcher.sh" ]; then
      printf '%s [AGENT-DIRECTOR] Autopilot patcher (fixed): starting\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >>"$LOGFILE" 2>/dev/null || true
      sh "$REPO_ROOT/scripts/lib/patcher.sh" "$out_dir" "$out_dir/tasks.txt" "$combined_prompt" "$context_file" >>"$LOGFILE" 2>&1 || true
      printf '%s [AGENT-DIRECTOR] Autopilot patcher (fixed): completed (audit dir: %s)\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$out_dir" >>"$LOGFILE" 2>/dev/null || true
    else
      printf '%s [AGENT-DIRECTOR] Autopilot patcher (fixed): patcher script not present; skipping\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >>"$LOGFILE" 2>/dev/null || true
    fi
  fi

  return 0
}
