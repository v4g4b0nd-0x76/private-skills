# Inventorying Third-Party Requirements

Load this after `inventory.sh` and before writing any test. A test against an unmapped dependency is a guess.

## What counts as third party

Anything the process does not own:

- External SaaS APIs (payments, email, SMS, KYC, shipping, maps, LLM providers)
- Other teams' internal services reachable over the network
- Managed infrastructure you connect to by URL: object storage, managed queues, hosted search
- SDKs and packages whose behavior you depend on: clients, auth libraries, serializers
- Inbound third parties: webhooks, SSO/OIDC providers, partner callbacks

Not third party: your own database you run, your own services you deploy together, language standard library.

## Per-integration record

Fill this for every entry. Missing fields are findings.

```markdown
## <Provider name>

- Purpose: <what business function breaks without it>
- Called from: <file:line, module, or job name>
- Endpoint / base URL: <config key or env var holding it>
- Auth: <API key | OAuth2 client credentials | mTLS | signed webhook>
- Credential storage: <env var, secret manager, vault path>
- Contract: <REST version, gRPC proto, SDK version>
- Documented SLA: <latency, uptime, maintenance windows>
- Rate limit: <requests/sec or /month, per account or per endpoint>
- Timeout configured in app: <value, and where>
- Retry policy in app: <attempts, backoff, jitter, where>
- Failure fallback: <degrade, queue, fail request, serve stale>
- Data sent: <PII, payment data, tokens, nothing sensitive>
- Sandbox: <URL, how to get test credentials>
- Owner (internal): <team responsible for the integration>
- If provider is down: <user-visible impact>
- If provider is slow: <timeout behaviour, thread/connection impact>
- If provider returns 5xx: <retry? surface error? fallback?>
- If provider returns 429: <backoff? queue? fail?>
```

## Where to look

| Source | What it reveals |
|---|---|
| `package.json` / `pyproject.toml` / `Cargo.toml` / `go.mod` | SDKs, and often the provider name |
| `.env`, `.env.example`, `config/*.yaml`, Helm values | endpoint URLs, API keys, regions |
| `grep -rE 'https?://[a-z0-9.-]+' src/` | hardcoded endpoints |
| HTTP client construction sites | base URL, timeout, retry, interceptors |
| Webhook route handlers | inbound providers and their signature checks |
| outgoing-request middleware | retries, tracing, auth injection |
| queue/topic names | managed broker integrations |
| CI secrets list | which providers exist in test environments |

## Classification you will need

For each provider decide:

1. **Can it be run locally?** (container, emulator) → integration test with the real thing.
2. **Does it have a sandbox?** → nightly E2E against the sandbox.
3. **Neither?** → virtualize, and record that this is the only coverage.

Write the decision into the record. "Virtualized because no sandbox" is a risk you are accepting, not a detail.

## Common blind spots

- **SDK-managed dependencies** (an auth library calling a token endpoint) hide a network dependency. Grep for the library and follow it.
- **CDN/edge providers**: upload, image transform, WAF. Usually invisible until they fail.
- **Transactional email** is often assumed reliable; it is a provider with rate limits and deliverability rules.
- **DNS, TLS certs, and clocks** are third-party requirements too. If the app pins a cert or depends on time sync, record it.
- **Feature flags and config services** are runtime dependencies; an outage disables your kill switch.
- **Test-mode vs live-mode mismatch**: Stripe-style providers have separate keys and often separate data. Record which mode the test env uses.

## Deliverable

`.thirdparty/requirements.md` with one section per provider plus a summary table:

| Provider | Purpose | Auth | Rate limit | Fallback | Test approach |
|---|---|---|---|---|---|
| payments-co | charge/refund | API key | 100 rps | fail request, no retry storm | sandbox nightly |
| email-co | transactional email | OAuth2 | 50 rps | queue, retry with backoff | WireMock + sandbox |
| auth-idp | SSO login | OIDC | n/a | deny login | real sandbox |

That table is what Step 2 and Step 3 consume. Keep it current; it is the artifact reviewers will read.
