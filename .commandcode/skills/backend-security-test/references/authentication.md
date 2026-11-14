# Authentication Testing

Load this when testing session, token, or credential handling.

## What actually breaks

Authentication failures cluster into a few patterns. Test these, in this order — they are ordered by how often they produce real findings.

### 1. Token validation gaps

| Test | How | Real failure signal |
|---|---|---|
| No token | remove the header entirely | 200 on a protected route |
| Malformed token | `Authorization: Bearer x` | 200, or a 500 with a stack trace |
| Expired token | use one past `exp` | 200 |
| `alg: none` | re-sign with `"alg":"none"`, empty signature | 200 |
| Algorithm confusion | RS256 public key pasted as HS256 secret | 200 |
| Signature stripped | keep payload, truncate signature | 200 |
| `kid` injection | point `kid` at a path or a traversal | key confusion |
| `exp`/`iat` missing | omit both claims | 200 if the library does not require them |

Always decode a sample token and inspect the claims before testing. Look for: `iss`, `aud`, `sub`, `exp`, `nbf`, and any role or tenant claim. A token that carries `role` or `tenant_id` is a mass-assignment target if the server trusts it over the database.

### 2. Session handling

- **Session fixation**: accept a pre-set session ID before login, then confirm the ID changes after authentication.
- **Logout invalidation**: use the old token after logout; it must fail. Server-side sessions must be destroyed, not just the cookie cleared.
- **Expiry**: absolute and idle timeouts both enforced server-side, not by the client.
- **Concurrent sessions**: decide the policy and verify it holds; silent unlimited sessions are a finding only if the policy says otherwise.
- **Cookie flags**: `Secure`, `HttpOnly`, `SameSite=Lax/Strict` on session cookies.
- **Predictability**: session IDs must be random (CSPRNG), not timestamps or counters.

### 3. Credential flows

- **User enumeration**: same response and timing for existing vs nonexistent accounts on login, registration, and password reset.
- **Password reset**: token entropy, single use, expiry, bound to the account, and not returned in the response body.
- **Rate limiting**: brute force the login endpoint and measure. Missing limits are real findings for authentication.
- **Timing**: constant-time comparison for secrets and password hashes.
- **MFA bypass**: skip the second factor by calling the post-MFA endpoint directly; test whether the pre-MFA session is privileged enough.
- **OAuth/OIDC**: `redirect_uri` exact-match allowlist (no prefix or wildcard matching), `state` CSRF binding, PKCE on public clients, `nonce` validation, ID token signature and `aud` check.

### 4. Credential storage (white-box only)

```bash
# What is used to hash passwords?
grep -rnE 'bcrypt|argon2|scrypt|pbkdf2|sha256|md5' <backend-root>
```

- Acceptable: `argon2id`, `bcrypt` (cost >= 12), `scrypt`, `pbkdf2` with high iterations.
- Finding: MD5/SHA1/SHA256 of a password, unsalted hashes, home-grown schemes.
- Also check: secrets in source, default credentials in config/fixtures, tokens logged.

## Test matrix

Write one test per row that applies to the system:

```python
def test_protected_route_requires_token(client):
    assert client.get("/api/me", headers={}).status in (401, 403)

def test_tampered_signature_rejected(client, alice_token):
    tampered = alice_token[:-4] + "AAAA"
    assert client.get("/api/me", headers={"Authorization": f"Bearer {tampered}"}).status == 401

def test_expired_token_rejected(client, expired_token):
    assert client.get("/api/me", headers={"Authorization": f"Bearer {expired_token}"}).status == 401

def test_logout_invalidates_token(client, alice_token):
    client.post("/api/logout", headers={"Authorization": f"Bearer {alice_token}"})
    assert client.get("/api/me", headers={"Authorization": f"Bearer {alice_token}"}).status == 401

def test_alg_none_rejected(client):
    forged = make_unsigned_token(sub="alice", role="admin")
    assert client.get("/api/me", headers={"Authorization": f"Bearer {forged}"}).status == 401
```

## Gotchas

- A 401 on the happy path does not prove validation. Send no token, a garbage token, an expired token, and a token for a deleted user — each separately.
- Distinguish "401 unauthenticated" from "403 authenticated but forbidden"; treating them the same hides authz bugs.
- Clock skew makes expiry tests flaky; generate the expired token with an explicit `exp` in the past.
- Checking the cookie in the browser is not a server-side test. Delete the header at the HTTP layer.
- SSO/IdP behavior is usually fine; the bugs are in *your* handling of the returned token.
