"""Mass assignment and ownership-field injection.

The server must derive ownership and privilege from the authenticated session,
never from the request body.
"""

import pytest


PRIVILEGE_FIELDS = ["role", "is_admin", "admin", "verified", "email_verified",
                    "balance", "credits", "plan", "tier", "permissions",
                    "owner_id", "user_id", "tenant_id", "account_id"]


def test_privilege_fields_not_accepted_on_update(alice):
    RESOURCE = "tasks"  # TODO
    own_id = alice.own(RESOURCE)

    payload = {f: ("admin" if f in ("role", "plan", "tier") else True)
               for f in PRIVILEGE_FIELDS}
    r = alice.patch(f"/api/{RESOURCE}/{own_id}", json=payload)
    if r.status_code in (400, 403, 422):
        return  # rejected outright: correct

    after = alice.get(f"/api/{RESOURCE}/{own_id}")
    if after.status_code != 200:
        pytest.skip("cannot re-read the object")

    body = after.json()
    for field, sent in payload.items():
        got = body.get(field)
        assert got != sent, f"mass assignment accepted for '{field}' -> {got!r}"


def test_ownership_derived_from_session_not_body(alice, bob):
    RESOURCE = "tasks"  # TODO
    bob_id = bob.own(RESOURCE)

    r = alice.post(f"/api/{RESOURCE}", json={"name": "x", "owner_id": bob_id, "user_id": bob_id})
    if r.status_code >= 400:
        return

    created = r.json()
    owner = str(created.get("owner_id") or created.get("user_id") or "")
    assert owner != str(bob_id), "created object assigned to another principal"

    # The creator must be able to read what they created
    obj_id = created.get("id")
    assert alice.get(f"/api/{RESOURCE}/{obj_id}").status_code == 200
    # ...and bob must not
    assert bob.get(f"/api/{RESOURCE}/{obj_id}").status_code in (403, 404)


def test_registration_cannot_set_role(alice, unique_email):
    import requests
    from conftest import BASE_URL, TIMEOUT

    r = requests.post(f"{BASE_URL}/api/auth/register", timeout=TIMEOUT, json={
        "email": unique_email, "password": "Aa1!aaaaaaa", "role": "admin", "is_admin": True,
    })
    if r.status_code >= 400:
        return  # registration closed or validated: fine

    token = r.json().get("access_token")
    if not token:
        pytest.skip("registration returns no token to inspect")
    me = requests.get(f"{BASE_URL}/api/me",
                      headers={"Authorization": f"Bearer {token}"}, timeout=TIMEOUT)
    if me.status_code == 200:
        assert me.json().get("role") != "admin", "self-registration granted admin"
