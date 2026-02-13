#!/usr/bin/env bash
# hfsm.sh - Hierarchical Finite State Machine library for shell scripts
#
# Lightweight HFSM implementation for bash. Intended to be sourced by other
# scripts to organize logic into hierarchical states with enter/exit handlers
# and event-based handlers that may trigger transitions.
#
# API:
#  hfsm_create <name>
#  hfsm_add_state <hfsm> <state> [parent]
#  hfsm_set_enter <hfsm> <state> <fn>
#  hfsm_set_exit <hfsm> <state> <fn>
#  hfsm_set_handler <hfsm> <state> <event> <fn>
#  hfsm_init <hfsm> <initial_state>
#  hfsm_current <hfsm>    # prints current state
#  hfsm_transition <hfsm> <target_state>
#  hfsm_dispatch <hfsm> <event> [args...]
#  hfsm_push <hfsm> <state>
#  hfsm_pop <hfsm>
#  hfsm_destroy <hfsm>
#
# Notes:
# - State names should be simple tokens (no newlines). Parent states form the
#   hierarchy. Handlers are shell function names or commands which are invoked
#   with arguments: <hfsm> <state> <event> [event-args...].
#
# Example:
#   hfsm_create myfsm
#   hfsm_add_state myfsm idle
#   hfsm_add_state myfsm running idle
#   hfsm_set_enter myfsm running on_enter_running
#   hfsm_set_handler myfsm running STOP on_stop
#   hfsm_init myfsm idle
#

# Create a new HFSM namespace
hfsm_create() {
  local name="$1"
  if [ -z "$name" ]; then
    echo "hfsm_create: name required" >&2
    return 1
  fi
  eval "declare -g -A ${name}__parent=()"
  eval "declare -g -A ${name}__enter=()"
  eval "declare -g -A ${name}__exit=()"
  eval "declare -g -A ${name}__handlers=()"
  eval "declare -g ${name}__current=''"
  eval "declare -g -a ${name}__stack=()"
}

hfsm_add_state() {
  local h="$1" s="$2" p="${3:-}"
  if [ -z "$h" ] || [ -z "$s" ]; then
    echo "hfsm_add_state: hfsm and state required" >&2
    return 1
  fi
  eval "${h}__parent[\"$s\"]=\"$p\""
}

hfsm_set_enter() {
  local h="$1" s="$2" fn="$3"
  if [ -z "$h" ] || [ -z "$s" ]; then
    echo "hfsm_set_enter: hfsm and state required" >&2
    return 1
  fi
  eval "${h}__enter[\"$s\"]=\"$fn\""
}

hfsm_set_exit() {
  local h="$1" s="$2" fn="$3"
  if [ -z "$h" ] || [ -z "$s" ]; then
    echo "hfsm_set_exit: hfsm and state required" >&2
    return 1
  fi
  eval "${h}__exit[\"$s\"]=\"$fn\""
}

hfsm_set_handler() {
  local h="$1" s="$2" event="$3" fn="$4"
  if [ -z "$h" ] || [ -z "$s" ] || [ -z "$event" ] || [ -z "$fn" ]; then
    echo "hfsm_set_handler: hfsm, state, event and fn required" >&2
    return 1
  fi
  eval "${h}__handlers[\"$s::$event\"]=\"$fn\""
}

hfsm_current() {
  local h="$1"
  eval "printf '%s' \"\${${h}__current}\""
}

# internal helper: build ancestors array (state->root)
_hfsm_build_ancestors() {
  local h="$1" state="$2"
  local -a out=()
  local cur="$state"
  while [ -n "$cur" ]; do
    out+=("$cur")
    local parent
    eval "parent=\${${h}__parent[\"$cur\"]}"
    cur="$parent"
  done
  printf '%s\n' "${out[@]}"
}

hfsm_transition() {
  local h="$1" target="$2"
  if [ -z "$h" ] || [ -z "$target" ]; then
    echo "hfsm_transition: hfsm and target required" >&2
    return 1
  fi

  local cur
  eval "cur=\${${h}__current}"
  if [ "$cur" = "$target" ]; then
    return 0
  fi

  # build ancestors lists (state -> root)
  local cur_list target_list
  cur_list="$(_hfsm_build_ancestors "$h" "$cur")"
  target_list="$(_hfsm_build_ancestors "$h" "$target")"

  IFS=$'\n' read -r -a cur_arr <<< "$cur_list"
  IFS=$'\n' read -r -a target_arr <<< "$target_list"

  # reverse to root->state
  local -a cur_rev=()
  for ((i=${#cur_arr[@]}-1;i>=0;i--)); do cur_rev+=( "${cur_arr[i]}" ); done
  local -a target_rev=()
  for ((i=${#target_arr[@]}-1;i>=0;i--)); do target_rev+=( "${target_arr[i]}" ); done

  # find least common ancestor (LCA)
  local lca=""
  local i=0
  while [ $i -lt ${#cur_rev[@]} ] && [ $i -lt ${#target_rev[@]} ]; do
    if [ "${cur_rev[$i]}" = "${target_rev[$i]}" ]; then
      lca="${cur_rev[$i]}"
    else
      break
    fi
    i=$((i+1))
  done

  # call exit handlers from current up to (but excluding) LCA
  local idx=0
  while [ $idx -lt ${#cur_arr[@]} ]; do
    local s="${cur_arr[$idx]}"
    if [ "$s" = "$lca" ]; then break; fi
    local fn
    eval "fn=\${${h}__exit[\"$s\"]}"
    if [ -n "$fn" ] && command -v "$fn" >/dev/null 2>&1; then
      "$fn" "$h" "$s" "$target"
    fi
    idx=$((idx+1))
  done

  # call enter handlers from LCA child down to target
  local start=0
  if [ -n "$lca" ]; then
    for ((j=0;j<${#target_rev[@]};j++)); do
      if [ "${target_rev[$j]}" = "$lca" ]; then
        start=$((j+1))
        break
      fi
    done
  fi
  for ((j=start;j<${#target_rev[@]};j++)); do
    local s="${target_rev[$j]}"
    local fn
    eval "fn=\${${h}__enter[\"$s\"]}"
    if [ -n "$fn" ] && command -v "$fn" >/dev/null 2>&1; then
      "$fn" "$h" "$s" "$cur"
    fi
  done

  # set current
  eval "${h}__current=\"$target\""
  return 0
}

hfsm_init() { local h=$1 init="$2"; eval "${h}__current=''" ; hfsm_transition "$h" "$init"; }

hfsm_dispatch() {
  local h="$1" event="$2"
  shift 2 || true
  local args=("$@")
  local cur
  eval "cur=\${${h}__current}"
  local s="$cur"
  while [ -n "$s" ]; do
    local handler
    eval "handler=\${${h}__handlers[\"$s::$event\"]}"
    if [ -n "$handler" ] && command -v "$handler" >/dev/null 2>&1; then
      local raw out
      raw="$("$handler" "$h" "$s" "$event" "${args[@]}")"
      # Extract last non-empty line of handler output as next-state (robust against debug logs)
      out="$(printf '%s\n' "$raw" | awk 'NF{line=$0} END{print line}')"
      # if handler printed a state name, transition to it
      if [ -n "$out" ]; then
        hfsm_transition "$h" "$out"
      fi
      return 0
    fi
    eval "s=\${${h}__parent[\"$s\"]}"
  done
  return 1
}

hfsm_push() {
  local h="$1" target="$2"
  local cur
  eval "cur=\${${h}__current}"
  # push current (may be empty)
  eval "${h}__stack+=(\"\$cur\")"
  hfsm_transition "$h" "$target"
}

hfsm_pop() {
  local h="$1"
  # pop last pushed state and return it on stdout (empty if none)
  local top=""
  local len
  eval "len=\${#${h}__stack[@]}"
  if [ "${len:-0}" -gt 0 ]; then
    eval "top=\${${h}__stack[$((len-1))]}"
    eval "tmp=(\"\${${h}__stack[@]:0:$((len-1))}\")"
    eval "${h}__stack=(\"\${tmp[@]}\")"
  else
    top=""
  fi
  printf '%s' "$top"
}

hfsm_pop_and_restore() {
  local h="$1"
  local prev
  prev="$(hfsm_pop "$h")"
  if [ -n "$prev" ]; then
    hfsm_transition "$h" "$prev"
    return 0
  fi
  return 1
}

hfsm_states() {
  local h="$1"
  eval "for _s in \\${!${h}__parent[@]}; do printf '%s\\n' \"\$_s\"; done"
}

hfsm_destroy() {
  local h="$1"
  eval "unset -v ${h}__current ${h}__stack ${h}__parent ${h}__enter ${h}__exit ${h}__handlers 2>/dev/null || true"
}

# End of hfsm.sh
