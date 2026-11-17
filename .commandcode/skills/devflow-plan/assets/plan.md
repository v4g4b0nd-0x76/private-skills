---
devflow: plan
status: draft
upstream: .devflow/research.md
approval: pending
bench_env: not-required
latency_campaign: false
updated: YYYY-MM-DD
---

# Plan: <task>

## Goal

<One sentence with a verifiable success condition.>

## Non-goals

- <what this change will not do>

## Steps

1. <single reviewable change>
2. <single reviewable change>

## Files to touch

- `<path/from/project/root>` — <why>
- `<path/from/project/root>` — <why>

## Test plan

- `<exact command>` — <what it proves>
- <edge cases covered: empty input, error path, concurrency, permissions>

## Bench environment

<!-- Required when header bench_env: required. Otherwise write "not applicable". -->

- `bench_env`: not-required | required
- `latency_campaign`: false | true
- Owned deps (run for real): <postgres/redis/kafka/… + image tags>
- Third-party deps (simulate): <provider → WireMock stub + prod-like latency profile>
- Fixture / mock data sources: <recorded sandbox capture | synthetic schema | path>
- Isolation: dedicated compose project, localhost-only ports, unique run IDs
- Evidence of readiness: `check-bench-env.sh` exit 0

## Risks and rollback

- <risk> — <mitigation or revert step>

## Decision log

- <decision made while planning> — <why>

## Approval

- [ ] User approved this plan in the conversation
