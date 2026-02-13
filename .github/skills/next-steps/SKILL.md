---
name: next-steps
description: "Produce a prioritized, actionable task list (<=20) from a repo summary with acceptance criteria, complexity, impact, and suggested branches/PRs."
---

# SKILL: next-steps

## Summary

Generate a comprehensive but concise set (no more than 20) of prioritized next steps from `summary.json`. Items should cover fixes, enhancements, refactors, new features, and documentation. Each item must include acceptance criteria, a complexity score (1-5), an impact level (low|medium|high), and suggested branch/commit messages.

## When to run

- Immediately after `review-repo` completes.

## Inputs

- `summary_path` (required)
- `allow_insert_todos` (bool, default: false)
- `allow_execute` (bool, default: false)
- `max_tasks` (int, default: 20)

## Outputs

- `run/skills/next-steps/<timestamp>/tasks.json`
- `run/skills/next-steps/<timestamp>/tasks.txt`
- Optional SQL inserts into the `todos` table when allowed.

## Task schema (example)

```
{ "id":"add-ci-checks", "title":"Add CI checks to run scripts/setup.sh", "description":"...", "priority":1, "complexity":2, "impact":"medium", "files":["scripts/setup.sh"], "branch":"chore/add-ci-checks", "commit_msg":"chore(ci): add workflow to run scripts/setup.sh" }
```

## Guidelines

- Produce a comprehensive but concise list (<= 20 items) that spans fixes, enhancements, refactors, new features, and documentation improvements.
- Each item must include: acceptance criteria, complexity (1-5), impact (low|medium|high), priority, affected files or globs, suggested branch name and commit message.
- Do not include time or duration estimates.
- Mark tasks that require network access, external resources, or privileged actions as `requires-approval` or `requires-sandbox`.
- When inserting into `todos`, use kebab-case IDs and include complexity and impact metadata in the description or as structured fields.
- Prefer actionable items that can be implemented as a single PR; include file paths or short code snippets to make them easy to implement.

### References and how to find evidence in the codebase

- Primary input: the provided `summary_path` (summary.json). If not provided, use the latest `run/skills/review-repo/*/summary.json`.
- Scan top-level docs: `README.md`, `AGENT.md`, `docs/`, and `docs/*` for architecture and design.
- Inspect `.github/skills/*/SKILL.md`, `scripts/skills/`, and `scripts/` for automation and helper scripts.
- Search source and scripts for TODO/FIXME and domain keywords: `agent`, `swarm`, `autonom`, `self[- ]?improv`, `optimi`, `evolv`, `decentral`, `secure`, `copilot`, `supervisor`, `daemon`, `director`.
- Use git metadata (HEAD, recent commits via `git log -n 50 --pretty=oneline`) to prioritize recently modified components.
- When referencing files, use relative paths and include examples of lines or snippets to change.
