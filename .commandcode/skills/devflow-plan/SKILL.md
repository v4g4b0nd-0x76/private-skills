---
name: devflow-plan
description: Stage 2 of devflow — turn .devflow/research.md into an approved implementation plan with goal, non-goals, ordered steps, exact files to touch, test plan, and rollback. Use when devflow routing returns devflow-plan, when a task needs a written plan before coding, or when the user asks to plan a feature or refactor. Don't use for research (use devflow-research) or for making the change (use devflow-implement).
argument-hint: "[task description]"
metadata:
  version: "1.0"
  devflow-stage: "2"
---

# Devflow Plan

Produce `.devflow/plan.md` and stop at the approval gate. Do not write production code in this stage.

`$SKILL_DIR` in the commands below means the absolute path of this skill's own directory.

## Preconditions

1. Read `.devflow/research.md` in full. If it is missing or not complete, stop and route to `devflow-research`.
2. Validate the upstream artifact:
   ```bash
   bash $SKILL_DIR/../devflow-research/scripts/check-research.sh <project-root>
   ```
   If it fails, fix nothing directly — route back to `devflow-research`.

## Steps

1. **Extract from research** — task, decisions already made, rejected options, open questions. Do not relitigate settled decisions.
2. **Write the plan** from `assets/plan.md` to `.devflow/plan.md`:
   - `Goal` in one sentence with a verifiable success condition.
   - `Non-goals` explicit, so scope cannot drift.
   - `Steps` ordered, each a single reviewable change.
   - `Files to touch` exact repository-relative paths, one per line. This list is enforced later by `check-scope.sh`, so include every file you expect to modify.
   - `Test plan` the exact commands that prove the change works, plus the edge cases they cover.
   - Header `bench_env` / `latency_campaign` — set `bench_env: required` and fill `## Bench environment` when the work needs mock data, third-party access, or a sub-µs dual-gate campaign. Owned deps run for real; third parties are simulated with production-like latency (see rust-submicrosecond-refactor + thirdparty-e2e). Otherwise leave `not-required` / `false` and write `not applicable` in the section.
   - `Risks and rollback` one line per risk.
   - `Decision log` new decisions not already in research.
3. **Validate**:
   ```bash
   bash $SKILL_DIR/scripts/check-plan.sh <project-root>
   ```
   Fix and re-run until it exits 0.
4. **Set the gate** — header must read `status: draft` and `approval: pending`.
5. **STOP.** Present the plan to the user: goal, file list, test commands, risks. Ask for approval.
6. **On explicit approval only** — set `status: approved` and `approval: granted`, then route with `next.sh` from `../devflow/`. If the user asks for changes, edit the plan, re-validate, and present it again.

## Approval rule

Approval must be an explicit yes for this plan in this conversation. "Looks fine", a prior approval for another task, or silence is not approval. Never set `approval: granted` on your own initiative.

## Gotchas

- A file you forget in `Files to touch` becomes a scope violation in `devflow-implement`. When unsure, list the directory rather than guessing extra files — never invent paths that do not exist in the tree.
- Test commands must already exist or be created by a listed step. A test plan that says "write tests" without a runnable command fails validation.
- Plan for the smallest change that satisfies the goal; do not bundle refactors into a fix.
- Do not reintroduce options research already rejected, and do not invent new library/API choices without a research finding to back them.
- If research has a non-blocking open question, put the decision you are making in `Decision log`.

## Checklist

- [ ] `research.md` read and complete
- [ ] Plan filled from template, file list exact
- [ ] `check-plan.sh` exits 0
- [ ] `approval: pending` set and plan shown to the user
- [ ] Approval received before any approval field changes

## Dependencies

Uses `assets/plan.md` and `scripts/check-plan.sh` from this directory, plus `../devflow-research/scripts/check-research.sh` and routing from `../devflow/`.
