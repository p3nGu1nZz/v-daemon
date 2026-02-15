#!/usr/bin/env sh
# Helpers for safe process termination and lock cleanup
# normalize_cmd: normalize cmdline string (convert NULs to spaces, collapse whitespace)
normalize_cmd() {
  printf '%s' "$1" 2>/dev/null | tr '\0' ' ' | sed -E 's/[[:space:]]+/ /g' | sed -E 's/^ //; s/ $//'
}

# collect_descendants using pgrep if available, fallback to ps-based traversal
collect_descendants_pgrep() {
  parent="$1"
  children=""
  if command -v pgrep >/dev/null 2>&1; then
    for c in $(pgrep -P "$parent" 2>/dev/null || true); do
      children="$children $c"
      more=$(collect_descendants_pgrep "$c")
      if [ -n "$more" ]; then
        children="$children $more"
      fi
    done
  fi
  printf '%s' "$children"
}

collect_descendants_ps() {
  parent="$1"
  out="$parent"
  # Build descendant list iteratively
  while :; do
    found=""
    for pair in $(ps -eo pid,ppid | awk 'NR>1 {print $1":"$2}'); do
      pid=${pair%:*}
      ppid=${pair#*:}
      for p in $out; do
        if [ "$ppid" = "$p" ] && ! printf '%s' "$out" | grep -w -q "$pid"; then
          found="$found $pid"
        fi
      done
    done
    if [ -z "$found" ]; then
      break
    fi
    out="$out $found"
  done
  # return descendants (exclude the parent itself)
  printf '%s' "$out" | awk '{for(i=2;i<=NF;i++) printf "%s ",$i}'
}

collect_descendants() {
  parent="$1"
  if command -v pgrep >/dev/null 2>&1; then
    collect_descendants_pgrep "$parent" | tr '\n' ' '
  else
    collect_descendants_ps "$parent"
  fi
}

# proc_kill_tree: kill a process and its descendants safely (UID check)
proc_kill_tree() {
  pid="$1"
  if [ -z "$pid" ]; then
    return 1
  fi
  # collect descendants
  descendants="$(collect_descendants "$pid")"
  list=""
  for d in $descendants; do list="$list $d"; done
  list="$list $pid"
  # reverse order for killing children before parents
  reversed=$(printf "%s\n" $list | awk '{a[NR]=$0} END{for(i=NR;i>=1;i--) print a[i]}')
  CUR_UID="$(id -u 2>/dev/null || echo '')"
  for p in $reversed; do
    p_uid="$(ps -o uid= -p "$p" 2>/dev/null | tr -d '[:space:]' || echo '')"
    if [ -z "$p_uid" ] || [ "$p_uid" != "$CUR_UID" ]; then
      printf '%s\n' "proc_kill_tree: pid $p owned by uid $p_uid does not match current uid $CUR_UID" 1>&2
      return 2
    fi
  done
  # Try graceful termination
  for p in $reversed; do kill -TERM "$p" 2>/dev/null || true; done
  sleep 2
  for p in $reversed; do if kill -0 "$p" 2>/dev/null; then kill -9 "$p" 2>/dev/null || true; fi; done
  return 0
}
