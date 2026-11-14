# Hunter Report: <hunter-id>

- **Class:** <bola | injection | authn | authz | logic | leakage>
- **Target:** <service>
- **Budget:** <hypotheses or minutes> (used: <n>)
- **Findings:** <confirmed n> confirmed, <unverified n> unverified, <rejected n> rejected

## Summary

<one paragraph: what you covered, the strongest result, and whether the class
looks defended or broken>

## Confirmed findings

### <title>

- **Endpoint:** `<METHOD /path>`
- **Severity:** <critical|high|medium|low>
- **Fingerprint (root cause):** <missing-owner-check | trusted-client-role | ...>
- **Reproduction:**
  ```
  1. <as principal A, do X>
  2. <send Y>
  3. <observe Z>
  ```
- **Observed:** <the effect: data returned, state changed, access gained>
- **Expected:** <what a correct implementation does>
- **Impact:** <who can do what they should not>

## Unverified

### <title>
- **Why not proven:** <missing piece>
- **What would confirm it:** <the next test>

## Rejected hypotheses

| Hypothesis | Why it failed |
|---|---|
| <"server trusts the role header"> | <stripped by middleware; verified by ...> |

## Coverage

| Area | Tested | Notes |
|---|---|---|
| <sub-area of this class> | yes/no | |

## Would test next

<ordered list, assuming more budget>
