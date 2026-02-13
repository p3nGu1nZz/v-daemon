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
  LOCKDIR="$DEV_AUDITS_DIR/director-summary.lock"
  CREATED_LOCK=0
  # try to acquire a simple lockdir to avoid concurrent runs
  if mkdir "$LOCKDIR" 2>/dev/null; then
    echo "$$" >"$LOCKDIR/pid" 2>/dev/null || true
    CREATED_LOCK=1
  else
    OWNER_PID=$(cat "$LOCKDIR/pid" 2>/dev/null || true)
    if [ -n "$OWNER_PID" ] && kill -0 "$OWNER_PID" 2>/dev/null; then
      printf '%s [AGENT-DIRECTOR] Autopilot summary: already running (PID %s), skipping\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$OWNER_PID" >>"$LOGFILE" 2>/dev/null || true
      return 0
    else
      # stale lockdir, try to remove and acquire
      rm -rf "$LOCKDIR" 2>/dev/null || true
      if mkdir "$LOCKDIR" 2>/dev/null; then
        echo "$$" >"$LOCKDIR/pid" 2>/dev/null || true
        CREATED_LOCK=1
      else
        printf '%s [AGENT-DIRECTOR] Autopilot summary: unable to acquire lock, skipping\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >>"$LOGFILE" 2>/dev/null || true
        return 1
      fi
    fi
  fi

  cleanup_lock() {
    if [ "$CREATED_LOCK" = "1" ]; then
      rm -rf "$LOCKDIR" 2>/dev/null || true
    fi
  }
  trap 'cleanup_lock' EXIT INT TERM

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
Important: DO NOT attempt to access files on disk or request interactive permission; only use the REPO SNAPSHOT provided before this prompt.
EOF

  # Build a small repository snapshot to include with the prompt so copilot doesn't need filesystem access
  context_file=$(mktemp "/tmp/director_context_${run_ts}.XXXXXX") || context_file="/tmp/director_context_${run_ts}.$$"
  {
    printf 'REPO SNAPSHOT generated: %s\n\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')"
    if [ -r "$REPO_ROOT/README.md" ]; then
      printf '%s\n' '--- README.md (first 200 lines) ---'
      sed -n '1,200p' "$REPO_ROOT/README.md" || true
      printf '\n'
    fi
    if [ -r "$REPO_ROOT/TODO.md" ]; then
      printf '%s\n' '--- TODO.md (first 120 lines) ---'
      sed -n '1,120p' "$REPO_ROOT/TODO.md" || true
      printf '\n'
    fi
    printf '%s\n' '--- scripts list ---'
    ls -1 "$REPO_ROOT/scripts" 2>/dev/null | sed -n '1,200p' || true
    printf '\n'
    printf '%s\n' '--- key scripts snippets ---'
    for f in "$REPO_ROOT/scripts/setup.sh" "$REPO_ROOT/scripts/run.sh" "$REPO_ROOT/scripts/check.sh" "$REPO_ROOT/scripts/lib/daemon.sh" "$REPO_ROOT/scripts/lib/director.sh" "$REPO_ROOT/scripts/lib/director_actions.sh"; do
      if [ -r "$f" ]; then
        printf '\n--- %s (first 120 lines) ---\n' "$(basename \"$f\")"
        sed -n '1,120p' "$f" || true
      fi
    done
  } > "$context_file"

  combined_prompt=$(mktemp "/tmp/director_combined_${run_ts}.XXXXXX") || combined_prompt="$out_dir/combined_prompt.txt"
  cat "$context_file" "$prompt_file" > "$combined_prompt" || true

  # Ensure temp files are cleaned up when we exit
  cleanup_tmp() {
    rm -f "$prompt_file" "$context_file" "$combined_prompt" 2>/dev/null || true
  }
  trap 'cleanup_lock; cleanup_tmp' EXIT INT TERM

  printf '%s [AGENT-DIRECTOR] Autopilot summary: starting\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >>"$LOGFILE" 2>/dev/null || true

  if command -v copilot >/dev/null 2>&1; then
    COPILOT_HELP=$(copilot --help 2>&1 || true)
    SUPPORTS_STDIN=0
    if echo "$COPILOT_HELP" | grep -q -- '--stdin'; then
      SUPPORTS_STDIN=1
    fi
    COPILOT_OPTS=""
    # Always request gpt-5-mini; prefer explicit flags if supported
    if echo "$COPILOT_HELP" | grep -q -- '--model'; then
      COPILOT_OPTS="--model gpt-5-mini"
    elif echo "$COPILOT_HELP" | grep -q -- '--engine'; then
      COPILOT_OPTS="--engine gpt-5-mini"
    fi
    # Ensure model env var is set so any copilot implementation uses gpt-5-mini
    COPILOT_ENV="env COPILOT_MODEL=gpt-5-mini"

    copilot_status=127
    if [ -n "$COPILOT_OPTS" ]; then
      if [ "$SUPPORTS_STDIN" -eq 1 ]; then
        if $COPILOT_ENV copilot $COPILOT_OPTS --stdin <"$combined_prompt" >"$summary_file" 2>"$out_dir/copilot.err"; then
          printf '%s [AGENT-DIRECTOR] Autopilot summary: copilot succeeded, saved to %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$summary_file" >>"$LOGFILE" 2>/dev/null || true
          copilot_status=0
        else
          rc=$?
          printf '%s [AGENT-DIRECTOR] Autopilot summary: copilot invocation failed (exit %s), falling back\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$rc" >>"$LOGFILE" 2>/dev/null || true
          copilot_status=$rc
        fi
      else
        if cat "$combined_prompt" | $COPILOT_ENV copilot $COPILOT_OPTS >"$summary_file" 2>"$out_dir/copilot.err"; then
          printf '%s [AGENT-DIRECTOR] Autopilot summary: copilot succeeded (piped), saved to %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$summary_file" >>"$LOGFILE" 2>/dev/null || true
          copilot_status=0
        else
          rc=$?
          printf '%s [AGENT-DIRECTOR] Autopilot summary: copilot invocation (piped) failed (exit %s), falling back\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$rc" >>"$LOGFILE" 2>/dev/null || true
          copilot_status=$rc
        fi
      fi
    else
      # No explicit model flag supported; still set model via env var
      if [ "$SUPPORTS_STDIN" -eq 1 ]; then
        if $COPILOT_ENV copilot --stdin <"$combined_prompt" >"$summary_file" 2>"$out_dir/copilot.err"; then
          printf '%s [AGENT-DIRECTOR] Autopilot summary: copilot succeeded (env), saved to %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$summary_file" >>"$LOGFILE" 2>/dev/null || true
          copilot_status=0
        else
          rc=$?
          printf '%s [AGENT-DIRECTOR] Autopilot summary: copilot invocation (env) failed (exit %s), falling back\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$rc" >>"$LOGFILE" 2>/dev/null || true
          copilot_status=$rc
        fi
      else
        if cat "$combined_prompt" | $COPILOT_ENV copilot >"$summary_file" 2>"$out_dir/copilot.err"; then
          printf '%s [AGENT-DIRECTOR] Autopilot summary: copilot succeeded (env+piped), saved to %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$summary_file" >>"$LOGFILE" 2>/dev/null || true
          copilot_status=0
        else
          rc=$?
          printf '%s [AGENT-DIRECTOR] Autopilot summary: copilot invocation (env+piped) failed (exit %s), falling back\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$rc" >>"$LOGFILE" 2>/dev/null || true
          copilot_status=$rc
        fi
      fi
    fi
  else
    printf '%s [AGENT-DIRECTOR] Autopilot summary: copilot CLI not found, using local summarizer\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >>"$LOGFILE" 2>/dev/null || true
    copilot_status=127
  fi

  # If copilot didn't produce a file, returned a non-zero status, or produced permission errors, fallback
  need_fallback=0
  if [ "$copilot_status" != "0" ] || [ ! -s "$summary_file" ]; then
    need_fallback=1
  else
    if grep -qi "permission denied" "$summary_file" 2>/dev/null; then
      need_fallback=1
      printf '%s [AGENT-DIRECTOR] Autopilot summary: copilot output contained permission errors, falling back\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >>"$LOGFILE" 2>/dev/null || true
    fi
  fi

  if [ "$need_fallback" -eq 1 ]; then
    run_local_summarizer >"$summary_file" 2>&1 || true
    printf '%s [AGENT-DIRECTOR] Autopilot summary: fallback saved to %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$summary_file" >>"$LOGFILE" 2>/dev/null || true
    # If there is a copilot.err, append it to log for debugging
    if [ -f "$out_dir/copilot.err" ] && [ -s "$out_dir/copilot.err" ]; then
      printf '%s [AGENT-DIRECTOR] copilot stderr:\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >>"$LOGFILE" 2>/dev/null || true
      sed -n '1,50p' "$out_dir/copilot.err" >>"$LOGFILE" 2>/dev/null || true
    fi
  fi

  # Sanitize summary: remove obvious copilot-run artifacts and append (up to first 200 lines)
  if [ -s "$summary_file" ]; then
    cleaned=$(mktemp "/tmp/director_cleaned_${run_ts}.XXXXXX") || cleaned="$summary_file"
    # filter out noise that looks like shell commands, permission errors, copilot help hints, or copilot planning artifacts
    grep -i -v -E 'Permission denied|could not request permission|Try .*copilot --help|^\\$ |^\\s*✗|Reading README|Running parallel|Attempt to read|^\\s*\\$' "$summary_file" > "$cleaned" 2>/dev/null || cp "$summary_file" "$cleaned" 2>/dev/null || true
    sed -n '1,200p' "$cleaned" >>"$LOGFILE" 2>/dev/null || true

    # Prepare a one-line excerpt (first 250 characters, whitespace collapsed) from cleaned content
    excerpt_raw=$(tr '\n' ' ' <"$cleaned" | sed 's/[[:space:]]\+/ /g' | sed 's/^ *//;s/ *$//')
    excerpt=$(printf '%s' "$excerpt_raw" | cut -c 1-250)
    printf '%s [AGENT-DIRECTOR] summary excerpt: %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$excerpt" >>"$LOGFILE" 2>/dev/null || true
    # Also echo to stdout (will be captured by director's stdout redirection)
    printf '%s [AGENT-DIRECTOR] summary excerpt: %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$excerpt" || true

    # cleanup temporary cleaned file if created
    [ -n "$cleaned" ] && [ "$cleaned" != "$summary_file" ] && rm -f "$cleaned" 2>/dev/null || true
  fi

  # cleanup temp prompt/context/combined files and lock
  cleanup_tmp || true
  cleanup_lock
  trap - EXIT INT TERM
  return 0
}
