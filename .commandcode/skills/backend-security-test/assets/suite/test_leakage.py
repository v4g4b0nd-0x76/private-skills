"""Data leakage: over-fetch, error disclosure, cross-user aggregates, caching."""

import pytest

from conftest import BASE_URL, TIMEOUT

SECRET_FIELDS = ["password", "password_hash", "salt", "mfa_secret", "api_key",
                 "access_token", "refresh_token", "internal_notes", "ssn",
                 "iban", "card_number", "stripe_customer_id"]


def test_self_endpoint_does_not_expose_secrets(alice):
    r = alice.get("/api/me")
    if r.status_code != 200:
        pytest.skip("/api/me not present")
    body = r.json()
    for field in SECRET_FIELDS:
        assert field not in body, f"/api/me leaks '{field}'"


def test_list_endpoint_scoped_to_caller(alice, bob):
    RESOURCE = "orders"  # TODO
    bob_id = bob.own(RESOURCE)

    r = alice.get(f"/api/{RESOURCE}")
    if r.status_code != 200:
        pytest.skip(f"/api/{RESOURCE} list not present")

    rows = r.json()
    rows = rows.get("items", rows) if isinstance(rows, dict) else rows
    ids = {str(row.get("id")) for row in rows if isinstance(row, dict)}
    assert str(bob_id) not in ids, "list endpoint returns another user's rows"


def test_error_paths_do_not_leak_internals(alice):
    probes = ["/api/items/'", "/api/items/%00", "/api/items/not-a-number",
              "/api/items/..%2f..%2fetc%2fpasswd"]
    markers = ["Traceback", "at Object.", "SELECT ", "sqlite", "postgres",
               "Exception", "/Users/", "/home/", "node_modules"]

    for path in probes:
        r = alice.get(path)
        text = r.text
        for marker in markers:
            assert marker.lower() not in text.lower(), (
                f"{path} leaks '{marker}' (HTTP {r.status_code})"
            )


def test_authenticated_response_not_publicly_cacheable(alice):
    r = alice.get("/api/me")
    if r.status_code != 200:
        pytest.skip("/api/me not present")
    cache = (r.headers.get("cache-control") or "").lower()
    assert "public" not in cache, "authenticated response marked public cacheable"


def test_cors_not_wildcard_with_credentials(alice):
    origin = "https://evil.example.test"
    r = alice.get("/api/me", headers={"Origin": origin})
    allow = r.headers.get("access-control-allow-origin", "")
    creds = (r.headers.get("access-control-allow-credentials") or "").lower()
    if allow == "*" and creds == "true":
        pytest.fail("CORS allows any origin with credentials")
    assert origin not in allow, "CORS reflects an arbitrary origin"


def test_no_sequential_volume_leak(alice):
    """404 vs 403 differences or counters can reveal another tenant's volume."""
    r = alice.get("/api/stats")
    if r.status_code != 200:
        pytest.skip("no stats endpoint")
    body = r.json()
    for key in ("total_users", "total_orders", "org_count"):
        if key in body:
            pytest.fail(f"global aggregate '{key}' exposed to a tenant user: {body[key]}")
