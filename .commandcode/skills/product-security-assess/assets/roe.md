---
authorized: false
valid_from: YYYY-MM-DD
valid_until: YYYY-MM-DD
stop_contact: ""
credentials.ref: ""
code-root: ""
approval_reference: ""
---

# Rules of engagement

## Scope

- Targets: (domains / IPs / ports from init)

## Out of scope

- Third-party hosts, DoS, social engineering, physical

## Allowed actions

- Bright non-destructive scans by default
- Destructive / mutating only when DESTRUCTIVE_ARMED

## Stop conditions

- Page stop_contact on customer impact, auth lockouts, or error-rate spike

## Data handling

- No secrets or customer PII in `.product-security/` artifacts
