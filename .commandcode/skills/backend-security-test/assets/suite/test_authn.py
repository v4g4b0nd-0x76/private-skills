"""Authentication tests: token and session validation.

Each test targets one validation gap. Skip a test only if the mechanism
does not exist in this backend.
"""

import base64
import json

import pytest

from conftest import BASE_URL, TIMEOUT, assert_cross_user_denied


def _b64(obj) -> str:
    return base64.urlsafe_b64encode(json.dumps(obj).encode()).rstrip(b"=").decode()


def _unsigned_token(**claims) -> str:
    return f"{_b64({'alg': 'none', 'typ': 'JWT'})}.{_b64(claims)}."


PROTECTED = "/api/me"  # TODO: a route that requires authentication


def test_protected_route_requires_credentials():
    import requests

    r = requests.get(f"{BASE_URL}{PROTECTED}", timeout=TIMEOUT)
    assert r.status_code in (401, 403), (
        f"unauthenticated access returned {r.status_code}"
    )


def test_malformed_token_rejected(alice):
    for bad in ("not-a-jwt", "a.b", "..", "Bearer", _unsigned_token(sub="x")):
        r = alice.get(PROTECTED, headers={"Authorization": f"Bearer {bad}"})
        assert r.status_code in (401, 403), f"malformed token accepted: {bad!r}"


def test_tampered_signature_rejected(alice):
    if not alice.token:
        pytest.skip("no token to tamper with")
    tampered = alice.token[:-4] + "AAAA"
    r = alice.get(PROTECTED, headers={"Authorization": f"Bearer {tampered}"})
    assert r.status_code in (401, 403), "signature not verified"


def test_alg_none_rejected(alice):
    forged = _unsigned_token(sub=alice.user or "x", role="admin", exp=9999999999)
    r = alice.get(PROTECTED, headers={"Authorization": f"Bearer {forged}"})
    assert r.status_code in (401, 403), "alg:none token accepted"


def test_expired_token_rejected():
    import requests

    expired = _unsigned_token(sub="x", exp=1)
    r = requests.get(
        f"{BASE_URL}{PROTECTED}",
        headers={"Authorization": f"Bearer {expired}"},
        timeout=TIMEOUT,
    )
    assert r.status_code in (401, 403), "expired token accepted"


def test_logout_invalidates_token(alice):
    if not alice.token:
        pytest.skip("no token")
    token = alice.token
    alice.post("/api/auth/logout")
    r = alice.get(PROTECTED, headers={"Authorization": f"Bearer {token}"})
    assert r.status_code in (401, 403), "token still valid after logout"


def test_password_reset_token_not_in_response(alice):
    r = alice.post("/api/auth/forgot-password", json={"email": alice.user})
    if r.status_code >= 400:
        pytest.skip("endpoint not present or not usable")
    body = json.dumps(r.json())
    assert "token" not in body.lower(), "reset token returned to the client"
