# Third-Party Requirements

One section per external dependency. A missing field is a finding, not a formality.

## Summary

| Provider | Purpose | Auth | Rate limit | Fallback | Test approach |
|---|---|---|---|---|---|
| <payments-co> | <charge/refund> | <API key> | <100 rps> | <fail request, no retry storm> | <sandbox nightly> |
| <email-co> | <transactional email> | <OAuth2> | <50 rps> | <queue + backoff> | <WireMock + sandbox> |

## <Provider name>

- Purpose:
- Called from: <file:line>
- Endpoint / config key:
- Auth:
- Credential storage:
- Contract / version:
- Documented SLA:
- Rate limit:
- App timeout: <value, where configured>
- Retry policy: <attempts, backoff, jitter>
- Failure fallback:
- Data sent: <PII / payment data / tokens>
- Sandbox:
- Internal owner:
- If down: <user-visible impact>
- If slow: <timeout behaviour>
- If 5xx: <behaviour>
- If 429: <behaviour>

## Libraries and packages

| Package | Version | Used for | Risk noted |
|---|---|---|---|
| <pkg> | <1.2.3> | <http client> | <advisory / maintenance> |
