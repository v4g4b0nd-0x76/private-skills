# Data Leakage

Load this when testing responses, errors, logs, caches, or anything that could carry one user's data to another.

## Where data escapes

Work outward from the object: response body, headers, errors, caches, logs, side channels.

### 1. Over-fetching (excessive data exposure)

The endpoint returns more fields than the UI shows, and the client is expected to filter.

```bash
# Attack: request one object and inspect every field
curl -s -H "Authorization: Bearer $TOKEN" "$BASE/api/users/me" | jq 'keys'
```

Look for: `password_hash`, `password`, `salt`, `mfa_secret`, `internal_*`, `stripe_customer_id`, `ssn`, `iban`, `api_key`, `*_token`, `deleted_at`, other users' emails, admin notes.

Test the *other* user's view of the same object: a list endpoint often returns full records where the detail endpoint redacts them.

### 2. Error disclosure

Trigger failures and read what comes back: `500` with a stack trace, SQL errors naming tables/columns, framework debug pages, internal hostnames, connection strings, file paths, dependency versions.

```python
for bad in ("'", "../../", "null", "[]", "{\"a\":", "%00"):
    r = alice.get(f"/api/items/{bad}")
    assert_no_internals(r.text)   # paths, stack frames, SQL, env values
```

Fail-open is worse: an invalid input that returns 200 with empty data usually means the check was skipped.

### 3. Cross-user leakage through aggregates

- List endpoints that paginate over all rows instead of the caller's rows.
- Search/autocomplete that matches other users' records.
- Counts and metrics that reveal others' volume.
- Export/report endpoints (`/export.csv`, `/admin/reports`) with weaker checks than the UI path.
- Webhooks and event payloads sent to the wrong subscriber.

### 4. Caching and headers

- `Cache-Control` on authenticated responses; a shared/CDN cache can serve one user's body to another. Test with two sessions and inspect `Age`, `X-Cache`.
- `Vary` missing on the auth-related header.
- Sensitive data in `Location`, `Referer`, `X-Debug-*`, or a custom `X-User-Id`.
- CORS: `Access-Control-Allow-Origin: *` together with credentials, or reflecting an arbitrary `Origin`.
- Server headers leaking versions, internal IPs, or debug flags.

### 5. Logs and telemetry (white-box)

```bash
grep -rnE '\b(log|logger|println!|console\.log|fmt\.Print|print)\b.*(password|token|secret|authorization|cookie|ssn|card)' <backend-root>
```

- Credentials, tokens, and PII must never be logged.
- Log injection: user input written raw into logs allows forging entries (newlines).
- Same for tracing spans and error trackers (Sentry-style breadcrumbs).

### 6. Side channels

- Timing differences that reveal whether a record exists.
- Response-size differences (`404` body vs `403` body).
- Sequential IDs leaking volume of business.
- Bond/GraphQL introspection or `OPTIONS` revealing undocumented fields and mutations.

### 7. Storage and transport (white-box)

- PII in plaintext columns where the schema implies encryption.
- Backups, dumps, `.env` files, or fixture files committed with production-looking data.
- Secrets in source or CI config.
- TLS not enforced on internal calls that carry tokens.

## Test matrix

```python
def test_me_does_not_leak_secrets(alice):
    body = alice.get("/api/users/me").json()
    for field in ("password", "password_hash", "mfa_secret", "api_key"):
        assert field not in body

def test_list_returns_only_own_records(alice, bob):
    ids = {row["id"] for row in alice.get("/api/orders").json()["items"]}
    assert bob_order_id not in ids

def test_error_has_no_internals(alice):
    r = alice.get("/api/orders/not-a-number")
    assert "Traceback" not in r.text and "SELECT" not in r.text.upper()

def test_authenticated_response_not_publicly_cacheable(alice):
    r = alice.get("/api/users/me")
    assert "public" not in r.headers.get("cache-control", "").lower()
```

## Judging the result

Leakage findings need the *sensitivity* of the field argued explicitly. Returning `created_at` or a public `username` is not a leak. Returning another user's email, token, hash, or financial identifier is.

Check whether the field is documented as public before reporting it.
