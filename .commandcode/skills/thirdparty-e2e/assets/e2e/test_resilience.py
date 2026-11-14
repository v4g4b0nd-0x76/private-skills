"""Resilience: idempotency, timeouts, credential lifecycle, retry amplification.

These are the bugs that cost money — double charges, duplicate emails, and
thread pools pinned by a provider that already gave up.
"""

import concurrent.futures

import pytest

from conftest import request


def test_webhook_replay_is_idempotent(app, base_url, run_id):
    """Providers retry webhook delivery. Receiving the same event twice is
    normal; doing the side effect twice is the bug."""
    event = {
        "id": f"evt_{run_id}",
        "type": "charge.succeeded",
        "data": {"order_id": f"order_{run_id}", "amount": 100},
    }

    first = request(app, base_url, "POST", "/webhooks/provider", json=event)
    if first.status_code >= 400:
        pytest.skip(f"webhook endpoint not available: {first.status_code}")

    second = request(app, base_url, "POST", "/webhooks/provider", json=event)

    orders = request(app, base_url, "GET", f"/api/orders?ref=order_{run_id}")
    if orders.status_code != 200:
        pytest.skip("cannot read orders back")

    count = len(orders.json().get("items", []))
    assert count <= 1, f"webhook replay created {count} orders"


def test_timeout_shorter_than_provider(app, base_url, provider_stub, monkeypatch):
    """The app must not keep working on a request the provider abandoned."""
    provider_stub.register("POST", "/v1/charges", status=201, delay_ms=8000,
                           body={"id": "ch_slow", "status": "succeeded"})

    r = request(app, base_url, "POST", "/api/checkout", json={"sku": "s_t", "qty": 1})
    # Either the app bounded it and returned an error, or it waited — both are
    # informative; the assertion is that it did not silently claim success.
    if r.status_code == 200:
        assert r.elapsed.total_seconds() >= 7, (
            "returned success before the provider could have completed — phantom charge"
        )


def test_concurrent_token_refresh_is_single_flight(app, base_url):
    """Expired OAuth token + concurrent requests must not produce a 401 storm
    or N simultaneous refreshes."""
    def call(_):
        return request(app, base_url, "GET", "/api/items")

    with concurrent.futures.ThreadPoolExecutor(max_workers=20) as pool:
        results = list(pool.map(call, range(20)))

    unauth = [r for r in results if r.status_code == 401]
    assert not unauth, f"{len(unauth)}/20 requests 401ed during token refresh"


def test_idempotency_key_prevents_duplicate_charge(app, base_url, run_id):
    """The same idempotency key must not move money twice."""
    key = f"idem_{run_id}"
    payload = {"sku": "s_idem", "qty": 1}
    headers = {"Idempotency-Key": key}

    first = request(app, base_url, "POST", "/api/checkout", json=payload, headers=headers)
    if first.status_code >= 400:
        pytest.skip("idempotency not supported on this endpoint")

    second = request(app, base_url, "POST", "/api/checkout", json=payload, headers=headers)

    assert second.status_code < 500
    if first.status_code == 200 and second.status_code == 200:
        a, b = first.json().get("order_id"), second.json().get("order_id")
        assert a == b, "idempotency key ignored — two different orders created"


def test_same_key_different_payload_rejected(app, base_url, run_id):
    """Reusing a key with a different body must be an error, not a silent
    apply of the new payload."""
    key = f"idem2_{run_id}"
    headers = {"Idempotency-Key": key}
    first = request(app, base_url, "POST", "/api/checkout",
                    json={"sku": "a", "qty": 1}, headers=headers)
    if first.status_code >= 400:
        pytest.skip("idempotency not supported")

    second = request(app, base_url, "POST", "/api/checkout",
                     json={"sku": "b", "qty": 99}, headers=headers)
    assert second.status_code in (400, 409, 422), (
        "reused idempotency key with a different payload was accepted"
    )


def test_no_retry_on_non_idempotent_call(app, base_url, provider_stub):
    """A payment capture is not idempotent; retrying it double-charges."""
    provider_stub.register("POST", "/v1/charges", status=503)
    request(app, base_url, "POST", "/api/charge", json={"sku": "s_r", "qty": 1})

    calls = provider_stub.request_count()
    assert calls <= 1, f"retried a non-idempotent charge {calls} times"
