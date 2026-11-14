"""Degradation correctness under partial outage, and recovery afterwards.

The question is never "did the process survive" but "what did it serve, and is
that acceptable". Then: does it recover, or does the backlog stay stuck?
"""

import time

import pytest

from conftest import request


def test_degraded_page_still_renders_core_content(app, base_url, toxiproxy):
    """A non-critical provider failing must not take down the whole page."""
    proxy = "app_dev_payments_1"  # TODO
    toxiproxy.down(proxy)

    r = request(app, base_url, "GET", "/api/catalog")
    assert r.status_code in (200, 206, 503), f"unexpected {r.status_code}"
    if r.status_code == 200:
        body = r.json()
        assert body.get("items"), "degraded response returned no core content"
        # If the recommendation provider is down, that section may be absent —
        # but it must be flagged, not silently empty.
        if "recommendations" in body and not body["recommendations"]:
            assert body.get("degraded") is True, "empty section with no degradation flag"


def test_critical_provider_down_fails_explicitly(app, base_url, toxiproxy):
    """A critical provider must produce an explicit error, never fabricated data."""
    proxy = "app_dev_payments_1"  # TODO
    toxiproxy.down(proxy)

    r = request(app, base_url, "POST", "/api/checkout", json={"sku": "s1", "qty": 1})
    assert r.status_code != 200 or r.json().get("payment_status") != "paid", (
        "checkout reported paid while payment provider was down"
    )


def test_backpressure_is_bounded(app, base_url, provider_stub):
    """A slow provider must not cause unbounded in-memory buffering."""
    provider_stub.register("GET", "/v1/prices", status=200, delay_ms=3000,
                           body={"prices": [{"sku": "s1", "amount": 100}]})

    # Fire more requests than the app can serve; none may hang indefinitely.
    import concurrent.futures
    def one(_):
        return request(app, base_url, "GET", "/api/prices")

    with concurrent.futures.ThreadPoolExecutor(max_workers=25) as pool:
        results = list(pool.map(one, range(25)))

    hung = [r for r in results if r.elapsed.total_seconds() > 30]
    assert not hung, f"{len(hung)} requests hung past 30s under provider stall"


def test_recovers_after_outage(app, base_url, toxiproxy):
    """After the fault is removed, the app must return to normal — not stay stuck
    on a circuit breaker or serve stale data forever."""
    proxy = "app_dev_payments_1"  # TODO

    toxiproxy.down(proxy)
    request(app, base_url, "GET", "/api/catalog")
    toxiproxy.cleanup()   # reset: enabled + no toxics

    deadline = time.time() + 60
    last = None
    while time.time() < deadline:
        last = request(app, base_url, "GET", "/api/catalog")
        if last.status_code == 200 and not last.json().get("degraded"):
            break
        time.sleep(2)

    assert last is not None and last.status_code == 200, "did not recover after outage"
    assert not last.json().get("degraded"), "recovery flag stuck after provider returned"


def test_backlog_drains_after_spike(app, base_url):
    """Queue depth must return to baseline after load stops. A backlog that never
    drains is a finding even if latency looks normal."""
    import concurrent.futures
    def one(_):
        return request(app, base_url, "POST", "/api/enqueue", json={"job": "x"})

    with concurrent.futures.ThreadPoolExecutor(max_workers=50) as pool:
        list(pool.map(one, range(200)))

    # TODO: replace with the app's real queue-depth metric endpoint.
    deadline = time.time() + 120
    depth = None
    while time.time() < deadline:
        m = request(app, base_url, "GET", "/metrics/queue-depth")
        if m.status_code == 200:
            depth = m.json().get("depth")
            if depth == 0:
                break
        time.sleep(3)

    if depth is None:
        pytest.skip("no queue depth metric exposed — add one, backlog is otherwise invisible")
    assert depth == 0, f"backlog did not drain: depth={depth}"
