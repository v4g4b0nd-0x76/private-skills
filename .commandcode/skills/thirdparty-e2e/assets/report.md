# Third-Party E2E Report

- **Application:** <service, commit, environment>
- **Date:** YYYY-MM-DD
- **Tester:** <agent / person>
- **Approval to load:** <who approved, for which target>

## Third-party requirements

| Provider | Purpose | Auth | Rate limit | Fallback | Test approach |
|---|---|---|---|---|---|
| <provider> | <purpose> | <auth> | <limit> | <fallback> | <real sandbox / virtualized> |

## Load conditions tested

- Profiles: <smoke, steady, spike, soak, cold-start, degraded>
- Fault scenarios: <latency 2s, down, 429, packet loss>
- Target: <localhost / staging host>
- Duration and rate: <5m @ 100rps>

## Unexpected behaviour

### FINDING-001 <short title>

- **Provider:** <provider or "internal">
- **Severity:** Critical | High | Medium | Low
- **Behaviour:** silent-success | retry-storm | idempotency | timeout-mismatch
  | cache-poisoning | unbounded-queue | order-dependence | contract-drift
  | credential-race | backlog-not-draining
- **Condition:** <the load or fault state in which it appears>
- **Reproduction:**
  ```
  1. faults.sh --scenario <scenario> --proxy <name>
  2. loadgen.sh <url> --profile <profile> --i-own-this-target
  3. observe <exact result>
  ```
- **Observed:** <what happened, with numbers>
- **Expected:** <acceptable behaviour>
- **Impact:** <money / data / availability, in business terms>
- **Fix:** <bounded retry, explicit degradation, idempotency key, cache rule>

## What was not tested

- <provider / profile / scenario skipped, and why>

## Summary

<2-3 sentences: worst finding, which load condition exposed it, what to fix first.>
