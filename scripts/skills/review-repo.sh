#!/bin/sh
set -eu

usage() {
  echo "Usage: $0 [--allow-run] [--output json|text]"
  exit 1
}

ALLOW_RUN=false
OUT_FMT="text"

while [ $# -gt 0 ]; do
  case "$1" in
    --allow-run) ALLOW_RUN=true; shift ;;
    --output) OUT_FMT="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) shift ;;
  esac
done

timestamp=$(date -u +"%Y%m%dT%H%M%SZ")
out="run/skills/review-repo/$timestamp"
mkdir -p "$out/raw"

# git metadata
git_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if [ -n "$git_root" ]; then
  git rev-parse --verify HEAD 2>/dev/null >"$out/raw/head_sha.txt" || true
  git log -1 --pretty=format:"%H %an %ad %s" --date=iso >"$out/raw/head_log.txt" 2>/dev/null || true
  git status --porcelain >"$out/raw/git_status.txt" 2>/dev/null || true
fi

# top-level layout
ls -la >"$out/raw/ls_top.txt" 2>/dev/null || true

# preview core docs
for f in README.md AGENT.md; do
  if [ -f "$f" ]; then
    head -n 400 "$f" >"$out/raw/$(basename "$f")"
  fi
done

for d in doc docs; do
  if [ -d "$d" ]; then
    find "$d" -maxdepth 2 -type f -print0 2>/dev/null | xargs -0 -I{} sh -c 'echo "== {} =="; head -n 200 "{}"' >"$out/raw/${d}_preview.txt" 2>/dev/null || true
  fi
done

# scripts and shebangs
find . -path "./.git" -prune -o -path "./run" -prune -o -path "./logs" -prune -o -type f -print0 2>/dev/null | xargs -0 grep -InE "^#!.*(sh|bash|python|node|perl)" >"$out/raw/shebangs.txt" 2>/dev/null || true

# TODOs / FIXMEs
find . -path "./.git" -prune -o -type f -print0 2>/dev/null | xargs -0 grep -InE "TODO|FIXME" >"$out/raw/todos.txt" 2>/dev/null || true
todo_count=$(wc -l <"$out/raw/todos.txt" 2>/dev/null || echo 0)

# keyword search relevant to prime directive
keywords="agent|swarm|autonom|self[- ]?improv|self[- ]?optimi|evolv|optimi|decentral|secure|copilot|supervisor|daemon|director"
find . -path "./.git" -prune -o -type f -print0 2>/dev/null | xargs -0 grep -InE "$keywords" >"$out/raw/keywords.txt" 2>/dev/null || true
keyword_count=$(wc -l <"$out/raw/keywords.txt" 2>/dev/null || echo 0)

# file type summary
find . -path "./.git" -prune -o -type f -name "*.*" -print | sed 's|^\./||' >"$out/raw/file_list.txt" 2>/dev/null || true
awk -F. '{ if (NF>1) print $NF }' "$out/raw/file_list.txt" | sort | uniq -c | sort -nr >"$out/raw/file_types.txt" 2>/dev/null || true

# basic alignment heuristic
alignment="unknown"
score=0
if [ "$keyword_count" -ge 10 ]; then score=$((score+2)); fi
if [ "$keyword_count" -ge 3 ]; then score=$((score+1)); fi
if [ "$todo_count" -gt 0 ]; then score=$((score-1)); fi

if [ "$score" -ge 3 ]; then alignment="strong"
elif [ "$score" -ge 1 ]; then alignment="partial"
elif [ "$score" -ge 0 ]; then alignment="weak"
else alignment="needs-work"
fi

head_sha=$(cat "$out/raw/head_sha.txt" 2>/dev/null || echo "")

# write JSON
cat >"$out/review.json" <<EOF
{
  "repo":"$(basename "$PWD")",
  "timestamp":"$timestamp",
  "head":"$head_sha",
  "todo_count": ${todo_count:-0},
  "keyword_matches": ${keyword_count:-0},
  "alignment_estimate":"$alignment",
  "notes":"",
  "recommended_next_steps":[]
}
EOF

# create compat summary.json
cp "$out/review.json" "$out/summary.json" 2>/dev/null || true

# human summary
{
  echo "Repository review for $(basename "$PWD") at $timestamp"
  echo ""
  if [ -n "$head_sha" ]; then
    echo "Latest commit: $(cat "$out/raw/head_log.txt" 2>/dev/null || echo "$head_sha")"
  fi
  echo ""
  echo "Detected $todo_count TODO/FIXME mentions and $keyword_count keyword matches related to autonomy/decentralization/security."
  echo ""
  echo "File types (top 10):"
  sed -n '1,10p' "$out/raw/file_types.txt" 2>/dev/null || true
  echo ""
  echo "Alignment estimate: $alignment"
  echo ""
  echo "Recommendations:"
  echo "- Inspect run/skills/review-repo/$timestamp/raw/todos.txt for outstanding work items."
  echo "- Run linters and security scanners (requires --allow-run) and feed the outputs into `review-repo` + LLM for a richer alignment assessment."
  echo "- Create small PRs (see next-steps) to address highest-impact gaps."
} >"$out/review.txt"

if [ "$OUT_FMT" = "json" ]; then
  cat "$out/review.json"
else
  cat "$out/review.txt"
fi

echo "Wrote outputs to $out"
