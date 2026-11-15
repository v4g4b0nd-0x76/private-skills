---
name: thirdparty-e2e
description: Inventory every third-party requirement an application depends on — external services, SDKs and libraries — then generate and run end-to-end tests that reproduce real scenarios under several load levels, hunting for unexpected behaviour like silent degradation, retry storms and contract drift. Use when asked what a system depends on externally, to write E2E or integration tests against real dependencies, to load-test, or to find how an app behaves when a provider is slow, rate-limited or down. Don't use for unit testing pure logic (use the project's own test runner) or for authorization/security abuse (use backend-security-test).
argument-hint: "[inventory | contracts | e2e | load | faults | report] [path-or-target]"
metadata:
  version: "1.0"
allowed-tools: Read Grep Glob Bash
---

# Third-Party E2E

Find what the app depends on outside its own process, write down what it requires, then prove the integration works — and keeps working — under real conditions.

`$SKILL_DIR` in the commands below means the absolute path of this skill's own directory.

## Safety rule

Load and fault tests send traffic and create real side effects. Before any of it:

1. Target must be `localhost`, `127.0.0.1`, `::1`, `*.test`, `*.localhost`, or an explicitly named staging URL.
2. `loadgen.sh` refuses production-looking hosts and requires `--i-own-this-target`.
3. Never run destructive scenarios (refunds, deletes, real charges) against anything but a sandbox account with test credentials.

Generating suites and profiles is always safe. Executing them is not.

## Step 1 — Inventory third-party requirements

```bash
bash $SKILL_DIR/scripts/inventory.sh <app-root> [--json]
```

It finds: outbound HTTP clients, provider SDK imports, base URLs and credentials in config, package manifests, and retry/timeout settings. Read [references/inventory.md](references/inventory.md) to turn hits into the real list.

For **each** integration record, in `.thirdparty/requirements.md` from `assets/integration-requirements.md`:

- provider, purpose, and which code path calls it
- auth model (API key, OAuth2, mTLS, signed webhook)
- contract: endpoint, request/response shape, version, documented SLA and rate limit
- failure semantics the app assumes: timeout, retry, fallback, queueing
- data classification: what is sent (PII, payment data, tokens)
- test credentials and a sandbox endpoint
- what breaks the app if this provider is slow, down, or returns 4xx/5xx

A provider with no failure semantics recorded is an untested assumption. That is the first finding.

## Step 2 — Decide how to exercise each dependency

Read [references/testing-layers.md](references/testing-layers.md). The rule:

| Dependency | Exercise |
|---|---|
| You own it, can run it | real, in a container (Testcontainers) |
| Someone else owns it, has a sandbox | real sandbox, nightly, not per-PR |
| Someone else owns it, no sandbox | virtualization (WireMock) with recorded + hostile responses |
| Slow, flaky, or rate-limited | proxy it (Toxiproxy) so you can reproduce it |

**Mock what you do not own; integrate for real with what you do.** Mocking your own services is how a green CI hides a red production.

## Step 3 — Generate the E2E suite

```bash
bash $SKILL_DIR/scripts/gen-e2e.sh <app-root> --out .thirdparty/e2e
```

Writes a runnable pytest suite plus a `docker-compose.yml` for WireMock and Toxiproxy:

```
.thirdparty/
├── requirements.md          # from Step 1, the source of truth
├── e2e/
│   ├── conftest.py          # target guard, provider health checks
│   ├── test_contracts.py    # response shape, required fields, versioning
│   ├── test_failures.py     # provider down/slow/5xx/429 -> app behaviour
│   ├── test_resilience.py   # retries, timeout, idempotency, no storm
│   └── test_degradation.py  # partial outage: what still works
└── docker-compose.yml
```

Fill the TODOs from `requirements.md`. Tests that cannot assert on behaviour must be deleted, not weakened — see [references/unexpected-behaviour.md](references/unexpected-behaviour.md) for what to assert.

## Step 4 — Load levels

```bash
bash $SKILL_DIR/scripts/loadgen.sh <app-root> --generate
bash $SKILL_DIR/scripts/loadgen.sh http://localhost:8080 --profile steady --i-own-this-target
```

Profiles generated (see [references/load-profiles.md](references/load-profiles.md)):

| Profile | Shape | What it reveals |
|---|---|---|
| `smoke` | 1 VU, 30s | wiring, auth, cold caches |
| `steady` | constant arrival rate, 5m | baseline latency and error rate |
| `spike` | ramp 10x for 60s | queue growth, autoscaling, 429 storms |
| `soak` | steady for 1h+ | leaks, connection exhaustion, drift |
| `cold-start` | 0 → peak in 10s | post-deploy behaviour |
| `degraded` | steady with a provider slowed | fallback correctness under load |

Thresholds are pass/fail, not decoration: p95, p99, error rate, and a **per-provider error budget**. A test that sends 20% errors and passes is a broken test.

## Step 5 — Fault injection

```bash
bash $SKILL_DIR/scripts/faults.sh <app-root> --list
bash $SKILL_DIR/scripts/faults.sh --toxiproxy localhost:8474 --scenario latency,p={provider_port} --apply
```

Toxiproxy toxics worth running per provider: `latency` (200ms/1s/5s), `timeout`, `down`, `reset_peer`, `bandwidth`, `packet_loss`. Assert **degradation, not just survival**: does the page still render, is the fallback used, is the error surfaced, is a retry bounded?

## Step 6 — Hunt unexpected behaviour

This is the point of the skill. Read [references/unexpected-behaviour.md](references/unexpected-behaviour.md) and actively look for:

- **Silent success**: 200 with empty or stale data when a provider failed.
- **Retry storms**: N retries × M callers; check provider-side request counts.
- **Idempotency failures**: the same event processed twice (double charge, duplicate email).
- **Timeout mismatch**: app timeout > provider timeout, so threads stay pinned.
- **Cache poisoning**: a failure cached and served as a valid result.
- **Unbounded queues**: backlog grows during a spike and never drains.
- **Order dependence**: events processed out of order (webhook + polling race).
- **Contract drift**: provider adds/removes a field; strict deserialization now fails or silently drops data.
- **Credential expiry mid-run**: token refresh under concurrency.

Every one of these needs an assertion, not a walkthrough.

## Step 7 — Report

Fill `assets/report.md`, then:

```bash
bash $SKILL_DIR/scripts/check-report.sh <report.md>
```

It requires every finding to have a reproduction, an observed-vs-expected pair, and the load/fault conditions under which it appears. Fix and re-run until it exits 0.

## Grounding rules (anti-hallucination)

- Provider contracts (URLs, fields, rate limits, SLAs) come from `inventory.sh` hits, vendor docs the agent fetched, or sandbox responses — never from model memory of "how Stripe usually works".
- If a contract field is unknown, record it as an open requirement gap; do not invent schemas to make a test compile.
- Load/fault results cite the profile name, thresholds, and observed metrics. Do not claim p95/error rates that were not printed by k6 or the suite.
- Prefer `check-report.sh` over self-grading.

## Gotchas

- **Mocking your own services produces green CI and red production.** Only virtualize what you cannot run.
- **A provider sandbox is not production.** Sandboxes have different latency, rate limits, and sometimes different contract versions; never infer production capacity from them.
- **Test data leaks between runs.** Sandbox accounts accumulate state; unique IDs per run, and clean up.
- **No think time is not load.** Requests back-to-back with zero delay measure the bot, not users. Vary inputs or every cache hit lies.
- **The load generator can be the bottleneck.** Check its CPU before blaming the target.
- **Warming the target invalidates the first minute.** Discard it, or measure `cold-start` deliberately.
- **`k6` thresholds are the only thing that fails a build.** A profile without thresholds proves nothing.
- **Webhooks retry.** Providers retry deliveries; receiving the same event twice is normal and must be idempotent.
- **Rate limits are per-account and often per-endpoint**; a 429 storm in staging may be your own test harness.
- **Do not load-test production without explicit approval and comms.** It costs real money and can page someone.

## Checklist

- [ ] Every outbound dependency inventoried with owner and purpose
- [ ] Auth model and rate limit recorded per provider
- [ ] Failure semantics written down (timeout/retry/fallback)
- [ ] Each dependency assigned a real-or-virtualized test layer
- [ ] E2E suite asserts behaviour, not just status codes
- [ ] Load profiles have thresholds
- [ ] Fault scenarios assert degradation, not just survival
- [ ] Unexpected-behaviour list checked item by item
- [ ] Target guard verified before running anything
- [ ] `check-report.sh` exits 0

## Dependencies

`references/inventory.md`, `references/testing-layers.md`, `references/load-profiles.md`, `references/unexpected-behaviour.md`. Scripts: `inventory.sh`, `gen-e2e.sh`, `loadgen.sh`, `faults.sh`, `check-report.sh`. Assets: `integration-requirements.md`, `report.md`, `k6/`, `e2e/`, `docker-compose.yml`. Complements `backend-security-test` (abuse) — this skill is about correctness and resilience under real conditions.
