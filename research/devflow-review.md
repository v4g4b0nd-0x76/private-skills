# Research: devflow-review

- **Date:** 2026-11-14
- **Change:** created `devflow-review`

## Queries run

1. `AI code review agent severity levels best practices 2026`
2. `agent skills code review instructions examples`

## Sources

| # | Source | Type | What it established |
|---|--------|------|---------------------|
| 1 | https://agentskills.io/skill-creation/best-practices | vendor docs | code review example favors judgment-oriented checks over rigid procedure |
| 2 | https://agentskills.io/specification | spec | scripts/ for deterministic scans; clear actionable errors |
| 3 | https://github.com/mgechev/skills-best-practices | source repo | specific instructions, consistent terminology, explicit edge cases |

## Project evidence

- Review must be able to send work back without destroying traceability.
- A cheap deterministic scan for credentials is worth more than an instruction to "check for secrets".

## Decisions

- **Read-only stage.** Fixes route back to implement so every change stays tied to a plan step and a test run.
- **Four severity levels with fixed meanings** — keeps verdicts consistent across tasks.
- **`check-diff.sh` treats credentials and private keys as blocking (exit 1)**, debug leftovers and TODOs as warnings. Concrete, low false-positive patterns only.
- **`verdict: changes-requested`** is the routing signal; `next.sh` uses it to return to implement.

## Conflicts and resolution

- None.

## Follow-ups

- Extend secret patterns only with evidence of real misses; broad regexes produce false positives that train agents to ignore the scan.

## Verification log (executed, not assumed)

| Check | Result |
|---|---|
| `scripts/chain-coverage.sh` | `changes-requested` routes back to implement; `approve` reaches `DONE` |
| `check-diff.sh` | asserted to block a planted credential and pass a clean diff |
| Stale handling | asserted: after stale, tests re-gate rather than review resuming |
