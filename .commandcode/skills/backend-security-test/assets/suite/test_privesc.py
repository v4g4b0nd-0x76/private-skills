"""Vertical privilege escalation (11.9% of confirmed BOLA, and under-tested).

The role is legitimately allowed to call the endpoint. The missing control is
object ownership: a normal user acting on an admin's object.
"""

import pytest

from conftest import assert_cross_user_denied


def test_user_cannot_act_on_admin_object(alice, admin):
    if not admin.token:
        pytest.skip("admin not configured")

    admin_resource = admin.own("admin_resource")  # TODO: fill in fixtures

    r = alice.delete(f"/api/users/{admin_resource}")
    assert_cross_user_denied(r, "alice acted on an admin-owned object")

    r = alice.patch(f"/api/users/{admin_resource}", json={"role": "user"})
    assert_cross_user_denied(r, "alice modified an admin-owned object")


def test_admin_only_routes_reject_user(alice):
    """BFLA: the endpoint itself must be role-gated."""
    for path in ("/api/admin/users", "/api/admin/audit", "/api/admin/settings"):
        r = alice.get(path)
        if r.status_code == 404:
            continue
        assert r.status_code in (401, 403), f"{path} reachable by non-admin"


@pytest.mark.parametrize("method,path", [
    ("post", "/api/admin/users"),
    ("delete", "/api/admin/users/1"),
    ("patch", "/api/admin/settings"),
])
def test_admin_mutations_reject_user(alice, method, path):
    r = getattr(alice, method)(path, json={})
    if r.status_code == 404:
        pytest.skip(f"{path} not present")
    assert r.status_code in (401, 403, 405), f"{method.upper()} {path} not role-gated"


def test_role_not_escalatable_via_profile_update(alice):
    """Mass assignment of privilege fields through the profile endpoint."""
    for payload in ({"role": "admin"}, {"is_admin": True}, {"permissions": ["*"]}):
        alice.patch("/api/me", json=payload)

    me = alice.get("/api/me")
    if me.status_code != 200:
        pytest.skip("no profile endpoint")
    body = me.json()
    assert body.get("role") != "admin", "role escalated via profile update"
    assert body.get("is_admin") is not True, "is_admin escalated via profile update"
    assert body.get("permissions") != ["*"], "permissions escalated via profile update"


def test_header_and_query_role_override_ignored(alice):
    """Never trust role from a header or query parameter."""
    r = alice.get("/api/admin/users",
                  headers={"X-Role": "admin", "X-User-Role": "admin"},
                  params={"role": "admin", "is_admin": "true"})
    if r.status_code == 404:
        pytest.skip("no admin route")
    assert r.status_code in (401, 403), "role header/query trusted by the server"
