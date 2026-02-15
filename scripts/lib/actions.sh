#!/usr/bin/env sh
# Director action helpers: autopilot summary (uses copilot CLI only; local fallback removed).
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOGFILE="${REPO_ROOT}/logs/director.log"
DEV_AUDITS_DIR="$REPO_ROOT/audits"
mkdir -p "$DEV_AUDITS_DIR"

# Load environment, console, and logger helpers if available for consistent env and logging
if [ -f "$REPO_ROOT/scripts/lib/env.sh" ]; then
  . "$REPO_ROOT/scripts/lib/env.sh"
  env_init "$REPO_ROOT"
fi
# console/logger/prompts are loaded by env_init in scripts/lib/env.sh

# Local summarizer removed; Copilot CLI is required for autopilot summaries.

# Run autopilot summary: use copilot CLI only (no local fallback)
run_autopilot_summary() {
  LOCKDIR="$DEV_AUDITS_DIR/director-summary.lock"
  CREATED_LOCK=0
  # try to acquire a simple lockdir to avoid concurrent runs
  if mkdir "$LOCKDIR" 2>/dev/null; then
    echo "$$" >"$LOCKDIR/pid" 2>/dev/null || true
    echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" >"$LOCKDIR/ts" 2>/dev/null || true
    ps -p $$ -o args= 2>/dev/null >"$LOCKDIR/cmdline" 2>/dev/null || true
    CREATED_LOCK=1
  else
    OWNER_PID=$(cat "$LOCKDIR/pid" 2>/dev/null || true)
    OWNER_META=""
    if [ -f "$LOCKDIR/cmdline" ]; then OWNER_META="$(cat \"$LOCKDIR/cmdline\" 2>/dev/null || true)"; fi
    if [ -n "$OWNER_PID" ] && kill -0 "$OWNER_PID" 2>/dev/null; then
      # determine lock age (seconds) using the timestamp file if present
      LOCK_TS_FILE="$LOCKDIR/ts"
      owner_age=0
      if [ -f "$LOCK_TS_FILE" ]; then
        lock_epoch=$(stat -c %Y "$LOCK_TS_FILE" 2>/dev/null || echo 0)
        now_epoch=$(date +%s)
        owner_age=$((now_epoch - lock_epoch))
      fi
      STALE_SECONDS="${DIRECTOR_LOCK_STALE_SECONDS:-600}"
      if [ "$owner_age" -ge "$STALE_SECONDS" ] && [ "$owner_age" -gt 0 ]; then
        printf '%s [AGENT-DIRECTOR] Autopilot summary: lock PID %s owner_cmd="%s" age=%ss exceeds stale threshold=%ss; attempting to terminate and clean up\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$OWNER_PID" "$OWNER_META" "$owner_age" "$STALE_SECONDS" >>"$LOGFILE" 2>/dev/null || true
        # Try graceful shutdown first, then escalate
        if kill -TERM "$OWNER_PID" 2>/dev/null; then
          sleep 3
          if kill -0 "$OWNER_PID" 2>/dev/null; then
            kill -9 "$OWNER_PID" 2>/dev/null || true
          fi
        fi
        rm -rf "$LOCKDIR" 2>/dev/null || true
        # Attempt to acquire the lock now that we've cleaned it
        if mkdir "$LOCKDIR" 2>/dev/null; then
          echo "$$" >"$LOCKDIR/pid" 2>/dev/null || true
          echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" >"$LOCKDIR/ts" 2>/dev/null || true
          ps -p $$ -o args= 2>/dev/null >"$LOCKDIR/cmdline" 2>/dev/null || true
          CREATED_LOCK=1
        else
          printf '%s [AGENT-DIRECTOR] Autopilot summary: unable to acquire lock after cleaning stale owner; skipping\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >>"$LOGFILE" 2>/dev/null || true
          return 1
        fi
      else
        printf '%s [AGENT-DIRECTOR] Autopilot summary: already running (PID %s) owner_cmd="%s", waiting for completion\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$OWNER_PID" "$OWNER_META" >>"$LOGFILE" 2>/dev/null || true
        # Wait for the existing lock to clear (bounded by DIRECTOR_LOCK_WAIT_SECONDS)
        WAIT_SECONDS="${DIRECTOR_LOCK_WAIT_SECONDS:-120}"
        start_ts=$(date +%s)
        while [ -d "$LOCKDIR" ] && [ $(( $(date +%s) - start_ts )) -lt "$WAIT_SECONDS" ]; do
          sleep 1
        done
        if [ -d "$LOCKDIR" ]; then
          printf '%s [AGENT-DIRECTOR] Autopilot summary: existing lock (PID %s) did not clear after %s seconds; skipping this run\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$OWNER_PID" "$WAIT_SECONDS" >>"$LOGFILE" 2>/dev/null || true
          return 1
        fi
        # Attempt to acquire the lock now that it cleared
        if mkdir "$LOCKDIR" 2>/dev/null; then
          echo "$$" >"$LOCKDIR/pid" 2>/dev/null || true
          echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" >"$LOCKDIR/ts" 2>/dev/null || true
          ps -p $$ -o args= 2>/dev/null >"$LOCKDIR/cmdline" 2>/dev/null || true
          CREATED_LOCK=1
        else
          printf '%s [AGENT-DIRECTOR] Autopilot summary: unable to acquire lock after wait; skipping\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >>"$LOGFILE" 2>/dev/null || true
          return 1
        fi
      fi
    else
      # stale lockdir, try to remove and acquire
      OWNER_META_FILE="$LOCKDIR/cmdline"
      printf '%s [AGENT-DIRECTOR] Autopilot summary: cleaning stale lock (owner pid: %s, owner_cmd: %s)\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$OWNER_PID" "$( [ -f \"$OWNER_META_FILE\" ] && cat \"$OWNER_META_FILE\" || echo '' )" >>"$LOGFILE" 2>/dev/null || true
      rm -rf "$LOCKDIR" 2>/dev/null || true
      if mkdir "$LOCKDIR" 2>/dev/null; then
        echo "$$" >"$LOCKDIR/pid" 2>/dev/null || true
        echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" >"$LOCKDIR/ts" 2>/dev/null || true
        ps -p $$ -o args= 2>/dev/null >"$LOCKDIR/cmdline" 2>/dev/null || true
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

  # Redirect autopilot function stdout/stderr to director logfile to avoid duplicate console prints
  mkdir -p "$(dirname \"$LOGFILE\")" 2>/dev/null || true
  # Mirror director logfile to system log in near-real-time if SYSTEM_LOGFILE is set
  if [ -n "${SYSTEM_LOGFILE:-}" ]; then
    mkdir -p "$(dirname \"$SYSTEM_LOGFILE\")" 2>/dev/null || true
    TAIL_PIDFILE="${RUN_DIR:-$REPO_ROOT/run}/director-log-dup.pid"
    if command -v tail >/dev/null 2>&1; then
      if [ -f "$TAIL_PIDFILE" ] && kill -0 "$(cat \"$TAIL_PIDFILE\" 2>/dev/null)" 2>/dev/null; then
        :
      else
        # start a background tail that appends new director log lines to the system log
        ( tail -n 0 -F "$LOGFILE" 2>/dev/null | while IFS= read -r ln; do printf '%s\n' "$ln" >>"$SYSTEM_LOGFILE" 2>/dev/null || true; done ) &
        echo $! > "$TAIL_PIDFILE" 2>/dev/null || true
        printf '%s [AGENT-DIRECTOR] log-dup: started tail pid %s to mirror to %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$(cat \"$TAIL_PIDFILE\" 2>/dev/null || echo '')" "$SYSTEM_LOGFILE" >>"$LOGFILE" 2>/dev/null || true
      fi
    fi
  fi
  if [ -n "${SYSTEM_LOGFILE:-}" ]; then
    FIFO="${RUN_DIR:-$REPO_ROOT/run}/director.log.fifo"
    rm -f "$FIFO" 2>/dev/null || true
    mkfifo "$FIFO" 2>/dev/null || true
    ( tee -a "$LOGFILE" "$SYSTEM_LOGFILE" <"$FIFO" & )
    exec >"$FIFO" 2>&1
  else
    exec >>"$LOGFILE" 2>&1
  fi

  prompt_file=$(mktemp "/tmp/director_prompt_${run_ts}.XXXXXX") || prompt_file="/tmp/director_prompt_${run_ts}.$$"
if [ -f "$REPO_ROOT/scripts/lib/prompts.sh" ]; then
  show_prompt summarize > "$prompt_file"
else
  printf '%s [AGENT-DIRECTOR] Autopilot summary: prompts.sh missing; aborting\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >>"$LOGFILE" 2>/dev/null || true
  cleanup_lock
  trap - EXIT INT TERM
  return 1
fi

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
    for f in "$REPO_ROOT/scripts/setup.sh" "$REPO_ROOT/scripts/run.sh" "$REPO_ROOT/scripts/lib/daemon.sh" "$REPO_ROOT/scripts/lib/director.sh" "$REPO_ROOT/scripts/lib/actions.sh" "$REPO_ROOT/scripts/lib/patcher.sh" "$REPO_ROOT/scripts/skills/patch-repo.sh"; do
      if [ -r "$f" ]; then
        printf '\n--- %s (first 120 lines) ---\n' "$(basename "$f")"
        sed -n '1,120p' "$f" || true
      fi
    done
  } > "$context_file"

  combined_prompt=$(mktemp "/tmp/director_combined_${run_ts}.XXXXXX") || combined_prompt="$out_dir/combined_prompt.txt"
  cat "$context_file" "$prompt_file" > "$combined_prompt" || true

  # Ensure temp files are cleaned up when we exit
  cleanup_tmp() {
    rm -f "$prompt_file" "$context_file" "$out_dir"/combined_prompt_*.txt 2>/dev/null || true
  }
  trap 'cleanup_lock; cleanup_tmp' EXIT INT TERM

  printf '%s [AGENT-DIRECTOR] Autopilot summary: starting\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >>"$LOGFILE" 2>/dev/null || true
  printf '%s [AGENT-DIRECTOR] Autopilot summary: starting (audit dir: %s)\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$out_dir" >>"$LOGFILE" 2>/dev/null || true

  if command -v copilot >/dev/null 2>&1; then
    COPILOT_HELP=$(copilot --help 2>&1 || true)
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
    MAX_ATTEMPTS=3
    ATTEMPT=1
    usable=0
    while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
      rm -f "$summary_file" "$out_dir/copilot.err" 2>/dev/null || true
      # Recompute prompt for this attempt; add stricter retry instructions on subsequent attempts
      active_prompt="$combined_prompt"
      if [ "$ATTEMPT" -gt 1 ]; then
        retry_prompt="$out_dir/combined_prompt_${ATTEMPT}.txt"
        cp "$active_prompt" "$retry_prompt" 2>/dev/null || cat "$active_prompt" > "$retry_prompt"
        printf '\n\n--- RETRY INSTRUCTIONS ---\n' >> "$retry_prompt"
        printf '%s\n' 'IMPORTANT: Do not include shell traces, error messages like "Permission denied", or copilot CLI hints. Use only the REPO SNAPSHOT and produce a concise plain-text summary (6-12 lines). Output only the summary.' >> "$retry_prompt"
        active_prompt="$retry_prompt"
      fi
      printf '%s [AGENT-DIRECTOR] Autopilot summary: copilot attempt %d/%d\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$ATTEMPT" "$MAX_ATTEMPTS" >>"$LOGFILE" 2>/dev/null || true
      printf '%s [AGENT-DIRECTOR] Autopilot summary: attempting copilot (attempt %d/%d); stderr will be saved to %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$ATTEMPT" "$MAX_ATTEMPTS" "$out_dir/copilot.err" >>"$LOGFILE" 2>/dev/null || true

      # Read prompt content and pass via -p (non-interactive); use -s to output only agent response
      MAX_PROMPT_BYTES=81920
      PROMPT_TEXT=""
      if [ -f "$active_prompt" ]; then
        prompt_size=$(wc -c < "$active_prompt" 2>/dev/null || echo 0)
      else
        prompt_size=0
      fi
      if [ "$prompt_size" -gt "$MAX_PROMPT_BYTES" ]; then
        trimmed_prompt="$out_dir/combined_prompt_trimmed.txt"
        head -c "$MAX_PROMPT_BYTES" "$active_prompt" > "$trimmed_prompt" 2>/dev/null || cp "$active_prompt" "$trimmed_prompt" 2>/dev/null || true
        printf '\n\n[TRUNCATED: original prompt %d bytes > %d bytes]\n' "$prompt_size" "$MAX_PROMPT_BYTES" >> "$trimmed_prompt" || true
        PROMPT_TEXT=$(cat "$trimmed_prompt" 2>/dev/null || true)
        printf '%s [AGENT-DIRECTOR] Autopilot summary: trimmed prompt from %d to %d bytes for copilot invocation\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$prompt_size" "$MAX_PROMPT_BYTES" >>"$LOGFILE" 2>/dev/null || true
      else
        PROMPT_TEXT=$(cat "$active_prompt" 2>/dev/null || true)
      fi
      # Use timeout wrapper if available to limit copilot hang time
      TIMEOUT_CMD=""
      if command -v timeout >/dev/null 2>&1; then
        TIMEOUT_CMD="timeout ${DIRECTOR_COPILOT_TIMEOUT_SECONDS:-300}"
      fi

      # Determine isolation command to start copilot in its own session if available
      ISOLATE_CMD=""
      if command -v setsid >/dev/null 2>&1; then
        ISOLATE_CMD="setsid"
      fi

      # record start timestamp for diagnostics
      attempt_start_ts="$(date +'%Y-%m-%dT%H:%M:%S%z')"
      printf '%s\n' "$attempt_start_ts" > "$out_dir/copilot.start_ts" 2>/dev/null || true

      if [ -n "$TIMEOUT_CMD" ]; then
        # run copilot under timeout wrapper and in its own session to avoid signal leakage
        if $COPILOT_ENV $TIMEOUT_CMD $ISOLATE_CMD copilot -s -p "$PROMPT_TEXT" $COPILOT_OPTS >"$summary_file" 2>"$out_dir/copilot.err"; then
          copilot_status=0
        else
          copilot_status=$?
        fi
      else
        if $COPILOT_ENV $ISOLATE_CMD copilot -s -p "$PROMPT_TEXT" $COPILOT_OPTS >"$summary_file" 2>"$out_dir/copilot.err"; then
          copilot_status=0
        else
          copilot_status=$?
        fi
      fi

      # record end timestamp and exit code
      attempt_end_ts="$(date +'%Y-%m-%dT%H:%M:%S%z')"
      printf '%s\n' "$attempt_end_ts" > "$out_dir/copilot.end_ts" 2>/dev/null || true
      printf '%s\n' "exitcode:$copilot_status" > "$out_dir/copilot.exit" 2>/dev/null || true

      # Capture any copilot-related processes and a full ps snapshot for diagnostics
      ps -eo pid,ppid,pgid,cmd 2>/dev/null | grep -i 'copilot' | grep -v grep > "$out_dir/copilot.processlist" 2>/dev/null || true
      ps -eo pid,ppid,pgid,cmd 2>/dev/null > "$out_dir/ps_snapshot.txt" 2>/dev/null || true

      # write primary copilot pid/pgid if present
      if [ -s "$out_dir/copilot.processlist" ]; then
        awk 'NR==1 {print $1" "$3}' "$out_dir/copilot.processlist" > "$out_dir/copilot_pid_pgid" 2>/dev/null || true
        if [ -s "$out_dir/copilot_pid_pgid" ]; then
          read cp_pid cp_pgid < "$out_dir/copilot_pid_pgid" || true
          printf '%s\n' "$cp_pid" > "$out_dir/copilot.pid" 2>/dev/null || true
          printf '%s\n' "$cp_pgid" > "$out_dir/copilot.pgid" 2>/dev/null || true
        fi
      fi

      if [ -s "$summary_file" ]; then
        cleaned=$(mktemp "/tmp/director_cleaned_${run_ts}.XXXXXX") || cleaned="$summary_file"
        grep -i -v -E 'Permission denied|could not request permission|Try .*copilot --help|^\\$ |^\\s*✗|Reading README|Running parallel|Attempt to read|^\\s*\\$' "$summary_file" > "$cleaned" 2>/dev/null || cp "$summary_file" "$cleaned" 2>/dev/null || true
        if [ -s "$cleaned" ]; then
          mv "$cleaned" "$summary_file" 2>/dev/null || cp "$cleaned" "$summary_file" 2>/dev/null || true
          printf '%s [AGENT-DIRECTOR] Autopilot summary: copilot produced usable output on attempt %d\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$ATTEMPT" >>"$LOGFILE" 2>/dev/null || true
          printf '%s [AGENT-DIRECTOR] Autopilot summary: copilot produced usable output on attempt %d (summary: %s)\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$ATTEMPT" "$summary_file" >>"$LOGFILE" 2>/dev/null || true
          if [ -f "$out_dir/copilot.err" ] && [ -s "$out_dir/copilot.err" ]; then
            printf '%s [AGENT-DIRECTOR] copilot stderr (trimmed):\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >>"$LOGFILE" 2>/dev/null || true
            sed -n '1,50p' "$out_dir/copilot.err" >>"$LOGFILE" 2>/dev/null || true
          fi
          usable=1
          break
        else
          printf '%s [AGENT-DIRECTOR] Autopilot summary: copilot output contained only errors on attempt %d, retrying\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$ATTEMPT" >>"$LOGFILE" 2>/dev/null || true
          rm -f "$cleaned" 2>/dev/null || true
        fi
      else
        printf '%s [AGENT-DIRECTOR] Autopilot summary: copilot produced no output (exit %s) on attempt %d, stderr saved to %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$copilot_status" "$ATTEMPT" "$out_dir/copilot.err" >>"$LOGFILE" 2>/dev/null || true
        printf '%s [AGENT-DIRECTOR] Autopilot summary: copilot produced no output (exit %s) on attempt %d; check %s for details\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$copilot_status" "$ATTEMPT" "$out_dir/copilot.err" >>"$LOGFILE" 2>/dev/null || true
      fi

      ATTEMPT=$((ATTEMPT+1))
      sleep 1
    done

    if [ "$usable" -ne 1 ]; then
      if [ -s "$summary_file" ]; then
        cleaned=$(mktemp "/tmp/director_cleaned_${run_ts}.XXXXXX") || cleaned="$summary_file"
        grep -i -v -E 'Try .*copilot --help|^\$ |^\s*✗|Reading README|Running parallel|Attempt to read|^\s*\$' "$summary_file" > "$cleaned" 2>/dev/null || cp "$summary_file" "$cleaned" 2>/dev/null || true
        if [ -s "$cleaned" ]; then
          # do NOT fallback to local summarizer; preserve raw and sanitized outputs for diagnostics
          mv "$summary_file" "$out_dir/copilot_raw.txt" 2>/dev/null || cp "$summary_file" "$out_dir/copilot_raw.txt" 2>/dev/null || true
          mv "$cleaned" "$out_dir/copilot_sanitized.txt" 2>/dev/null || cp "$cleaned" "$out_dir/copilot_sanitized.txt" 2>/dev/null || true
          printf '%s [AGENT-DIRECTOR] Autopilot summary: sanitized copilot output saved to %s/copilot_sanitized.txt and raw to %s/copilot_raw.txt\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$out_dir" "$out_dir" >>"$LOGFILE" 2>/dev/null || true
          printf '%s [AGENT-DIRECTOR] Autopilot summary: copilot produced sanitized output after %d attempts but will NOT fallback; inspect %s/copilot_sanitized.txt\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$MAX_ATTEMPTS" "$out_dir" >>"$LOGFILE" 2>/dev/null || true
        else
          rm -f "$cleaned" 2>/dev/null || true
          mv "$summary_file" "$out_dir/copilot_raw.txt" 2>/dev/null || cp "$summary_file" "$out_dir/copilot_raw.txt" 2>/dev/null || true
          printf '%s [AGENT-DIRECTOR] Autopilot summary: copilot produced only artifacts after %d attempts; no usable summary\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$MAX_ATTEMPTS" >>"$LOGFILE" 2>/dev/null || true
        fi
      else
        printf '%s [AGENT-DIRECTOR] Autopilot summary: copilot failed to produce any output after %d attempts\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$MAX_ATTEMPTS" >>"$LOGFILE" 2>/dev/null || true
      fi

      # If copilot produced no stdout/stderr, write diagnostics to copilot.err for debugging
      if [ ! -s "$out_dir/copilot.err" ]; then
        {
          printf '=== copilot diagnostics (no stdout/stderr captured) ===\n'
          printf 'command -v copilot: %s\n' "$(command -v copilot 2>/dev/null || echo '(not found)')"
          printf 'which copilot: %s\n' "$(which copilot 2>/dev/null || echo '(not found)')"
          copilot --version 2>&1 || true
          printf 'PATH=%s\n' "$PATH"
          printf 'COPILOT_MODEL=%s\n' "${COPILOT_MODEL:-}"
          printf 'prompt head (first 8k bytes):\n'
          head -c 8192 "$active_prompt" 2>/dev/null || true
        } >> "$out_dir/copilot.err" 2>/dev/null || true
        printf '%s [AGENT-DIRECTOR] Autopilot summary: no copilot stderr captured; diagnostics written to %s/copilot.err\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$out_dir" >>"$LOGFILE" 2>/dev/null || true
      fi

      # After saving diagnostics, abort without local fallback
      printf '%s [AGENT-DIRECTOR] Autopilot summary: no usable summary produced; aborting (no local fallback)\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >>"$LOGFILE" 2>/dev/null || true
      cleanup_tmp || true
      cleanup_lock
      trap - EXIT INT TERM
      return 1
    fi
  fi

  
if ! command -v copilot >/dev/null 2>&1; then
  printf '%s [AGENT-DIRECTOR] Autopilot summary: copilot CLI not found; autopilot summary requires the copilot CLI\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >>"$LOGFILE" 2>/dev/null || true
  # Write an explicit summary file and abort; do NOT fallback to a local summarizer
  printf 'Copilot CLI not found; autopilot summary aborted.\n' >"$summary_file" 2>/dev/null || true
  cleanup_tmp || true
  cleanup_lock
  trap - EXIT INT TERM
  return 1
fi

  # Sanitize summary: remove obvious copilot-run artifacts and append (up to first 200 lines)
  if [ -s "$summary_file" ]; then
    # Preserve raw output for debugging
    mv "$summary_file" "$out_dir/copilot_raw.txt" 2>/dev/null || cp "$summary_file" "$out_dir/copilot_raw.txt" 2>/dev/null || true
    cleaned=$(mktemp "/tmp/director_cleaned_${run_ts}.XXXXXX") || cleaned="$out_dir/copilot_sanitized.txt"
    # filter out noise that looks like shell commands, permission errors, copilot help hints, or copilot planning artifacts
    grep -i -v -E 'Permission denied|could not request permission|Try .*copilot --help|^\\$ |^\\s*✗|\\bReading\\b|\\bPrint\\b|\\bAsked user:|\\bUser responded:|Marking the inspection|parallel tool call|report intent|Running repository environment checks|sh scripts/setup.sh --check|Shell execution is blocked|Attempt to read|^\\s*\\$' "$out_dir/copilot_raw.txt" > "$cleaned" 2>/dev/null || cp "$out_dir/copilot_raw.txt" "$cleaned" 2>/dev/null || true

    if [ -s "$cleaned" ]; then
      # Move sanitized version into the canonical summary file and keep copies
      mv "$cleaned" "$summary_file" 2>/dev/null || cp "$cleaned" "$summary_file" 2>/dev/null || true
      cp "$summary_file" "$out_dir/copilot_sanitized.txt" 2>/dev/null || true
      # copy sanitized summary to canonical last_summary so director can check
      cp "$summary_file" "$DEV_AUDITS_DIR/last_summary.txt" 2>/dev/null || true
      sed -n '1,200p' "$summary_file" >>"$LOGFILE" 2>/dev/null || true
      printf '%s [AGENT-DIRECTOR] Autopilot summary: sanitized copilot output saved to %s/copilot_sanitized.txt (raw: %s/copilot_raw.txt); canonical summary saved to %s/last_summary.txt\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$out_dir" "$out_dir" "$DEV_AUDITS_DIR" >>"$LOGFILE" 2>/dev/null || true

      # Prepare and print excerpt
      excerpt_raw=$(tr '\n' ' ' <"$summary_file" | sed 's/[[:space:]]\+/ /g' | sed 's/^ *//;s/ *$//')
      # determine length (bytes/chars) and truncate to 200 characters, appending "..." when truncated
      excerpt_len=$(printf '%s' "$excerpt_raw" | wc -c)
      excerpt_len=$(printf '%s' "$excerpt_len" | tr -d '[:space:]')
      if [ -n "$excerpt_len" ] && [ "$excerpt_len" -gt 200 ]; then
        excerpt=$(printf '%s' "$excerpt_raw" | cut -c 1-197)
        excerpt="${excerpt}..."
      else
        excerpt="$excerpt_raw"
      fi
      printf '%s [AGENT-DIRECTOR] summary excerpt: %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$excerpt" >>"$LOGFILE" 2>/dev/null || true

      # Also print a truncated head (first 6 lines) of the sanitized summary for visibility
      printf '%s [AGENT-DIRECTOR] summary head (first 6 lines):\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >>"$LOGFILE" 2>/dev/null || true

      awk 'length($0)>200 {print substr($0,1,197) "..."; next} {print}' "$summary_file" | sed -n '1,6p' >>"$LOGFILE" 2>/dev/null || true

      # After a successful sanitized summary, attempt to generate a prioritized itemized plan using Copilot
      if [ -s "$summary_file" ]; then
        printf '%s [AGENT-DIRECTOR] Autopilot plan: starting (using sanitized summary)\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >>"$LOGFILE" 2>/dev/null || true
        # run_autopilot_plan expects: out_dir, summary_file, context_file, combined_prompt
        if run_autopilot_plan "$out_dir" "$summary_file" "$context_file" "$combined_prompt"; then
          printf '%s [AGENT-DIRECTOR] Autopilot plan: generation completed for %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$out_dir" >>"$LOGFILE" 2>/dev/null || true
        else
          printf '%s [AGENT-DIRECTOR] Autopilot plan: generation failed for %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$out_dir" >>"$LOGFILE" 2>/dev/null || true
        fi
      fi
    else
      # Sanitization removed everything; keep raw for debugging and write a clear message into summary_file
      printf '%s [AGENT-DIRECTOR] Autopilot summary: copilot output contained only artifacts and was not suitable; raw output saved to %s/copilot_raw.txt\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$out_dir" >>"$LOGFILE" 2>/dev/null || true

      printf 'Copilot did not provide a usable summary: see copilot_raw.txt for full output.\n' >"$summary_file" 2>/dev/null || true
    fi
  else
    printf '%s [AGENT-DIRECTOR] Autopilot summary: no output to sanitize\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >>"$LOGFILE" 2>/dev/null || true
  fi

  # cleanup temp prompt/context/combined files and lock
  cleanup_tmp || true
  cleanup_lock
  trap - EXIT INT TERM
  return 0
}

# Generate a prioritized itemized plan (todo list) from the sanitized summary + repo snapshot using the copilot CLI.
# Parameters: out_dir, summary_file, context_file, combined_prompt
run_autopilot_plan() {
  out_dir="$1"
  summary_file="$2"
  context_file="$3"
  combined_prompt="$4"

  plan_ts="$(date +%Y%m%dT%H%M%S)"
  plan_in="$out_dir/plan_input.txt"
  plan_raw="$out_dir/plan_raw.txt"
  plan_err="$out_dir/copilot_plan.err"
  plan_sanitized="$out_dir/plan_sanitized.txt"
  plan_tasks="$out_dir/tasks.txt"
  plan_prompt_file=$(mktemp "/tmp/director_plan_prompt_${plan_ts}.XXXXXX") || plan_prompt_file="$out_dir/plan_prompt.txt"
if [ -f "$REPO_ROOT/scripts/lib/prompts.sh" ]; then
  show_prompt next > "$plan_prompt_file"
else
  printf '%s [AGENT-DIRECTOR] Autopilot plan: prompts.sh missing; aborting\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >>"$LOGFILE" 2>/dev/null || true
  return 1
fi

  # Build plan input (context + summary + plan instructions)
  cat "$context_file" "$summary_file" "$plan_prompt_file" > "$plan_in" 2>/dev/null || true

  if command -v copilot >/dev/null 2>&1; then
    COPILOT_HELP=$(copilot --help 2>&1 || true)
    COPILOT_OPTS=""
    if echo "$COPILOT_HELP" | grep -q -- '--model'; then
      COPILOT_OPTS="--model gpt-5-mini"
    elif echo "$COPILOT_HELP" | grep -q -- '--engine'; then
      COPILOT_OPTS="--engine gpt-5-mini"
    fi
    COPILOT_ENV="env COPILOT_MODEL=gpt-5-mini"

    MAX_ATTEMPTS=2
    ATTEMPT=1
    plan_usable=0
    while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
      printf '%s [AGENT-DIRECTOR] Autopilot plan: copilot attempt %d/%d\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$ATTEMPT" "$MAX_ATTEMPTS" >>"$LOGFILE" 2>/dev/null || true
      MAX_PROMPT_BYTES=81920
      PLAN_TEXT=""
      if [ -f "$plan_in" ]; then
        plan_size=$(wc -c < "$plan_in" 2>/dev/null || echo 0)
      else
        plan_size=0
      fi
      if [ "$plan_size" -gt "$MAX_PROMPT_BYTES" ]; then
        plan_trim="$out_dir/plan_input_trimmed.txt"
        head -c "$MAX_PROMPT_BYTES" "$plan_in" > "$plan_trim" 2>/dev/null || cp "$plan_in" "$plan_trim" 2>/dev/null || true
        printf '\n\n[TRUNCATED: original plan input %d bytes > %d bytes]\n' "$plan_size" "$MAX_PROMPT_BYTES" >> "$plan_trim" || true
        PLAN_TEXT=$(cat "$plan_trim" 2>/dev/null || true)
        printf '%s [AGENT-DIRECTOR] Autopilot plan: trimmed plan input from %d to %d bytes for copilot invocation\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$plan_size" "$MAX_PROMPT_BYTES" >>"$LOGFILE" 2>/dev/null || true
      else
        PLAN_TEXT=$(cat "$plan_in" 2>/dev/null || true)
      fi
      # Use timeout wrapper for plan generation if available
      TIMEOUT_CMD=""
      if command -v timeout >/dev/null 2>&1; then
        TIMEOUT_CMD="timeout ${DIRECTOR_COPILOT_TIMEOUT_SECONDS:-300}"
      fi
      # Determine isolation command for copilot plan invocation
      ISOLATE_CMD=""
      if command -v setsid >/dev/null 2>&1; then
        ISOLATE_CMD="setsid"
      fi
      if [ -n "$TIMEOUT_CMD" ]; then
        if $COPILOT_ENV $TIMEOUT_CMD $ISOLATE_CMD copilot -s -p "$PLAN_TEXT" $COPILOT_OPTS >"$plan_raw" 2>"$plan_err"; then
          :
        else
          :
        fi
      else
        if $COPILOT_ENV $ISOLATE_CMD copilot -s -p "$PLAN_TEXT" $COPILOT_OPTS >"$plan_raw" 2>"$plan_err"; then
          :
        fi
      fi
      if [ -s "$plan_raw" ]; then
        # Keep only obvious bullet or numbered lines and normalize numbering to bullets
        grep -E '^\s*-\s+|^\s*[0-9]+\.' "$plan_raw" > "$plan_sanitized" 2>/dev/null || cp "$plan_raw" "$plan_sanitized" 2>/dev/null || true
        sed 's/^[[:space:]]*[0-9][0-9]*\.\s*/- /' "$plan_sanitized" > "$plan_tasks" 2>/dev/null || cp "$plan_sanitized" "$plan_tasks" 2>/dev/null || true
        plan_usable=1
        break
      fi
      ATTEMPT=$((ATTEMPT+1))
      sleep 1
    done

    if [ $plan_usable -ne 1 ]; then
      printf '%s [AGENT-DIRECTOR] Autopilot plan: copilot did not produce a usable plan after %d attempts; raw saved to %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$MAX_ATTEMPTS" "$plan_raw" >>"$LOGFILE" 2>/dev/null || true
      return 1
    fi

    printf '%s [AGENT-DIRECTOR] Autopilot plan: plan saved to %s (tasks: %s)\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$out_dir" "$plan_tasks" >>"$LOGFILE" 2>/dev/null || true

    # Print a brief excerpt of the tasks to console for visibility (truncate lines to 200 chars)
    if [ -s "$plan_tasks" ]; then
      printf '%s [AGENT-DIRECTOR] plan excerpt:\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >>"$LOGFILE" 2>/dev/null || true
      # Truncate lines for logfile (first 12)
      awk 'length($0)>200 {print substr($0,1,197) "..."; next} {print}' "$plan_tasks" | sed -n '1,12p' >>"$LOGFILE" 2>/dev/null || true
    fi
  else
    printf '%s [AGENT-DIRECTOR] Autopilot plan: copilot CLI not found; skipping plan\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" >>"$LOGFILE" 2>/dev/null || true
    return 1
  fi

  rm -f "$plan_prompt_file" "$plan_in" 2>/dev/null || true
  return 0
}

# If the script is executed directly with the "run" argument, invoke the autopilot summary.
# This allows running: sh scripts/lib/actions.sh run
if [ "$(basename "$0")" = "actions.sh" ] && [ "${1:-}" = "run" ]; then
  run_autopilot_summary
fi
