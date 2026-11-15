# Research: devflow-test

- **Date:** 2026-11-15
- **Agent:** Cursor Auto
- **Change:** edited grounding gotchas (shared anti-hallucination pass with parent devflow)
- **Prior:** created 2026-11-14

## Queries run

1. `AI agent test verification loop best practices 2026`
2. `agent skills validation loops checklists best practices`

## Sources

| # | Source | Type | What it established |
|---|--------|------|---------------------|
| 1 | https://agentskills.io/skill-creation/best-practices | vendor docs | validation-loop pattern: run validator, fix, repeat until pass |
| 2 | https://agentskills.io/specification | spec | scripts should handle edge cases and print actionable errors |
| 3 | https://github.com/mgechev/skills-best-practices | source repo | scripts as tiny CLIs; deterministic operations belong in scripts |

## Project evidence

- User requested an approval gate before the full test suite.
- Projects vary (JS, Go, Rust, Python), so gate detection must cover several ecosystems.

## Decisions

- **`run-gates.sh` is dry-run by default and requires `--run`** — the approval gate is enforced by the tool shape, not by trust.
- **Targeted checks run before the gate** — cheap failures do not need approval, expensive runs do.
- **Failures keep `status: draft` with `verdict: fail`**, and routing sends the task back to implement. Prevents "tests failed but stage complete".
- **Waivers require explicit user approval** — a skipped check is a failure unless waived.
- Rejected: hard-coding `npm test`. Detection across ecosystems is more useful and still deterministic.

## Conflicts and resolution

- None.

## Follow-ups

- Add detection for monorepos where gates live per package; current script only handles a single root project.
