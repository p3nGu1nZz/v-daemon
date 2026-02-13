# SKILL: next-steps

Summary

This skill instructs the Director agent how to generate prioritized, actionable next steps after producing a repository summary. The outputs are intended to be PR-sized tasks (3–6 items), written as a structured JSON artifact and optionally recorded into the Director's todo tracking table.

When to run
- Immediately after the summarize-repo skill completes and produced summary.json (and optionally summary.txt).
- During planning phases when the Director needs a small, prioritized list of actionable tasks to progress the project.

Inputs
- summary_path (required): path to summary.json produced by summarize-repo skill.
- allow_insert_todos (bool, default: false): if true, the skill may insert generated tasks into the todos table via the SQL tool.
- allow_execute (bool, default: false): if true, the skill may attempt to implement small patches (create branch, apply changes, run checks, and push) in a sandboxed workflow; use with care and explicit operator consent.
- max_tasks (int, default: 6): maximum number of tasks to generate.

Outputs (artifact locations)
- run/skills/next-steps/<timestamp>/tasks.json — primary JSON array of task objects
- run/skills/next-steps/<timestamp>/tasks.txt — a short human bulleted summary
- (optional) SQL inserts into todos table when allow_insert_todos=true

Task object schema (example)
{
  "id": "add-ci-checks",
  "title": "Add CI checks to run scripts/check.sh",
  "description": "Add a GitHub Actions workflow that runs `sh scripts/check.sh` in read-only mode and uploads logs to artifacts. Acceptance: workflow present, runs on push/PR, and returns exit code and artifacts.",
  "priority": 1,
  "estimate": "2h",
  "rationale": "Ensures basic repository checks run in CI and prevents regressions.",
  "files": ["scripts/check.sh", ".github/workflows/checks.yml"],
  "type": "quick-win",
  "branch": "chore/add-ci-checks",
  "commit_msg": "chore(ci): add workflow to run scripts/check.sh"
}

Generation steps
1. Read and validate summary.json. If missing fields, rebuild a minimal structure from README/AGENT.md and architecture.md.
2. Identify pain points and recommended_next_steps from summary.json and translate them into candidate tasks.
3. Normalize tasks to the Task object schema and ensure each is PR-sized.
4. Prioritize tasks using simple heuristics: safety, impact, testability, and lowest implementation friction.
5. Output tasks.json and tasks.txt to the run artifact directory.
6. If allow_insert_todos=true, insert each task into the SQL `todos` table with status 'pending' and return inserted IDs.

SQL example for inserting a todo (pseudo):
INSERT INTO todos (id, title, description) VALUES (
  'add-ci-checks',
  'Add CI checks to run scripts/check.sh',
  'Add a GitHub Actions workflow that runs scripts/check.sh in read-only mode and uploads artifacts. Acceptance: workflow present and passes.'
);

Quality rules and constraints
- Limit tasks to 3–6 items and prefer small, testable work items (PR-sized).
- Always include acceptance criteria in the description.
- Prefer actionable tasks with clear file targets and suggested branch/commit message.
- Mark tasks that require running scripts or network access with an explicit note and set "requires-sandbox": true.

Implementation notes for Director agent
- Use scripts/lib/prompts.sh PROMPT_NEXT_STEPS as the canonical prompt when invoking the Copilot CLI.
- Validate generated JSON strictly; reject and re-prompt if the output is not valid JSON.
- When inserting into the todos table, follow repository conventions for kebab-case IDs and provide helpful descriptions.
- Emit artifact references (paths) for downstream agents and humans.

Safety & human-in-the-loop
- Do NOT automatically trigger any task execution, CI changes, or merges.
- If a generated task appears to require privileged actions (infrastructure changes, publish, deletes), mark it as 'requires-approval' and notify a human operator.

Example short operator summary
- Top 2 recommended tasks: add CI checks (priority 1), add Director/Worker reference tests (priority 1).
- Quick wins: update AGENT.md and add scripts/lib/prompts.sh to centralize prompts.
- Long-term: containerize supervisor and add systemd/unit artifacts.

End of skill.
