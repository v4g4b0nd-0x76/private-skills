# Devflow Handoff Contract

Load this file when routing, when a stage's preconditions are unclear, or when an artifact header looks wrong.

## Artifacts

All live in `<project-root>/.devflow/`. The directory is committed by default so the decision trail is reviewable.

| Artifact | Writer | Reader |
|----------|--------|--------|
| `research.md` | devflow-research | devflow-plan |
| `plan.md` | devflow-plan | devflow-implement, devflow-review, rust-submicrosecond-refactor |
| `implement.md` | devflow-implement | devflow-test, devflow-review |
| `bench-env.md` | rust-submicrosecond-refactor | devflow-test, rust-submicrosecond-refactor (Phase 2+) |
| `test-report.md` | devflow-test | devflow-review |
| `review.md` | devflow-review | devflow-implement (on changes requested) |

`bench-env.md` is **optional**. It exists only when `plan.md` declares `bench_env: required` (latency / open-loop campaigns that need fixtures or third-party simulation).

## Header schema

Every artifact starts with YAML frontmatter:

```yaml
---
devflow: research        # this artifact's stage (or bench-env)
status: draft            # draft | complete | approved | stale
upstream: none           # relative path to the artifact this stage consumed
approval: not-required   # not-required | pending | granted
updated: 2026-11-14      # ISO date, update on every write
---
```

`review.md` also carries `verdict: approve | changes-requested`.
`test-report.md` also carries `verdict: pass | fail`.
`plan.md` may also carry:

```yaml
bench_env: not-required  # not-required | required
latency_campaign: false  # false | true — routes dual-gate benches after env is ready
```

Missing `bench_env` / `latency_campaign` keys mean `not-required` / `false` (backward compatible).

## Status lifecycle

- `draft` — stage is working or blocked. Routing does not advance past a draft.
- `complete` — stage finished and its own checks passed. Routing advances.
- `approved` — human approval granted. Only `plan.md` uses this as its terminal state.
- `stale` — an upstream artifact changed after this one was written. Routing recomputes from the stale artifact.

When rerunning a stage, set every downstream artifact to `status: stale` before writing your own output:

`bash $SKILL_DIR/scripts/mark-stale.sh <project-root> bench-env test review`

## Gates

| Gate | Trigger | Required action |
|------|---------|-----------------|
| Plan | `plan.md` has `approval: pending` | Show the plan, ask the user, then set `status: approved` and `approval: granted` |
| Test | `test-report.md` does not exist / not complete | Show the full-suite commands, ask the user, then run them |

A gate is satisfied only by an explicit user approval in the conversation. Silence, "looks reasonable", or a prior approval for a different task is not approval.

## Routing order

`next.sh` evaluates in order and returns the first unmet stage:

1. `research.md` not `complete` → `devflow-research`
2. `plan.md` not `approved` → `devflow-plan`, or `GATE` if `approval: pending`
3. `implement.md` not `complete` → `devflow-implement`
4. `plan.bench_env == required` and `bench-env.md` not `complete` → `rust-submicrosecond-refactor` (bench-env setup first)
5. `test-report.md` not `complete` → `devflow-test` (or `GATE` for suite approval)
6. `review.md` not `complete` → `devflow-review`
7. `review.md` verdict `changes-requested` → `devflow-implement`
8. otherwise → `DONE`

When step 4 fires, activate **rust-submicrosecond-refactor** and follow its **Bench environment** phase (and the full latency campaign when `latency_campaign: true`). Do not skip to devflow-test while the env artifact is missing or draft.

## Reading upstream

A stage must extract, and may not silently contradict:

- the task statement and non-goals
- decisions already made (do not relitigate them)
- the file list and test plan
- open questions that block the work
- when present: Bench environment (owned vs virtualized deps, fixture sources, latency profiles)

If the upstream artifact is wrong, record the correction under `## Deviations` in your own artifact and mark the upstream `stale`; do not rewrite it.
