# Authorization Testing: The Six BOLA Families

Load this when writing authorization tests or judging whether an access-control finding is real.

Source: empirical taxonomy of 107 classified HackerOne disclosures, 2021–2026 (Kaur, arXiv:2605.25865). Frequencies below are from that dataset — they tell you where to spend effort.

## Why families, not "IDOR"

"IDOR" names the *mechanism*; BOLA names the *root cause* (the server never checked whether this user may access this object). Testing only "change the ID in the URL" covers roughly a third of real cases. The six families below partition confirmed disclosures.

| Family | Share | What fails |
|---|---|---|
| Action-Level Object | 41.7% | you may call the endpoint, but not act on *this* object |
| Direct Object Reference | 36.9% | identifier substitution, single request |
| Tenant Isolation | 8.3% | cross-organization boundary |
| Workflow-Context | 6.0% | object state (archived/deactivated) should revoke access |
| Chained Disclosure | 4.8% | leaked ID from endpoint A used at endpoint B |
| Object Rebinding | 2.4% | client-supplied ownership field trusted |

Authorization direction: **85.7% horizontal** (peer-to-peer), **11.9% vertical** (user → admin object). State-changing actions total **46.4%**.

## Test shape for each family

Assume fixtures: `alice` and `bob`, each owning one object of the type under test; plus `admin` and a second tenant `org_b`.

### 1. Action-Level Object (highest yield)

You legitimately own the function; the object isn't yours.

```python
# Own path works
alice.post(f"/tasks/{alice_task}/archive").assert_ok()
# Same endpoint, bob's object, alice's session
r = alice.post(f"/tasks/{bob_task}/archive")
assert r.status in (403, 404), f"BOLA: alice archived bob's task -> {r.status}"
```

Cover every state-changing verb for every owned-object endpoint: `DELETE`, `PATCH`, `POST /approve`, `/transfer`, `/refund`, `/invite`, `/impersonate`, `/trigger`. Trigger-style endpoints that cause side effects without modifying the object are the easiest to miss.

### 2. Direct Object Reference

```python
for ident in (bob_id, bob_uuid, bob_username, bob_email):
    r = alice.get(f"/invoices/{ident}")
    assert r.status in (403, 404)
```

Vary the identifier type: sequential int, UUID, username, email, encoded/base64 ID, hash. Non-sequential IDs do not remove the risk — they only remove the guessing step.

Test enumeration explicitly when IDs are sequential: request `id+1` right after creating your own object. That is the highest-frequency mechanism observed (22.6%).

### 3. Tenant Isolation

For any multi-tenant system, register two organizations:

```python
r = alice_of_org_a.post("/bugs.json", json={"organization_id": org_b_id})
assert r.status in (403, 404)
```

The signal in real reports was accepting an `organization_id`/`tenant_id` from the request while only validating that the session is logged in. Test header-based tenant scoping (`X-Tenant-Id`) and subdomain scoping too.

### 4. Workflow-Context

Authorization was evaluated when access was granted and never re-evaluated:

```python
# Access works while the object is active
assert alice.get(f"/customers/{customer}").ok
# After the relationship is revoked / the object is archived:
admin.post(f"/customers/{customer}/remove_staff", json={"staff": "alice"})
assert alice.get(f"/customers/{customer}").status in (403, 404)
```

Test: archived/draft/deactivated/deleted/transferred states; after a role is revoked; after a member leaves the org; after a post is made private.

### 5. Chained Disclosure

Two-step: the leak is at endpoint A, the missing check is at endpoint B.

```python
# Step 1: does A return an identifier scoped to someone else?
preview = alice.get(f"/messages/{bob_message}/preview")
leaked = extract_id(preview)          # attachment token, document ID, etc.
# Step 2: can that identifier be redeemed without an ownership check?
r = alice.get(f"/attachments/{leaked}")
assert r.status in (403, 404)
```

Map every endpoint that returns a foreign identifier before testing. A response that leaks an ID is the precondition; the finding is the consuming endpoint's missing check.

### 6. Object Rebinding

The server trusts a client-supplied ownership field.

```python
r = alice.patch(f"/documents/{alice_doc}", json={"owner_id": bob_id})
assert r.status in (400, 403)
# Then confirm ownership did not actually move
assert bob.get(f"/documents/{alice_doc}").status in (403, 404)
```

Grep for `owner_id`, `account_id`, `user_id`, `tenant_id`, `msg.Sender`, `from`, `author` in request schemas. If the server derives ownership from the session, these fields must be ignored, not just validated.

## Vertical escalation

A lower-privileged user acting on a higher-privileged object. The role is legitimately allowed to call the endpoint; the missing control is object ownership.

```python
r = alice.post(f"/admin/users/{admin_id}/api_key", json={"rotate": True})
assert r.status in (403, 404)
```

Do not confuse this with RBAC/BFLA. BFLA = the endpoint itself is not role-gated. Vertical BOLA = the endpoint is reachable, but the *object* belongs to an admin.

## BFLA and mass assignment (adjacent, still test them)

- **BFLA**: call admin-only endpoints with a user session, including undocumented methods (`PATCH` vs `POST`), internal paths, and batch endpoints.
- **Mass assignment**: send extra fields (`role`, `is_admin`, `verified`, `balance`, `plan`, `tenant_id`) and check whether they persist. Then re-read the object with a fresh GET.

## Method-override and bypass checks

- `GET` blocked but `HEAD`/`OPTIONS`/`POST` open on the same path.
- Trailing slash, case variation, `.json` suffix, path traversal (`/api/v1/../admin`).
- Batch/bulk endpoints that accept a list of IDs — a single-item check is frequently missing there.
- GraphQL: same object reachable through a different field or a nested node ID.

## Judging a finding

A real authorization finding has all four:

1. Two principals with distinguishable objects.
2. Attacker-controlled identifier or ownership field.
3. A successful cross-boundary operation (not just a 200 — check the side effect).
4. No server-side scoping at the query layer.

If any is missing, it is unverified. See [false-positive.md](false-positive.md).
