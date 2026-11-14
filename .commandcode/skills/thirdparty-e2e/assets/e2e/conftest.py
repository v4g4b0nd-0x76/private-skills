"""Fixtures for third-party E2E tests.

Two things are mandatory:
  1. APP_URL must be local (or explicitly allowed staging).
  2. Every test must assert on BEHAVIOUR, not just a status code.

Configure:
    APP_URL        the app under test, e.g. http://localhost:3000
    WIREMOCK_URL   http://localhost:8080
    TOXIPROXY_URL  http://localhost:8474
"""

import ipaddress
import os
import uuid
from urllib.parse import urlparse

import pytest
import requests

APP_URL = os.environ.get("APP_URL", "http://localhost:3000")
WIREMOCK = os.environ.get("WIREMOCK_URL", "http://localhost:8080")
TOXIPROXY = os.environ.get("TOXIPROXY_URL", "http://localhost:8474")
TIMEOUT = float(os.environ.get("HTTP_TIMEOUT", "15"))
ALLOW_HOST = os.environ.get("ALLOW_STAGING_HOST", "")


def _assert_allowed(url: str) -> None:
    host = urlparse(url).hostname or ""
    local = (host in ("localhost", "::1") or host.endswith(".localhost")
             or host.endswith(".test"))
    if not local:
        try:
            local = ipaddress.ip_address(host).is_loopback
        except ValueError:
            local = False
    if not local and host != ALLOW_HOST:
        raise RuntimeError(
            f"REFUSED: host '{host}' is not local. Set ALLOW_STAGING_HOST={host} "
            "only for a staging environment you own."
        )


_assert_allowed(APP_URL)


@pytest.fixture(scope="session")
def app() -> requests.Session:
    s = requests.Session()
    s.headers["User-Agent"] = "thirdparty-e2e"
    return s


@pytest.fixture(scope="session")
def base_url() -> str:
    return APP_URL.rstrip("/")


@pytest.fixture
def run_id() -> str:
    """Unique per test: sandbox state accumulates across runs."""
    return uuid.uuid4().hex[:10]


def request(session, base_url, method, path, **kw):
    kw.setdefault("timeout", TIMEOUT)
    return session.request(method, f"{base_url}{path}", **kw)


def wiremock_available() -> bool:
    try:
        return requests.get(f"{WIREMOCK}/__admin/health", timeout=2).status_code == 200
    except requests.RequestException:
        return False


def toxiproxy_available() -> bool:
    try:
        return requests.get(f"{TOXIPROXY}/version", timeout=2).status_code == 200
    except requests.RequestException:
        return False


@pytest.fixture
def provider_stub():
    """WireMock control: register stubs and count requests.

    Raises rather than silently passing when the stub infra is missing,
    because an untested failure path is the bug this suite exists to find.
    """
    if not wiremock_available():
        raise RuntimeError(
            f"WireMock not reachable at {WIREMOCK}. "
            "Run: docker compose -f .thirdparty/docker-compose.yml up -d wiremock"
        )

    class Stub:
        def __init__(self):
            self.reset()
            self._count = 0

        def reset(self):
            requests.post(f"{WIREMOCK}/__admin/reset", timeout=5)

        def register(self, method, path, status=200, body=None, delay_ms=0, headers=None):
            resp = {"status": status, "jsonBody": body or {},
                    "headers": {"Content-Type": "application/json", **(headers or {})}}
            if delay_ms:
                resp["fixedDelayMilliseconds"] = delay_ms
            requests.post(f"{WIREMOCK}/__admin/mappings", timeout=5, json={
                "request": {"method": method, "urlPath": path},
                "response": resp,
            })
            return self

        def request_count(self) -> int:
            r = requests.get(f"{WIREMOCK}/__admin/requests", timeout=5)
            return len(r.json().get("requests", [])) if r.ok else 0

    return Stub()


@pytest.fixture
def toxiproxy():
    """Toxiproxy control for deterministic network faults."""
    if not toxiproxy_available():
        raise RuntimeError(
            f"Toxiproxy not reachable at {TOXIPROXY}. "
            "Run: docker compose -f .thirdparty/docker-compose.yml up -d toxiproxy"
        )

    class Proxy:
        def _reset(self):
            requests.post(f"{TOXIPROXY}/reset", timeout=5)

        def down(self, name):
            requests.post(f"{TOXIPROXY}/proxies/{name}", timeout=5,
                          json={"enabled": False})

        def up(self, name):
            requests.post(f"{TOXIPROXY}/proxies/{name}", timeout=5,
                          json={"enabled": True})

        def add(self, name, toxic, **attrs):
            requests.post(f"{TOXIPROXY}/proxies/{name}/toxics", timeout=5,
                          json={"type": toxic, "attributes": attrs})

        def cleanup(self):
            self._reset()

    p = Proxy()
    yield p
    p.cleanup()
