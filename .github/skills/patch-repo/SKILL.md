---
name: patch-repo
description: "Create deterministic git patches (stage/commit) and optionally push safely; writes audit reports under run/skills/patch-repo (scripts/skills/patch-repo.sh)."
---

# SKILL: patch-repo

## Summary

Automate a simple SCM workflow to stage all changes, create a deterministic commit message (update:<tree-hash>), and optionally push to upstream using scripts/skills/patch-repo.sh. The skill captures stdout/stderr and writes a structured report under run/skills/patch-repo/<timestamp>/ for auditing and troubleshooting.

## When to run

- When local changes are ready to be saved as a patch and optionally pushed upstream.
- Useful for agents that need to persist work by creating commits or preparing patches for review.

## Inputs

- args (array) — arguments forwarded to scripts/skills/patch-repo.sh (e.g., ['--no-push']).
- allow_push (bool, default: false) — when false, the agent should run with --no-push to avoid remote changes.

## Outputs

- run/skills/patch-repo/<timestamp>/stdout.txt
- run/skills/patch-repo/<timestamp>/stderr.txt
- run/skills/patch-repo/<timestamp>/report.json — { "commit":"<sha>", "pushed":true|false, "branch":"", "upstream":"", "status":"ok"|"failed", "notes":"" }
- run/skills/patch-repo/<timestamp>/status.txt — git --no-pager status output after completion

## Execution steps

1. Verify inside a git repository and capture working tree state and branch.
2. If allow_push is false, ensure --no-push is passed to scripts/skills/patch-repo.sh.
3. Run scripts/skills/patch-repo.sh, capturing stdout/stderr to run/skills/patch-repo/<timestamp>/.
4. After execution, verify that the created commit was successfully pushed when pushing is permitted. Parse the skill report (report.json) or inspect remote state to determine push success. If the push failed and allow_push is true, retry pushing up to 3 times (capturing stdout/stderr for each attempt) before giving up; record each attempt and any errors in the run/skills/patch-repo/<timestamp>/ outputs.
5. If any attempt succeeds, mark pushed=true and write the final report.json and status.txt. If all attempts fail after 3 retries, set status="failed", include details in notes (e.g., last push error), and exit with a non-zero error code so calling agents detect the failure.
6. On non-push failures (e.g., commit creation failed), capture git status and git log -n 5 and include error details in report.json.

## Quality rules & safety

- Do not push to protected branches (main, master, release) without explicit approval.
- Prefer running with --no-push for review; pushing requires allow_push true and explicit consent.
- Do not perform remote network operations; only perform git operations on configured remotes.

## Implementation notes

- Helper script: scripts/skills/patch-repo.sh — wrapper that invokes scripts/skills/patch-repo.sh and captures outputs.
- Example: sh scripts/skills/patch-repo.sh --no-push

## References

- scripts/skills/patch-repo.sh
- scripts/skills/patch-repo.sh (wrapper)
