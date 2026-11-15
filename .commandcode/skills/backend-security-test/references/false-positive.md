# False Positives and False Negatives

Load this before writing up any finding, and before concluding that the backend is clean.

## Why this page exists

Security testing fails in both directions, and both are expensive:

- A **false positive** wastes engineering time, erodes trust in the report, and buries real findings.
- A **false negative** is the vulnerability that ships.

The empirical BOLA study (Kaur, arXiv:2605.25865) sampled 200 HackerOne disclosures tagged IDOR/Improper Access Control: 107 were fully classified and **84 of 200 (42%)** were confirmed in-scope BOLA; of the classified set, **78.5%** confirmed and **21.5%** failed strict BOLA criteria. Tag counts alone overstate the signal. Hold your own findings to the same standard.

## Killing a candidate finding (run this on every one)

| # | Question | If the answer is... | Then |
|---|---|---|---|
| 1 | Is the identifier or ownership field attacker-controlled, or server config? | server config / env / constant | **not a finding** |
| 2 | Did I trace the value from request to sink in the code? | no | **unverified**, go read it |
| 3 | Is there middleware, decorator, ORM scope, or DB policy covering this? | yes, and it covers this verb/path | **not a finding** |
| 4 | Did the operation actually cross a boundary and persist? | response was 2xx but state unchanged | **not a finding** |
| 5 | Does it reproduce with fresh accounts and fresh objects? | no | **unverified**, likely fixture contamination |
| 6 | Is the exposed field documented as public? | yes | **not a finding** (or Low at most) |
| 7 | Is this the framework's intended behavior that the team has configured? | yes | **note**, not a finding |

Record the answers in the report. A finding without this trail is an allegation.

## Common false positives

- **403 on the unauthenticated path only.** Proves authn, not authz. Test the authorized path against someone else's object.
- **200 with an empty list.** Often means the filter worked. Confirm by creating an object that *should* appear.
- **404 instead of 403.** Many frameworks return 404 to avoid existence disclosure — that is correct behavior, not a bug.
- **Server-controlled URLs in SSRF.** `settings.API_URL` is not attacker-controlled; `request.args['url']` is.
- **ORM parameterized calls** flagged as SQL injection (`User.objects.filter(id=input)` is safe; `.raw()` with interpolation is not).
- **Auto-escaped templates** flagged as XSS (`{{ var }}` in Django/Jinja with default autoescape).
- **IDs that are not authorization boundaries** because the object is public content (published posts, public profiles).
- **Rate limiting "missing"** on an endpoint the infrastructure layer protects (CDN/WAF/gateway) — check before reporting.
- **Race test that fired requests sequentially**, or asserted only on response codes.
- **Enumeration of a public directory** (usernames are public by design).
- **A 500 from malformed input** with no data disclosed and no attacker influence — a robustness bug, not security.

## Common false negatives (where teams stop too early)

- Only testing `GET` (misses 46.4% of confirmed BOLA).
- Only horizontal testing (misses 11.9% vertical).
- Only the happy object state (misses Workflow-Context).
- Only the documented endpoint (misses method override, batch endpoints, alternate routes).
- Single-account testing (cannot prove any cross-user boundary).
- Trusting UUIDs (39.2% of known-format cases were non-sequential).
- Not decoding GraphQL Global IDs (decode → increment → re-encode).
- No concurrency (races invisible), no state reset between attempts.
- Testing the UI and concluding the API is safe.

## Confidence language

Use exactly these three, no others:

- **confirmed** — exploited end-to-end, with reproduction and observed wrong state.
- **unverified** — plausible, but a code path or a check is unread. Say what would confirm it.
- **rejected** — investigated and disproven, with the reason. Include these in the report; they show coverage and stop the team re-testing.

## Self-check before finalizing

- [ ] Every "confirmed" finding has a repro a second engineer can run
- [ ] Every finding states which layer was checked and found missing
- [ ] Every rejected candidate has a one-line reason
- [ ] No finding relies on a status code alone
- [ ] The report says explicitly what was **not** tested
