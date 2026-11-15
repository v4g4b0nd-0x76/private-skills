# Research: devflow-plan

- **Date:** 2026-11-15
- **Agent:** Cursor Auto
- **Change:** edited grounding gotchas (shared anti-hallucination pass with parent devflow)
- **Prior:** created 2026-11-14

## Queries run

1. `agent planning artifact implementation plan template best practices 2026`
2. `agentskills.io plan validate execute best practices`

## Sources

| # | Source | Type | What it established |
|---|--------|------|---------------------|
| 1 | https://agentskills.io/skill-creation/best-practices | vendor docs | plan → validate → execute for batch or risky work; templates for output format |
| 2 | https://agentskills.io/specification | spec | assets/ is the right place for output templates |
| 3 | https://github.com/mgechev/skills-best-practices | source repo | numbered chronological steps, explicit decision trees |

## Project evidence

- User chose a hard approval gate after planning.
- `devflow-implement` needs a machine-checkable file list, so the plan must list exact paths.

## Decisions

- **`Files to touch` is a contract**, parsed by `check-scope.sh`; a forgotten file becomes a real, visible failure instead of silent scope creep.
- **Non-goals are mandatory**, because the most common planning failure is scope drift.
- **Approval field is `pending` until the user explicitly approves**; the stage sets `granted` only after that. Enforced in the body, not the script, because it depends on conversation state.
- Rejected: letting the agent auto-approve when "the plan looks complete". The user asked for a gate.

## Conflicts and resolution

- mgechev recommends keeping templates out of the body; the plan template is short enough for `assets/` and is loaded only when the stage runs, so it goes there rather than inline.

## Follow-ups

- Validate that `Files to touch` parsing survives directory entries and paths with spaces.

## Verification log (executed, not assumed)

| Check | Result |
|---|---|
| `scripts/chain-coverage.sh` | `check-plan.sh` accepts a complete plan; the pending→gate→approved edge is asserted |
| Absolute-path rejection | asserted: `/absolute/path.ts` in `Files to touch` fails |
| Missing-section rejection | asserted: removing `## Non-goals` fails validation |
| Approval gate | asserted: `approval: pending` routes to `GATE`, not to implement |
