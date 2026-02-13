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

- Helper script: scripts/skills/patch-repo.sh — commits staged changes and pushes by default (no --no-push). The script re-execs under bash when invoked with sh, performs up to 3 push retries on failure, and exits non-zero if pushes fail so calling agents can detect and react to errors.
- Behavior: stages all changes with `git add .`, creates a deterministic commit `update:<tree-hash>` using `git write-tree` and `git commit`, then attempts to push; when no upstream is configured the first push uses `git push -u origin <branch>`.
- Agent guidance: invoke `sh scripts/skills/patch-repo.sh` (the script will re-exec to bash if needed). Ensure git credentials and remotes are configured (SSH key or token) and avoid targeting protected branches in automated runs. After execution, parse `run/skills/patch-repo/<timestamp>/report.json` and check `pushed` and `exit_code` to confirm success; inspect `stdout.txt`/`stderr.txt` for details.
- Partial patches & cherry-picks: if an agent must commit a subset of changes, prepare the index (e.g., `git add -p` or use `GIT_INDEX_FILE`) before invoking this script; consider lower-level git commands for advanced workflows.
- Troubleshooting / manual steps that fixed recent pushes: check `git status -sb` to see upstream and ahead counts, set upstream with `git push -u origin <branch>` when missing, and run `git push` to publish local commits (this was used to publish 5 local commits which updated remote to 355bf26).
- Tuning suggestions: consider adding a dry-run flag, a selective-file mode, or explicit max-retries/config options for agents; ensure CI and agents have network access and appropriate git authentication.

## References

- scripts/skills/patch-repo.sh
- scripts/skills/patch-repo.sh (wrapper)
