# SKILL: summarize-repo

Summary

This skill instructs the Director agent how to produce a concise, structured summary of the repository's current state suitable for human review and automated decision-making. The output is both a short human-readable summary (summary.txt) and a structured JSON (summary.json) that captures metadata, key files, scripts, build/runtime instructions, tests, and recommended next steps.

When to run
- During agent startup to get situational awareness
- Before creating high-level plans or actions (PR review, release prep)
- On-demand as a repository audit or periodic health-check

Inputs
- allow_run (bool, default: false): if true, the skill may execute repository scripts (e.g., scripts/check.sh). If false, the skill performs read-only collection.
- output_format (string, default: "text"): "text" or "json" (or both by writing both artifacts)
- include_globs (array, optional): additional glob patterns to include when indexing files
- max_preview_lines (int, default: 200): how many lines to include when previewing files

Outputs (artifact locations)
- run/skills/summarize-repo/<timestamp>/summary.txt  — concise human summary (4–8 sentences)
- run/skills/summarize-repo/<timestamp>/summary.json — structured JSON with detailed fields
- run/skills/summarize-repo/<timestamp>/raw/ — optional raw captures (git metadata, file lists, script outputs, check logs)

Gathering steps (read-only by default)
1. Git metadata:
   - git rev-parse --abbrev-ref HEAD
   - git rev-parse --short HEAD
   - git log -1 --pretty=format:'%H|%an|%ae|%ad|%s' --date=iso
2. Top-level layout:
   - list top-level files/dirs (ls -1)
   - record presence of README.md, AGENT.md, doc/, scripts/, config/, external/, run/, logs/, CMakeLists.txt
3. Core docs:
   - capture first `max_preview_lines` lines of README.md, AGENT.md, doc/architecture.md (if present), scripts/scripts.md, and config/settings.toml
4. Scripts and runtime helpers:
   - list scripts/ and scripts/lib/; for each script, capture the shebang and leading comment lines to infer purpose
5. Build/test detection:
   - detect CMakeLists.txt, Makefile, package.json, and presence of external/Catch2 or other test frameworks
6. TODOs & issues in code:
   - search for TODO, FIXME, XXX across repository (use ripgrep/grep)
7. (Optional, if allow_run=true) Safe checks:
   - run `sh scripts/check.sh` and capture stdout/stderr and exit code into raw/
   - do NOT run scripts that may install system packages unless explicitly permitted

Structured JSON schema (recommended fields)
{
  "repo": "<name>",
  "head": {"branch":"","commit":"","author":"","date":""},
  "summary": "<short 1-3 sentence overall summary>",
  "top_level": ["README.md","scripts/",...],
  "scripts": [{"path":"scripts/run.sh","purpose":"supervisor/harness","how_to_run":"sh scripts/run.sh [--monitor]"},...],
  "build": {"detected":"cmake|none","commands":["mkdir -p build && cd build && cmake .. && ninja"]},
  "runtime": {"entry_points":["scripts/run.sh"],"config":"config/settings.toml","artifacts":"run/ and logs/"},
  "tests": {"frameworks":["Catch2"],"how_to_run":"cd build && ctest"},
  "todos": [{"file":"path","line":42,"text":"TODO: ..."}],
  "pain_points": ["no CI configured","no test targets"],
  "recommended_next_steps": ["Add CI that runs scripts/check.sh in read-only mode","Add reference Director/Worker tests"]
}

Quality rules for the human summary
- Keep the summary factual and concise (4–8 sentences).
- Start with a single-sentence overall statement about the repository's purpose.
- Follow with 2–3 short sentences naming key scripts, config locations, and build/test status.
- End with 1–2 recommended next steps or high-risk notes (e.g., missing tests, scripts that perform installs).

Example human summary
"v-daemon is a lightweight shell-based supervisor and development harness implementing a Director/Worker pattern. Key developer scripts: scripts/setup.sh (prepare environment), scripts/check.sh (repo checks), scripts/run.sh (supervisor/harness). Configuration is under ./config/settings.toml; optional C/C++ builds are supported with CMake. Recommended next steps: add CI to run checks, add a reference Director/Worker test suite, and containerize the supervisor for reproducible integration runs."

Director-agent implementation notes (recommended)
- Perform the read-only collection steps first; write raw captures into the run/skills/summarize-repo/<timestamp>/raw/ folder.
- Build the structured JSON and then produce the human summary following the quality rules.
- If allow_run is true, run scripts/check.sh in a sandboxed environment or CI runner and record exit code and logs.
- Attach both summary.txt and summary.json as artifacts for downstream agents or humans.

Safety & precautions
- By default, the skill must be read-only. Executing repository scripts is opt-in and must be gated by allow_run.
- Capture and surface any network or package installation steps discovered in scripts as a warning before executing.

Maintenance
- Keep this SKILL.md updated whenever new top-level scripts or runtime conventions are added (also update AGENT.md to reference the skill).
- Aim to make the structured JSON backward-compatible: prefer adding new fields instead of renaming existing ones.

Example usage (pseudo-steps for Director agent)
1. timestamp=$(date -u +%Y%m%dT%H%M%SZ)
2. outdir="run/skills/summarize-repo/$timestamp" && mkdir -p "$outdir/raw"
3. collect git and file lists into $outdir/raw/
4. build summary.json and write to $outdir/summary.json
5. build summary.txt (4–8 sentences) and write to $outdir/summary.txt
6. emit artifact reference and relevant recommendations to the Director's plan

End of skill.
