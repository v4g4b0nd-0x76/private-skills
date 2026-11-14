---
name: devflow
description: Route a non-trivial development task through five gated stages — research, plan, implement, test, review — using shared artifacts in .devflow/ so each agent reads the previous agent's output before acting. Use when starting a feature, bug fix, or refactor that spans more than one file, when the user says "run devflow", "plan then implement", or asks which stage comes next. Don't use for one-line fixes, pure questions, or documentation-only edits.
argument-hint: "[task description | status | next]"
metadata:
  version: "1.0"
---

# Devflow Orchestrator

Routes work through five stage skills. Each stage writes one artifact to `.devflow/` in the target project; the next stage MUST read that artifact before acting.

`$SKILL_DIR` in the commands below means the absolute path of this skill's own directory.

## Stage chain

| # | Skill | Writes | Gate |
|---|-------|--------|------|
| 1 | devflow-research | `.devflow/research.md` | none |
| 2 | devflow-plan | `.devflow/plan.md` | STOP for user approval |
| 3 | devflow-implement | `.devflow/implement.md` | none |
| 4 | devflow-test | `.devflow/test-report.md` | STOP before full suite |
| 5 | devflow-review | `.devflow/review.md` | none |

The artifact header, status lifecycle, and stale rules are defined in [the handoff contract](references/handoff-contract.md). Read it before routing for the first time in a session.

## Routing

1. Run `bash $SKILL_DIR/scripts/status.sh <project-root>` to print every artifact and its status.
2. Run `bash $SKILL_DIR/scripts/next.sh <project-root>` to get the next action.
3. Act on the output exactly:
   - `NEXT: devflow-<stage>` — activate that stage skill and follow it.
   - `GATE: ...` — stop, present the artifact to the user, and ask for approval. Do not continue.
   - `DONE` — report the review verdict and stop.
4. Never activate two stage skills at once. One stage per turn, then re-run `next.sh`.

If the user gives a new task, start at `devflow-research` unless `.devflow/plan.md` is approved for that same task.

## Rules

- The artifacts are the state. Do not keep a separate mental plan that contradicts them.
- Never edit an upstream artifact from a downstream stage. If it is wrong, mark it stale and route back.
- Never skip a gate because the change looks safe.
- Missing `.devflow/` is normal for a new task; do not create it manually — the research stage creates it.
- If a stage cannot complete, append the blocker to its artifact, leave `status: draft`, and stop. Do not route forward.

## Checklist

- [ ] `next.sh` output read and followed
- [ ] Only one stage skill active
- [ ] Gate honored when `next.sh` returns `GATE`
- [ ] State re-read after each stage instead of assuming progress

## Dependencies

Stage skills live as siblings: `../devflow-research/`, `../devflow-plan/`, `../devflow-implement/`, `../devflow-test/`, `../devflow-review/`. Install them together.
