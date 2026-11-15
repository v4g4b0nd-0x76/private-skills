---
name: devflow-review
description: Stage 5 of devflow — review the diff against the approved plan and requirements, scan for secrets and debug leftovers, and record a verdict in .devflow/review.md. Use when devflow routing returns devflow-review, when a change is implemented and tested and needs sign-off, or when the user asks for a review of the current work. Don't use to fix code (use devflow-implement) or to run tests (use devflow-test).
metadata:
  version: "1.0"
  devflow-stage: "5"
---

# Devflow Review

Produce `.devflow/review.md` with a verdict. This stage is read-only with respect to production code.

`$SKILL_DIR` in the commands below means the absolute path of this skill's own directory.

## Preconditions

1. Run `bash $SKILL_DIR/../devflow/scripts/next.sh <project-root>`. It must say `NEXT: devflow-review`.
2. Read `.devflow/plan.md`, `.devflow/implement.md`, and `.devflow/test-report.md`.
3. Confirm `test-report.md` has `verdict: pass`. If not, stop and route back.

## Steps

1. **Scan the diff:**
   ```bash
   bash $SKILL_DIR/scripts/check-diff.sh <project-root>
   ```
   A non-zero exit means a credential or private key was found. Report it as a blocking finding immediately.
2. **Review against the plan** — every step done, every goal satisfied, no unapproved deviations, no scope creep.
3. **Review the code** with judgment, not a checklist ritual. Priorities in order:
   - correctness: does it meet the success condition, including edge cases in the plan?
   - security: injection, authz checks, secret handling, unsafe deserialization
   - data safety: migrations, destructive writes, retries
   - test adequacy: do the tests fail if the change is reverted?
   - maintainability only where it affects future correctness
4. **Write the artifact** from `assets/review.md` to `.devflow/review.md`. Findings ordered by severity, each with a location and a concrete fix.
5. **Set the verdict:**
   - No blocking findings → `status: complete`, `verdict: approve`.
   - Any blocking finding → `status: complete`, `verdict: changes-requested`, and route back to `devflow-implement`.
6. **Route** — run `next.sh` and follow its output.

## Severity

- `blocker` — wrong behavior, security issue, data loss risk, missing required step
- `major` — real defect or unhandled edge case, fixable without redesign
- `minor` — correctness-adjacent nit with a clear fix
- `note` — observation, no action required

## Gotchas

- Do not edit code in this stage, even trivial fixes. Route back so the change stays traceable.
- Do not approve with failing or unwaived tests, regardless of how small the change looks.
- Findings need a file path (and ideally a line/hunk) from the diff or `check-diff.sh` — do not invent locations.
- Style preferences that the project does not enforce are `note`, not `major`.
- Re-read the original task; a clean diff can still miss the actual requirement.

## Checklist

- [ ] `check-diff.sh` run, secrets treated as blocking
- [ ] Plan compliance verified step by step
- [ ] Findings have locations and concrete fixes
- [ ] Verdict matches findings
- [ ] Routing output followed

## Dependencies

Uses `assets/review.md` and `scripts/check-diff.sh` from this directory, plus routing from `../devflow/`.
