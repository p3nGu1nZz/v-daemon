---
name: review-repo
description: "Perform a repo-wide code and documentation review focused on autonomy, agent swarm design, security, and decentralization; produce structured summaries and raw captures."
---

# SKILL: review-repo

## Summary

Perform a repository-wide code and documentation review that focuses on alignment with the prime directive: building an autonomous agent swarm that self-improves, optimizes, evolves, and provides secure, decentralized networking to extend Copilot CLI and Copilot SDK.

## When to run

- After `review-repo` and before `next-steps`.
- Periodically during planning cycles or before major design decisions.

## Inputs

- allow_run (bool, default: false) — when true, safe runtime checks and linters may be invoked.
- include_globs (array) — optional list of glob patterns to limit review scope.
- output_format (string): `text` or `json`.
- safety_controls (optional) — configuration keys such as `director.allow_execute` and corresponding env `V_DAEMON_ALLOW_EXECUTE` can be used to prevent runtime actions (default: disabled).

## Outputs

- run/skills/review-repo/<timestamp>/review.txt  (readable stakeholder summary — informational only)
- run/skills/review-repo/<timestamp>/review.json (structured results)
- run/skills/review-repo/<timestamp>/raw/...      (raw captures used to build the report)

## Collection steps

1. Capture git metadata and top-level layout.
2. Preview core docs: README.md, AGENT.md, doc/, docs/.
3. List scripts and capture shebangs/headers.
4. Detect TODO/FIXME and capture context.
5. Search for domain keywords: agent, swarm, autonomous, self-improve, evolve, optimize, decentralized, secure, copilot, supervisor, daemon, director.
6. Produce a structured JSON with counts, file-type breakdown, and raw captures.
7. Produce a short readable summary that comments on alignment with the prime directive and suggests next steps; this summary is informational and does not require manual approval.

## JSON schema (recommended fields)

{
  "repo":"", "head":"", "timestamp":"", "todo_count":0,
  "keyword_matches":0, "file_types":[], "notes":"", "alignment_estimate":"",
  "recommended_next_steps":[]
}

## Quality rules

- Readable summary: 4–8 sentences; informational-only; state degree of alignment, major gaps, and 3 recommended PR-sized next steps.
- Always write raw captures to run/skills/review-repo/<timestamp>/raw/.
- Avoid making network changes or installing packages unless `allow_run=true`.

## Implementation notes

- A helper script is provided at `scripts/skills/review-repo.sh` that performs the data collection.
- Prefer running the script with: `sh scripts/skills/review-repo.sh --allow-run` when safe checks are desired.
