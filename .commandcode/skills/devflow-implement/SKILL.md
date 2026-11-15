---
name: devflow-implement
description: Stage 3 of devflow — execute an approved .devflow/plan.md with the smallest coherent diff, staying inside the plan's file list, then record changes and deviations in .devflow/implement.md. Use when devflow routing returns devflow-implement, when a plan is approved and coding can start, or when a review requested changes. Don't use when no approved plan exists (use devflow-plan) or for research-only work.
metadata:
  version: "1.0"
  devflow-stage: "3"
---

# Devflow Implement

Execute the approved plan. The plan is the contract; the diff is the output.

`$SKILL_DIR` in the commands below means the absolute path of this skill's own directory.

## Preconditions

1. Run `bash $SKILL_DIR/../devflow/scripts/next.sh <project-root>`. It must say `NEXT: devflow-implement`. If it says `GATE`, stop and get approval first.
2. Read `.devflow/plan.md` and `.devflow/research.md` in full.
3. Validate the plan: `bash $SKILL_DIR/../devflow-plan/scripts/check-plan.sh <project-root>`. It must exit 0.
4. Confirm `approval: granted` in `plan.md`. Do not start without it.
5. Mark downstream artifacts stale:
   ```bash
   bash $SKILL_DIR/../devflow/scripts/mark-stale.sh <project-root> test review
   ```

## Steps

1. **Implement step by step** in plan order. After each step, run the narrowest relevant check (targeted test, typecheck, lint on changed files).
2. **Stay in scope.** Only touch files listed in `Files to touch`. If a new file is genuinely required, stop and ask the user to update the plan; do not silently expand scope.
3. **Do not add dependencies, refactor unrelated code, or change formatting** outside the touched lines.
4. **Validate the diff**:
   ```bash
   bash $SKILL_DIR/scripts/check-scope.sh <project-root>
   ```
   Every reported out-of-scope file must be reverted or approved by the user and added to the plan.
5. **Write the artifact** from `assets/implement.md` to `.devflow/implement.md`: completed steps, changed files with one-line reasons, deviations, follow-ups.
6. **Complete** — set `status: complete` and `updated: today`.
7. **Route** — run `next.sh` from `../devflow/` and follow its output.

## Deviations

Any difference from the plan (different file, different approach, skipped step) goes in `## Deviations` with the reason. A deviation the user did not approve is a defect, not a note.

## Gotchas

- Tests that pass locally can still fail in the full suite; do not claim success beyond what you ran.
- If a step reveals the plan is wrong, stop and route back to `devflow-plan` instead of improvising a new design mid-implementation.
- Do not invent APIs, config keys, or dependency versions — follow research/plan evidence or stop and ask.
- Do not commit unless the user asked. Devflow tracks working-tree changes.
- If `check-scope.sh` reports `.devflow/` files, that is expected and excluded automatically.

## Checklist

- [ ] Plan approved and read
- [ ] Downstream artifacts marked stale
- [ ] Every plan step implemented and checked
- [ ] `check-scope.sh` clean or deviations approved
- [ ] `implement.md` written, `status: complete`

## Dependencies

Uses `assets/implement.md` and `scripts/check-scope.sh` from this directory, plus `../devflow/scripts/` and `../devflow-plan/scripts/`.
