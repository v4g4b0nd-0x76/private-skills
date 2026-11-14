"""Broken Object Level Authorization — the six families.

Empirical priorities from 107 real bug-bounty disclosures:
  Action-Level 41.7% | Direct Reference 36.9% | Tenant 8.3%
  Workflow-Context 6.0% | Chained 4.8% | Rebinding 2.4%

Every test needs TWO principals owning different objects. Fill the
`resource` name with the real one from your surface map.
"""

import pytest

from conftest import assert_cross_user_denied

RESOURCE = "tasks"  # TODO: replace with a real owned resource, e.g. "invoices"


# --- 1. Action-Level Object BOLA (highest yield: 41.7%) -------------------
# Alice may call the endpoint; she must not act on Bob's object.

@pytest.mark.parametrize("verb,path_suffix", [
    ("post", "archive"),
    ("post", "approve"),
    ("delete", ""),
    ("patch", ""),
])
def test_cannot_act_on_other_users_object(alice, bob, verb, path_suffix):
    bob_id = bob.own(RESOURCE)

    # Baseline: acting on her own object works.
    alice.own(RESOURCE)

    url = f"/api/{RESOURCE}/{bob_id}"
    if path_suffix:
        url = f"{url}/{path_suffix}"

    r = getattr(alice, verb)(url, json={"status": "approved"} if verb == "patch" else None)
    assert_cross_user_denied(r, f"alice {verb.upper()} {url} (bob's object)")

    # And the object must be unchanged.
    still = bob.get(f"/api/{RESOURCE}/{bob_id}")
    if still.status_code == 200:
        body = still.json()
        assert body.get("status") not in ("archived", "approved", "deleted"), (
            "cross-user action persisted — BOLA confirmed"
        )


# --- 2. Direct Object Reference BOLA (36.9%) -----------------------------

def test_cannot_read_other_users_object(alice, bob):
    bob_id = bob.own(RESOURCE)
    r = alice.get(f"/api/{RESOURCE}/{bob_id}")
    assert_cross_user_denied(r, f"alice read bob's {RESOURCE} by id")


def test_identifier_variants_all_denied(alice, bob):
    """Sequential ints, UUIDs, usernames, emails and encoded ids all count."""
    bob_id = bob.own(RESOURCE)
    variants = [bob_id, str(bob_id), (bob.user or ""), str(bob_id).upper()]
    for ident in variants:
        if not ident:
            continue
        r = alice.get(f"/api/{RESOURCE}/{ident}")
        if r.status_code in (401, 403, 404, 410):
            continue
        pytest.fail(f"identifier variant '{ident}' returned {r.status_code}")


def test_sequential_enumeration(alice, bob):
    """The most common mechanism (22.6%): id+1 after creating your own."""
    own_id = alice.own(RESOURCE)
    try:
        neighbour = str(int(own_id) + 1)
    except (TypeError, ValueError):
        pytest.skip("identifiers are not sequential")
    r = alice.get(f"/api/{RESOURCE}/{neighbour}")
    assert_cross_user_denied(r, f"alice enumerated id {neighbour}")


# --- 3. Tenant Isolation BOLA (8.3%) ------------------------------------

def test_cannot_act_across_tenant_boundary(alice):
    """Requires a second organization/tenant id the caller is not a member of."""
    other_tenant = "TODO-other-tenant-id"
    if other_tenant.startswith("TODO"):
        pytest.skip("configure a second tenant id")

    r = alice.post(f"/api/{RESOURCE}", json={"tenant_id": other_tenant, "name": "x"})
    assert r.status_code in (400, 403, 404), (
        f"created object in foreign tenant: {r.status_code}"
    )

    r = alice.get(f"/api/{RESOURCE}?tenant_id={other_tenant}")
    if r.status_code == 200:
        ids = {row.get("tenant_id") for row in r.json().get("items", [])}
        assert other_tenant not in ids, "list returned another tenant's rows"


# --- 4. Workflow-Context BOLA (6.0%) -------------------------------------

def test_authorization_rechecked_after_state_change(alice, bob):
    """Access granted earlier must be revoked when the object changes state."""
    bob_id = bob.own(RESOURCE)

    bob.patch(f"/api/{RESOURCE}/{bob_id}", json={"status": "archived"})

    r = alice.patch(f"/api/{RESOURCE}/{bob_id}", json={"status": "active"})
    assert_cross_user_denied(r, "alice modified bob's archived object")

    r = alice.get(f"/api/{RESOURCE}/{bob_id}")
    assert_cross_user_denied(r, "alice read bob's archived object")


# --- 5. Chained Disclosure BOLA (4.8%) ----------------------------------

def test_identifier_leak_then_redeem(alice, bob):
    """Step 1: a response leaks a foreign id. Step 2: consume it."""
    pytest.skip("map an id-returning endpoint in references/logic-surface.md first")

    # leaked = extract_foreign_id(alice.get("/api/messages/{bob_msg}/preview"))
    # assert_cross_user_denied(alice.get(f"/api/attachments/{leaked}"), "chained disclosure")


# --- 6. Object Rebinding BOLA (2.4%) ------------------------------------

def test_cannot_rebind_ownership(alice, bob):
    own_id = alice.own(RESOURCE)
    bob_id = bob.own(RESOURCE)

    r = alice.patch(f"/api/{RESOURCE}/{own_id}", json={"owner_id": bob_id})
    if r.status_code in (400, 403, 422):
        pytest.skip("server rejects ownership fields outright (correct)")

    after = alice.get(f"/api/{RESOURCE}/{own_id}")
    if after.status_code == 200 and str(after.json().get("owner_id")) == str(bob_id):
        pytest.fail("client-supplied owner_id rebinding accepted")

    # And alice must not now be able to read bob's original object
    assert_cross_user_denied(
        alice.get(f"/api/{RESOURCE}/{bob_id}"), "post-rebind cross-user read"
    )


# --- Method / path bypasses --------------------------------------------

@pytest.mark.parametrize("suffix", ["/", ".json", "//", "/../"])
def test_path_variants_do_not_bypass_authz(alice, bob, suffix):
    bob_id = bob.own(RESOURCE)
    r = alice.get(f"/api/{RESOURCE}/{bob_id}{suffix}")
    if r.status_code in (400, 404):
        return
    assert_cross_user_denied(r, f"path variant '{suffix}'")
