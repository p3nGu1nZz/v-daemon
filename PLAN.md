# PLAN: Short-term updates and next steps (2026-02-13)

Problem statement

Centralize environment helper loading, prevent duplicate sourcing, and harden repository scripts for portability and robustness across Linux and macOS/BSD. Ensure skills are discoverable by Copilot CLI and update documentation to reflect recent changes.

What changed (summary)

- Centralized helper loading in scripts/lib/env.sh via env_init, added _V_DAEMON_ENV_INIT_DONE guard to make it idempotent.
- Replaced non-portable constructs (sed -i, ps -eo, grep flags, timeout) with portable fallbacks (mktemp-based in-place edits, ps_fallback, find|xargs -0 grep, timeout fallbacks).
- Fixed update-docs to create OUT/RAW directories and added guards to avoid missing-file errors.
- Improved SKILL.md short descriptions for better Copilot discovery.

Immediate TODOs

1. Commit changes with a clear message: "docs: update TODO/PLAN/README and SKILL.md descriptions; centralize env and harden scripts"
2. Run shellcheck across scripts (recommended) and address remaining portability warnings.
3. (Optional / Defer to M1) Test on macOS/BSD (CI matrix) to validate ps_fallback and other fallbacks; prioritize after core Linux validation.
4. (Optional / Defer to M1) Convert remaining ls-based loops to find -print0/xargs -0 for full NUL-safety where filenames may contain newlines.
5. Add a CI job to run scripts/setup.sh --check and basic script smoke tests on Linux and macOS.
6. Ensure scripts/setup.sh includes a `--clean` mode and verify `docs/specs/_template.md` exists; test `scripts/docs.sh build` to produce compiled guide and optional PDF.

7. NOTE: The following items were already applied and pushed to main:
   - Ensure scripts/setup.sh creates run/ and logs/ (scripts/setup.sh)
   - Add AGENT.md (AGENT.md)
   - Add GitHub Actions workflow to run scripts/setup.sh --check (.github/workflows/setup-check.yml)
   - Improve review-repo and next-steps compatibility and outputs (scripts/skills/review-repo.sh, scripts/skills/next-steps.sh)
   - Insert safe placeholders for daemon and director autopatch logic (scripts/lib/daemon.sh, scripts/lib/director.sh)

6. NOTE: The following items were already applied and pushed to main:
   - Ensure scripts/setup.sh creates run/ and logs/ (scripts/setup.sh)
   - Add AGENT.md (AGENT.md)
   - Add GitHub Actions workflow to run scripts/setup.sh --check (.github/workflows/setup-check.yml)
   - Improve review-repo and next-steps compatibility and outputs (scripts/skills/review-repo.sh, scripts/skills/next-steps.sh)
   - Insert safe placeholders for daemon and director autopatch logic (scripts/lib/daemon.sh, scripts/lib/director.sh)

Acceptance criteria

- Changes committed with documentation updated.
- Shellcheck warnings triaged or documented.
- CI demonstrates basic script start/stop on supported platforms.

Notes

This PLAN.md is intentionally brief and actionable; expand into more detailed tasks in the todos tracker or project board as needed.
