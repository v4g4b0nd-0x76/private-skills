# Research: thirdparty-e2e

- **Date:** 2026-11-15
- **Agent:** Cursor Auto
- **Change:** edited `thirdparty-e2e` — added grounding rules against inventing provider contracts/metrics
- **Purpose:** inventory third-party requirements, generate E2E tests, run load/fault scenarios, hunt unexpected behaviour

## Queries run

1. `third party API dependency inventory contract testing WireMock Pact Testcontainers 2026 best practices`
2. `end to end testing production-like environment load testing k6 locust vegeta 2026 best practices`
3. `fault injection resilience testing Toxiproxy chaos engineering third party service failure 2026`
4. `SBOM dependency inventory syft CycloneDX cargo-audit pip-audit npm audit 2026 supply chain`
5. `reducing LLM hallucination agent skills grounded verification scripts 2026`

## Sources

| # | Source | Type | What it established |
|---|--------|------|---------------------|
| 1 | https://github.com/Shopify/toxiproxy | source repo | exact toxic set (latency, down, timeout, reset_peer, bandwidth, slicer, limit_data, packet_loss), directionality (upstream/downstream), `toxicity` probability, proxy naming scheme, admin API on 8474, "prove with tests that your application doesn't have single points of failure" |
| 2 | https://blog.rajpoot.dev/posts/devops/load-testing-2026/ | practitioner (detailed) | load shapes and the exact k6 configuration for steady/spike; thresholds as pass/fail; the 7 mistakes (no think time, same input, cold target, saturated generator, no error analysis); capacity-ceiling method |
| 3 | https://www.softwaretestpilot.com/blog/api-testing/microservices-testing | practitioner (detailed) | testing honeycomb (~40% unit, ~55% contract/integration, <=5% E2E); "mock what you don't own, integrate for real with what you do"; anti-pattern list; degradation/chaos levels |
| 4 | https://wstg.owasp.org/ | standards body | (context from prior skill) test-case structure |
| 5 | https://docs.pact.io/ | vendor docs | consumer-driven contract framing referenced by source 3 |
| 6 | https://testcontainers.com/ | vendor docs | real-dependency integration pattern referenced by source 3 |

## Project evidence

- Host has no `k6`, no Docker confirmed, no Toxiproxy, no WireMock. Reflects the capability-detection rule: scripts must probe and instruct, not assume.
- Existing skills: `rust-systems-perf` covers profiling/load for Rust binaries; `backend-security-test` covers adversarial authz. Neither inventories external dependencies or exercises third-party failure modes, so this is not a duplicate. SKILL.md links to both.
- User decisions: external services **and** libraries; generate profiles + opt-in run.

## Decisions

- **Grounding rules:** contracts and metrics must come from inventory/docs/sandbox/k6 output — never from memorized provider shapes. Unknown fields become requirement gaps, not invented schemas.
- **Inventory first, as a written artifact.** Every E2E test must trace to `.thirdparty/requirements.md`. A test against an unmapped dependency is a guess, and the missing failure-semantics field is itself the first finding.
- **Testing layer per dependency, chosen by ownership** (source 3's rule). Real container if you run it, sandbox nightly if they offer one, virtualization otherwise — and the record must state why it is virtualized.
- **Load profiles are named and distinct** (smoke/steady/spike/soak/cold-start/degraded) rather than one ramp-to-crash. Source 2 shows each shape exposes a different bottleneck; `cold-start` and `degraded` are the two that matter most for third-party apps and are usually skipped.
- **Thresholds are mandatory.** A profile without thresholds is a graph. Percentiles, never averages, and a failing-request budget separate from duration.
- **Degradation profile is the flagship.** Running steady traffic *while* a provider is impaired is the only way to see fallback correctness. Encoded as `degraded.js` plus `test_degradation.py`.
- **Safety gates in code.** `loadgen.sh` refuses non-local hosts, requires `--i-own-this-target`, and needs `--staging-host` to allow any single non-local host. `faults.sh` refuses a non-local Toxiproxy admin API. Generating is always safe.
- **Tests raise, not skip silently**, when stub infra is missing — the anti-false-negative rule carried over from the security skill.
- Rejected: a Locust or JMeter template alongside k6. Source 2/3 both name k6 as the 2026 default; adding three tools triples maintenance for no gain. Mentioned as alternatives in the reference instead.
- Rejected: automating SBOM generation. `inventory.sh` prints the correct `cargo audit` / `npm audit` / `pip-audit` command per stack rather than depending on all three being installed.

## Conflicts and resolution

- Source 3 caps E2E at <=5% of the suite, but this skill *is* the E2E layer. Resolved by scoping it to the third-party integration surface only and explicitly deferring unit/logic testing to the project's runner.
- Source 2 warns load generators lie when saturated; source 3 warns shared staging poisons runs. Both encoded as gotchas rather than treated as tooling problems.

## Verification log (executed, not assumed)

| Check | Result |
|---|---|
| `inventory.sh` on a multi-provider fixture | found Stripe/SendGrid SDK imports, hardcoded `api.stripe.com`, 30s timeouts, `maxNetworkRetries: 3`, webhook signature check |
| `inventory.sh` `.env` scan | found all 5 provider config keys (base URLs + secrets) that source-only grep missed |
| `inventory.sh --json` | valid JSON |
| `gen-e2e.sh` | writes 5 test files + README + docker-compose + requirements.md |
| `gen-e2e.sh` overwrite | refuses without `--force`; keeps existing `requirements.md` |
| `loadgen.sh --generate` | writes all 6 profiles, keeps existing |
| `loadgen.sh` vs `https://example.com`, `https://api.stripe.com`, `http://10.1.2.3` | **refused, exit 2** |
| `loadgen.sh` without `--i-own-this-target` | refused, exit 2 |
| `loadgen.sh --staging-host staging.myco.dev` | allows that host; refuses `prod.myco.dev` |
| `faults.sh --list` | prints scenarios, no network |
| `faults.sh --toxiproxy evil.example.com:8474` | **refused, exit 2** |
| `faults.sh` with nothing running | clear error + docker compose instruction |
| generated suite collection | **22 tests collected**, no syntax errors |
| suite with `APP_URL=https://prod.example.com` | raises `RuntimeError: REFUSED` |
| suite with stub infra absent | `provider_stub` raises `RuntimeError`, does not skip silently |
| `check-report.sh` blank template | rejected (18 placeholders) |
| `check-report.sh` valid report | passes |
| missing `Condition` / `## Third-party requirements` | rejected |
| `TODO` anywhere in report | rejected |
| live silent-success reproduction | app returned `payment_status=paid` with provider down; the assertion in `test_failures.py` flagged it **FAIL** |

Bugs found and fixed during verification:
- `faults.sh` probed the admin API **before** its localhost guard, so `--toxiproxy evil.example.com:8474` actually sent a network request. Moved the guard ahead of every network call.
- `inventory.sh` reported "endpoint config keys: (empty)" because provider endpoints live in `.env`, not source. Added a config-file scan.
- `inventory.sh` missed `maxNetworkRetries` — the retry policy was invisible, which is exactly the field the skill asks teams to record.
- `check-report.sh` silently passed a report containing `TODO`, because the inner check's exit status was swallowed. Added an explicit if-block plus a file-level check.

## Follow-ups (open)

- `faults.sh` covers Toxiproxy only; container-level chaos (pod kill, CPU, DNS) is documented in `testing-layers.md` but not automated. Add if the team runs Kubernetes.
- `test_contracts.py` forward-compatibility test needs a provider stub wired per integration; currently a skip with an explicit reason.
- Consider a recorder mode that captures real sandbox responses into WireMock fixtures, since that is the highest-value missing automation.
