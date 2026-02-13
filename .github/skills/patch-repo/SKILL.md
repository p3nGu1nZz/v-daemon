---
name: patch-repo
description: "Create deterministic git patches (stage/commit) and optionally push safely; writes audit reports under run/skills/patch-repo (scripts/skills/patch-repo.sh)."
---

# SKILL: patch-repo

## Summary

Automate a simple SCM workflow to stage all changes, create a deterministic commit message (update:<tree-hash>), and push to upstream by default using scripts/skills/patch-repo.sh. The skill captures stdout/stderr and writes a structured report under run/skills/patch-repo/<timestamp>/ for auditing and troubleshooting.

## When to run

- When local changes are ready to be saved as a patch and optionally pushed upstream.
- Useful for agents that need to persist work by creating commits or preparing patches for review.

## Inputs

- args (array) — arguments forwarded to scripts/skills/patch-repo.sh (only --help is supported; the script pushes by default).


## Outputs

- run/skills/patch-repo/<timestamp>/stdout.txt
- run/skills/patch-repo/<timestamp>/stderr.txt
- run/skills/patch-repo/<timestamp>/report.json — { "commit":"<sha>", "pushed":true|false, "branch":"", "upstream":"", "status":"ok"|"failed", "notes":"" }
- run/skills/patch-repo/<timestamp>/status.txt — git --no-pager status output after completion

## Execution steps

1. Verify inside a git repository and capture working tree state and branch.
2. The skill pushes commits by default; ensure the calling agent has permission to push to the target remote/branch and avoid protected branches unless explicitly allowed.
3. Run scripts/skills/patch-repo.sh, capturing stdout/stderr to run/skills/patch-repo/<timestamp>/.
4. After execution, verify that the created commit was successfully pushed; the script will retry pushing up to 3 times before failing. Record each attempt and any errors in the run/skills/patch-repo/<timestamp>/ outputs.
5. If any attempt succeeds, mark pushed=true and write the final report.json and status.txt. If all attempts fail after 3 retries, set status="failed", include details in notes (e.g., last push error), and exit with a non-zero error code so calling agents detect the failure.
6. On non-push failures (e.g., commit creation failed), capture git status and git log -n 5 and include error details in report.json.

## Quality rules & safety

- Do not push to protected branches (main, master, release) without explicit approval.
- This skill pushes by default; ensure protected branches are not targeted by automated runs without explicit consent.
- Do not perform remote network operations; only perform git operations on configured remotes.

## Implementation notes

- Helper script: scripts/skills/patch-repo.sh — wrapper that invokes scripts/skills/patch-repo.sh and captures outputs.
- Example: sh scripts/skills/patch-repo.sh

## References

- scripts/skills/patch-repo.sh
- scripts/skills/patch-repo.sh (wrapper)
