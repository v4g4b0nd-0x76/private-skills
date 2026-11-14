"""Fixtures for adversarial backend testing.

Two principals are mandatory: single-account testing cannot prove that a
cross-user authorization boundary exists.

Configure with environment variables:
    BASE_URL      local target, e.g. http://localhost:8080
    ALICE_USER / ALICE_PASS   primary principal
    BOB_USER   / BOB_PASS     second principal, different owner
    ADMIN_USER / ADMIN_PASS   optional, for vertical escalation tests

Never point BASE_URL at a system you do not own.
"""

import ipaddress
import os
import uuid
from urllib.parse import urlparse

import pytest
import requests

BASE_URL = os.environ.get("BASE_URL", "http://localhost:8080")
TIMEOUT = float(os.environ.get("HTTP_TIMEOUT", "10"))


def _assert_local(url: str) -> None:
    host = urlparse(url).hostname or ""
    allowed = (host == "localhost" or host.endswith(".localhost")
               or host.endswith(".test") or host == "::1")
    if not allowed:
        try:
            allowed = ipaddress.ip_address(host).is_loopback
        except ValueError:
            allowed = False
    if not allowed:
        raise RuntimeError(
            f"REFUSED: BASE_URL host '{host}' is not local. "
            "This suite only tests systems you run yourself."
        )


_assert_local(BASE_URL)


class Principal:
    """One authenticated actor with its own identifiable resources."""

    def __init__(self, name: str, user_env: str, pass_env: str):
        self.name = name
        self.user = os.environ.get(user_env)
        self.password = os.environ.get(pass_env)
        self.session = requests.Session()
        self.token: str | None = None
        self._owned: dict[str, str] = {}

    def login(self) -> "Principal":
        if not self.user or not self.password:
            pytest.skip(f"credentials for {self.name} not configured")
        r = self.session.post(
            f"{BASE_URL}/api/auth/login",
            json={"email": self.user, "password": self.password},
            timeout=TIMEOUT,
        )
        if r.status_code >= 400:
            pytest.skip(f"login failed for {self.name}: HTTP {r.status_code}")
        try:
            self.token = r.json().get("access_token") or r.json().get("token")
        except ValueError:
            self.token = None
        if self.token:
            self.session.headers["Authorization"] = f"Bearer {self.token}"
        return self

    def request(self, method: str, path: str, **kwargs):
        kwargs.setdefault("timeout", TIMEOUT)
        return self.session.request(method, f"{BASE_URL}{path}", **kwargs)

    def get(self, path, **kw):
        return self.request("GET", path, **kw)

    def post(self, path, **kw):
        return self.request("POST", path, **kw)

    def patch(self, path, **kw):
        return self.request("PATCH", path, **kw)

    def delete(self, path, **kw):
        return self.request("DELETE", path, **kw)

    def own(self, resource: str) -> str:
        """Return an object id owned by this principal.

        TODO: create or look up a real resource for this principal, e.g.:
            r = self.post("/api/projects", json={"name": f"p-{uuid.uuid4().hex[:8]}"})
            return r.json()["id"]
        Raise while unfilled so a security test never silently passes.
        """
        if resource in self._owned:
            return self._owned[resource]
        raise NotImplementedError(
            f"Principal.own('{resource}') is not implemented. "
            "Fill it from your fixtures before trusting any authz result."
        )


@pytest.fixture(scope="session")
def base_url() -> str:
    return BASE_URL


@pytest.fixture(scope="session")
def alice() -> Principal:
    return Principal("alice", "ALICE_USER", "ALICE_PASS").login()


@pytest.fixture(scope="session")
def bob() -> Principal:
    return Principal("bob", "BOB_USER", "BOB_PASS").login()


@pytest.fixture(scope="session")
def admin():
    p = Principal("admin", "ADMIN_USER", "ADMIN_PASS")
    if not (p.user and p.password):
        pytest.skip("admin credentials not configured")
    return p.login()


@pytest.fixture
def unique_email() -> str:
    return f"probe-{uuid.uuid4().hex[:12]}@example.test"


def assert_cross_user_denied(response, detail: str) -> None:
    """A cross-user access must fail closed.

    403 or 404 are both acceptable (404 avoids existence disclosure).
    200 is a finding. Anything else is inconclusive, not a pass.
    """
    if response.status_code == 200:
        pytest.fail(f"BOLA/IDOR: {detail} returned 200")
    assert response.status_code in (401, 403, 404, 410), (
        f"inconclusive for {detail}: HTTP {response.status_code} "
        "(expected 401/403/404)"
    )
