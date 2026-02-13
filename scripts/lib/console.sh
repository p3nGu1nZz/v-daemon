#!/usr/bin/env sh
# Console helpers: print status and truncated excerpts to console (stderr).

console_status_line() {
  ts="$(date +'%Y-%m-%dT%H:%M:%S%z')"
  printf '%s [SYSTEM] %s\n' "$ts" "$*" >&2
}

console_supervisor() {
  ts="$(date +'%Y-%m-%dT%H:%M:%S%z')"
  printf '%s [SUPERVISOR] %s\n' "$ts" "$*" >&2
}

console_agent() {
  ts="$(date +'%Y-%m-%dT%H:%M:%S%z')"
  printf '%s [AGENT-DIRECTOR] %s\n' "$ts" "$*" >&2
}

console_truncate() {
  text="$*"
  len=$(printf '%s' "$text" | wc -c)
  if [ "$len" -gt 200 ]; then
    printf '%s' "$(printf '%s' "$text" | cut -c 1-197)..."
  else
    printf '%s' "$text"
  fi
}

console_print_file_head_truncated() {
  file="$1"
  lines="${2:-6}"
  if [ ! -f "$file" ]; then
    return 0
  fi
  awk 'length($0)>200 {print substr($0,1,197) "..."; next} {print}' "$file" | sed -n "1,${lines}p" >&2 || true
}
