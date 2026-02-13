#!/usr/bin/env sh
# Director action helpers: autopilot summary (uses copilot CLI if available) and a local fallback.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOGFILE="${REPO_ROOT}/logs/director.log"
DEV_AUDITS_DIR="$REPO_ROOT/dev/audits"
mkdir -p "$DEV_AUDITS_DIR"

# Local summarizer fallback
run_local_summarizer() {
  echo "Repository summary (fallback)"
  echo "Generated: $(date +'%Y-%m-%dT%H:%M:%S%z')"
  echo
  if [ -f "$REPO_ROOT/README.md" ]; then
    echo "README (top):"
    sed -n '1,12p' "$REPO_ROOT/README.md"
    echo
  fi
  if [ -f "$REPO_ROOT/TODO.md" ]; then
    echo "Top TODOs:"
    grep -E '^- \[ \]' "$REPO_ROOT/TODO.md" | sed -n '1,10p' || true
    echo
  fi
  echo "Top scripts:"
  ls -1 "$REPO_ROOT/scripts" 2>/dev/null | sed -n '1,40p'
  echo
  echo "Top-level files:"
  ls -1 "$REPO_ROOT" | sed -n '1,40p'
  echo
  echo "File counts by dir:"
  for d in "$REPO_ROOT" "$REPO_ROOT/scripts" "$REPO_ROOT/src" "$REPO_ROOT/logs"; do
    if [ -d "$d" ]; then
      cnt=$(find "$d" -type f 2>/dev/null | wc -l | tr -d ' ')
      echo "$(basename "$d"): $cnt files"
    fi
  done
}

# Run autopilot summary: try copilot CLI (stdin) and fall back to local summarizer
run_autopilot_summary() {
  run_ts=$(date +%Y%m%dT%H%M%S)
  run_id="director-summary-$run_ts"
  out_dir="$DEV_AUDITS_DIR/$run_id"
  mkdir -p "$out_dir"
  summary_file="$out_dir/summary.txt"

  prompt_file=$(mktemp "/tmp/director_prompt_${run_ts}.XXXXXX") || prompt_file="/tmp/director_prompt_${run_ts}.$$"
  cat > "$prompt_file" <<'EOF'
You are an expert code reviewer. Analyze the repository in the current working directory and produce a concise summary (6-12 lines) describing:
- project purpose
- main components and key files
- how to build and run tests
- outstanding TODOs from TODO.md (if present)
Provide a plain-text report suitable for logging and auditing.
EOF

  printf '%s [AGENT-DIRECTOR] Autopilot summary: starting\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >>"$LOGFILE" 2>/dev/null || true

  if command -v copilot >/dev/null 2>&1; then
    # Try a simple stdin-based invocation; if it fails, fallback
    if copilot --stdin <"$prompt_file" >"$summary_file" 2>&1; then
      printf '%s [AGENT-DIRECTOR] Autopilot summary: copilot succeeded, saved to %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$summary_file" >>"$LOGFILE" 2>/dev/null || true
      # append a short excerpt into director log for visibility
      sed -n '1,200p' "$summary_file" >>"$LOGFILE" 2>/dev/null || true
      rm -f "$prompt_file" 2>/dev/null || true
      return 0
    else
      printf '%s [AGENT-DIRECTOR] Autopilot summary: copilot invocation failed, falling back\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >>"$LOGFILE" 2>/dev/null || true
    fi
  else
    printf '%s [AGENT-DIRECTOR] Autopilot summary: copilot CLI not found, using local summarizer\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >>"$LOGFILE" 2>/dev/null || true
  fi

  # Fallback
  run_local_summarizer >"$summary_file" 2>&1 || true
  printf '%s [AGENT-DIRECTOR] Autopilot summary: fallback saved to %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$summary_file" >>"$LOGFILE" 2>/dev/null || true
  sed -n '1,200p' "$summary_file" >>"$LOGFILE" 2>/dev/null || true
  rm -f "$prompt_file" 2>/dev/null || true
  return 0
}
