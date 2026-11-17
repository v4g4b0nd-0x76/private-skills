# Production-Grade Bench Environment

Load this when `plan.bench_env: required`, when `next.sh` routes to this skill for env setup, or before Phase 2 if benches need fixtures / third-party access.

## Goal

Own every dependency around the system under test so the **only** free variable in a dual-gate run is the code change under hypothesis. Uncontrolled sandboxes and zero-latency stubs lie about p99.

## Layering rule (compose with thirdparty-e2e)

| Dependency | How to exercise for benches |
| --- | --- |
| You own it (DB, queue, cache, internal gRPC) | **Real** container / binary — same engine as production |
| Third party with sandbox | Record once → **replay** fixtures; nightly live sandbox optional |
| Third party, no sandbox | **WireMock** (or equivalent) with recorded + hostile stubs |
| Need prod-like timing / faults | **Toxiproxy** (or stub fixedDelay) with measured or SLA latencies |

Never mock your own services for a latency campaign. Never point benches at shared staging (noisy neighbors invalidate MWU).

## Profiles every env must provide

1. **`baseline-zero`** — third parties at ~0 added latency / 0 errors (measure inherent path only).
2. **`prod-like`** — per-provider latency from observability or SLA (fixed or distribution); document the source in `.devflow/bench-env.md`.
3. **`fault`** *(optional for dual-gate)* — bounded 5xx / timeout / reset for resilience benches, not for the primary ACCEPT/REJECT gate unless the hypothesis is about fault handling.

Switch profiles without rewriting the SUT: point the app at Toxiproxy listen ports; change toxics or WireMock `fixedDelayMilliseconds`.

## Fixture / mock data

- Prefer **recorded** production-shaped payloads (sandbox capture) over hand-waved JSON.
- Synthetic data must match production schema cardinality (field presence, enum values, size bands).
- Unique IDs per run; clean up stateful sandboxes.
- Store under `.bench-env/fixtures/` and reference paths from the artifact — do not invent response bodies in the report.

## Isolation checklist

- Dedicated compose project name (`bench-<module>-<runid>`)
- Bind admin ports to localhost only
- Pin image tags (no `:latest` in committed compose)
- Healthchecks before first sample
- Tear down after the campaign (or leave running only with user approval)

## Softflow handoff

Write `.devflow/bench-env.md` from `assets/bench-env.md`. `check-bench-env.sh` must exit 0 before Phase 2. When devflow `mark-stale.sh … bench-env` runs after a new implement, rebuild or re-validate the env before claiming a new baseline.
