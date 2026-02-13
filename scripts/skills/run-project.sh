#!/bin/sh
set -eu

usage() { echo "Usage: $0 [status]"; exit 1; }

cmd="$1"
if [ -z "$cmd" ]; then cmd="status"; fi

timestamp=$(date -u +"%Y%m%dT%H%M%SZ")
out="run/skills/run-project/$timestamp"
mkdir -p "$out/raw"

if command -v sh >/dev/null 2>&1; then
  if [ -x "scripts/run.sh" ]; then
    sh scripts/run.sh status >"$out/status.txt" 2>&1 || true
  else
    echo "no scripts/run.sh present" >"$out/status.txt"
  fi
fi

echo "Wrote outputs to $out"
