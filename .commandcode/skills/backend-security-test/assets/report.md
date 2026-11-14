# Backend Security Test Report

- **Target:** <service, commit, environment>
- **Date:** YYYY-MM-DD
- **Tester:** <agent / person>
- **Authorization:** <who owns this system; scope agreed>
- **Mode:** static mapping + generated suite [+ local probe]

## Scope

In scope: <endpoints, services, roles>
Out of scope: <explicitly excluded>

## What was not tested

- <endpoint or class skipped, and why>

## Findings

### FINDING-001 <short title>

- **Severity:** Critical | High | Medium | Low
- **Class:** BOLA-ActionLevel | BOLA-DirectReference | BOLA-Tenant
  | BOLA-WorkflowContext | BOLA-ChainedDisclosure | BOLA-Rebinding
  | BFLA | VerticalEscalation | MassAssignment | RaceCondition
  | AuthBypass | DataLeakage | LogicAbuse
- **Endpoint:** `METHOD /path`
- **Confidence:** confirmed | unverified | rejected
- **Reproduction:**
  ```
  1. authenticate as alice, who owns object A
  2. request METHOD /path with <exact payload>
  3. observe <exact response or state>
  ```
- **Observed:** <what happened, including the wrong state>
- **Expected:** <what a correct implementation returns>
- **Impact:** <money / data / access / reputation, in business terms>
- **Fix:** <server derives ownership from session and scopes at the query layer>
- **Evidence:** <test name, file, or request/response excerpt>

## Rejected candidates

| Candidate | Reason rejected |
|---|---|
| <suspected issue> | <middleware covers it / field is public / not attacker-controlled> |

## Coverage

| Area | Tested | Notes |
|---|---|---|
| Authentication | yes/no | |
| Action-Level BOLA | yes/no | |
| Direct Reference BOLA | yes/no | |
| Tenant isolation | yes/no | |
| Workflow-Context | yes/no | |
| Chained disclosure | yes/no | |
| Object rebinding | yes/no | |
| Vertical escalation | yes/no | |
| Mass assignment | yes/no | |
| Race conditions | yes/no | |
| Data leakage | yes/no | |
| Business logic invariants | yes/no | |

## Summary

<2-3 sentences: how many confirmed, the worst one, and what to fix first.>
