"""Failure behaviour: what the app does when a provider misbehaves.

Every test here hunts a specific item from references/unexpected-behaviour.md.
A 200 that hides a provider failure is the worst outcome, not the best.
"""

import pytest

from conftest import request


def test_provider_down_does_not_fake_success(app, base_url, toxiproxy):
    """Provider down must yield an explicit failure or explicit degradation —
    never a 200 with fabricated data."""
    proxy = "app_dev_payments_1"  # TODO: your toxiproxy proxy name
    toxiproxy.down(proxy)

    r = request(app, base_url, "POST", "/api/checkout", json={"sku": "s1", "qty": 1})

    assert r.status_code != 200 or _is_explicitly_degraded(r), (
        "returned 200 while the payment provider was down — silent success"
    )
    assert r.status_code in (200, 402, 503, 504), f"unexpected {r.status_code}"


def _is_explicitly_degraded(r) -> bool:
    try:
        body = r.json()
    except ValueError:
        return False
    return bool(body.get("degraded") or body.get("stale") or body.get("payment_status") == "unavailable")


def test_provider_500_is_bounded(app, base_url, provider_stub):
    """A provider 5xx must not become an infinite retry loop."""
    provider_stub.register("POST", "/v1/charges", status=500, body={"error": "boom"})

    request(app, base_url, "POST", "/api/checkout", json={"sku": "s1", "qty": 1})

    calls = provider_stub.request_count()
    assert calls <= 5, f"retry storm: {calls} provider calls for one user action"


def test_rate_limit_backs_off(app, base_url, provider_stub):
    """429 must be handled with backoff, not an immediate retry loop, and must
    not surface as a hard user error when the request is retryable."""
    provider_stub.register(
        "POST", "/v1/charges", status=429,
        body={"error": "rate_limited"}, headers={"Retry-After": "1"},
    )

    r = request(app, base_url, "POST", "/api/checkout", json={"sku": "s1", "qty": 1})
    assert r.status_code in (200, 429, 503, 504)

    calls = provider_stub.request_count()
    assert calls <= 10, f"hammered the rate limit: {calls} calls"


def test_slow_provider_timeout_is_bounded(app, base_url, provider_stub):
    """Provider latency must be bounded by the app's timeout. An app timeout
    longer than the provider's pins threads after the provider has given up."""
    provider_stub.register("POST", "/v1/charges", status=201, delay_ms=5000,
                           body={"id": "ch_1", "status": "succeeded"})

    r = request(app, base_url, "POST", "/api/checkout", json={"sku": "s1", "qty": 1})
    assert r.elapsed.total_seconds() < 30, "request hung far past the provider timeout"


def test_failure_is_not_cached(app, base_url, provider_stub):
    """An error response must not be cached and replayed as a valid result."""
    provider_stub.register("GET", "/v1/prices", status=500)
    request(app, base_url, "GET", "/api/prices")

    provider_stub.reset()
    provider_stub.register("GET", "/v1/prices", status=200,
                           body={"prices": [{"sku": "s1", "amount": 100}]})
    r = request(app, base_url, "GET", "/api/prices")

    assert r.status_code == 200
    assert r.json().get("prices"), "served a cached failure as a successful empty result"


def test_malformed_provider_body_does_not_crash(app, base_url, provider_stub):
    """A provider returning garbage must produce a clear error, not a panic or
    a 200 with nulls."""
    provider_stub.register("GET", "/v1/prices", status=200, body={"unexpected": "shape"})
    r = request(app, base_url, "GET", "/api/prices")
    assert r.status_code in (200, 502, 503), f"unexpected {r.status_code}"
    if r.status_code == 200:
        assert "prices" in r.json(), "missing data silently dropped from the contract"
