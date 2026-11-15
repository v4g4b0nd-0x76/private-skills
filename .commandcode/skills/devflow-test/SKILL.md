---
name: devflow-test
description: Stage 4 of devflow — plan the verification commands, get approval, run the full gate suite, and record results in .devflow/test-report.md. Use when devflow routing returns devflow-test, when implementation is complete and needs verification, or when the user asks to run the gates. Don't use to write new features (use devflow-implement) or for review (use devflow-review).
metadata:
  version: "1.0"
  devflow-stage: "4"
---

# Devflow Test

Produce `.devflow/test-report.md`. Do not change production code in this stage; failures route back to implement.

`$SKILL_DIR` in the commands below means the absolute path of this skill's own directory.

## Preconditions

1. Run `bash $SKILL_DIR/../devflow/scripts/next.sh <project-root>`. It must say `GATE: test run approval required` or `NEXT: devflow-test`.
2. Read `.devflow/plan.md` (the `Test plan` section is the primary source of truth) and `.devflow/implement.md`.

## Steps

1. **Build the gate list:**
   ```bash
   bash $SKILL_DIR/scripts/run-gates.sh <project-root>
   ```
   The script prints the commands it would run. Merge them with the plan's `Test plan`; the plan wins when the two disagree.
2. **Targeted checks first** — run the fastest relevant check on the changed files (single test file, typecheck, lint). A quick failure saves a long run.
3. **STOP at the gate.** Show the user the exact full-suite commands and ask for approval to run them. Do not run the full suite before approval.
4. **On approval**, run the full suite:
   ```bash
   bash $SKILL_DIR/scripts/run-gates.sh <project-root> --run
   ```
5. **Write the artifact** from `assets/test-report.md` to `.devflow/test-report.md`: every command, its result, and the failure detail.
6. **Decide:**
   - All pass → `status: complete`, `verdict: pass`.
   - Any fail → `status: draft`, `verdict: fail`, route back to `devflow-implement`. Do not mark complete.
7. **Waivers** — a skipped or unavailable check needs the user's explicit approval, recorded in `## Waivers` with the reason. An unwaived skipped check is a failure.
8. **Route** — run `next.sh` and follow its output.

## Gotchas

- Never report "tests pass" for a suite you did not run. Record the exact command and the exit code as printed — do not invent results.
- A skipped or unavailable tool is a waiver candidate, not an implicit pass.
- A passing test suite does not prove the goal is met; check the plan's success condition separately and note it.
- Watch for suites that hang on watch mode; add `--run`/`--watch=false` style flags.
- Flaky failures get one re-run; if it passes twice inconsistently, record it as flaky in Waivers instead of hiding it.

## Checklist

- [ ] Gate list built and merged with the plan's test plan
- [ ] Targeted checks run before the full suite
- [ ] User approval obtained before the full suite
- [ ] Every command and result recorded
- [ ] `verdict` matches reality; failures routed back

## Dependencies

Uses `assets/test-report.md` and `scripts/run-gates.sh` from this directory, plus routing from `../devflow/`.
