# Research: devflow-research

- **Date:** 2026-11-15
- **Agent:** Cursor Auto
- **Change:** edited `devflow-research` — stronger citation rules; `check-research.sh` rejects unsourced findings

## Queries run

1. `agent skill research best practices sources verification 2026`
2. `agentskills.io skill creation best practices`
3. `reducing LLM hallucination agent skills grounded verification scripts 2026`

## Sources

| # | Source | Type | What it established |
|---|--------|------|---------------------|
| 1 | https://agentskills.io/skill-creation/best-practices | vendor docs | "start from real expertise"; generic procedures are the main failure mode |
| 2 | https://agentskills.io/specification | spec | assets/ for templates, references kept one level deep |
| 3 | https://github.com/mgechev/skills-best-practices | source repo | concrete templates beat prose descriptions of output format |
| 4 | https://github.com/srinitude/building-deterministic-skills | source repo | insufficient-context escape hatch; scripts for exact checks |
| 5 | https://github.com/pedro-angel/agent-methodology/blob/main/skills/grounded-verifiable-gates/SKILL.md | source repo | drop ungrounded claims before they can matter |

## Project evidence

- Existing fixture in `script-tests.sh` already used ` — ` citations; the new check hardens that convention.
- User taste: web search for current best practices is mandatory before documenting or implementing conventions.

## Decisions

- **Enforce sourced findings in `check-research.sh`** — every Findings bullet needs an em dash citation or path/URL. Rejected: prose-only "include a source".
- **Unknown → Open questions / BLOCKER**, not invented facts — matches grounded-gates fail-closed pattern.
- **Minimum two searches with the current year, primary sources preferred** — encodes the user's mandatory-research rule directly in the stage.
- Rejected: separate `research.md` and `sources.md` files. One artifact with a Sources section is enough and keeps the handoff simple.

## Conflicts and resolution

- None.

## Follow-ups

- Watch whether two searches are enough for version-sensitive work; raise the bar if plans keep missing context.

## Verification log (executed, not assumed)

| Check | Result |
|---|---|
| `script-tests.sh` unsourced-findings case | added; must fail check-research |
| `check-all.sh` | see batch run |
