# Research: devflow-research

- **Date:** 2026-11-14
- **Change:** created `devflow-research`

## Queries run

1. `agent skill research best practices sources verification 2026`
2. `agentskills.io skill creation best practices`

## Sources

| # | Source | Type | What it established |
|---|--------|------|---------------------|
| 1 | https://agentskills.io/skill-creation/best-practices | vendor docs | "start from real expertise"; generic procedures are the main failure mode |
| 2 | https://agentskills.io/specification | spec | assets/ for templates, references kept one level deep |
| 3 | https://github.com/mgechev/skills-best-practices | source repo | concrete templates beat prose descriptions of output format |

## Project evidence

- User taste: web search for current best practices is mandatory before documenting or implementing conventions.
- Empty repo, so the artifact template is the only format anchor.

## Decisions

- **Minimum two searches with the current year, primary sources preferred** — encodes the user's mandatory-research rule directly in the stage.
- **Findings must carry a source per bullet** (path, URL, or command) — prevents unsourced claims from reaching the plan.
- **`BLOCKER` marker in open questions** prevents the stage from claiming completion while an unknown remains; `check-research.sh` enforces it.
- Rejected: separate `research.md` and `sources.md` files. One artifact with a Sources section is enough and keeps the handoff simple.

## Conflicts and resolution

- None.

## Follow-ups

- Watch whether two searches are enough for version-sensitive work; raise the bar if plans keep missing context.
