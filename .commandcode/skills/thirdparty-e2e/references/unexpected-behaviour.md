# Unexpected Behaviour: What to Hunt For

Load this when writing E2E assertions and after running load or faults. This list is the reason the skill exists — work it item by item and give each one an assertion.

The pattern in every case: the app does not crash, so nobody notices, and the data is wrong.

## 1. Silent success

The provider failed, and the app returned 200 with empty, stale, or partially-filled data.

```python
def test_provider_down_does_not_return_fake_success(app, toxiproxy):
    with toxiproxy.down("payments"):
        r = app.place_order(sku="s1", qty=1)
    assert r.status_code != 200 or r.json().get("payment_status") != "paid"
    # a 200 claiming "paid" while the charge never happened is worse than a 500
```

Look for: `except: pass`, `unwrap_or_default()`, empty lists substituted for errors, `return []` in a `rescue`.

## 2. Retry storms

Each layer retries, so a single user action becomes N×M provider calls.

```python
def test_no_retry_storm(provider_stub, app):
    with provider_stub.returning(500):
        app.place_order(sku="s1", qty=1)
    assert provider_stub.request_count() <= 3, "retry amplification"
```

Check: client retries × gateway retries × queue redeliveries. Look for retries on non-idempotent calls (a duplicated charge).

## 3. Idempotency failures

The same event processed twice: double charge, duplicate email, two refunds.

```python
def test_webhook_replay_is_idempotent(app, provider):
    payload = provider.charge_succeeded_event(id="evt_1")
    app.post("/webhooks/payments", json=payload)
    app.post("/webhooks/payments", json=payload)   # providers DO retry
    assert app.orders(sku="s1").count == 1
```

Providers retry deliveries. Receiving an event twice is normal, not an attack.

## 4. Timeout mismatch

App timeout is longer than the provider's, or the reverse.

- App timeout > provider timeout: connections and threads stay pinned long after the provider gave up.
- App timeout < provider timeout: the app abandons work the provider will still complete — leading to phantom side effects (charge succeeds after you returned an error).

Check every configured timeout against the provider's documented one and assert the failure path.

## 5. Cache poisoning

A failure or a partial response gets cached and served as valid.

```python
def test_error_is_not_cached(app, stub):
    with stub.returning(500):
        app.get("/api/prices")
    with stub.returning(200):
        r = app.get("/api/prices")
    assert r.status_code == 200 and r.json()["prices"], "cached the failure"
```

Also check negative caching of auth tokens, 404s, and rate-limit responses.

## 6. Unbounded queues and backlog

During a spike the work queues; does it ever drain?

Assert on depth after the spike window, not only during it:

```python
def test_queue_drains_after_spike(app, metrics):
    app.run_spike()
    app.wait_idle(timeout=300)
    assert metrics.queue_depth() == 0, "backlog did not drain"
```

## 7. Order dependence

Webhook and polling race each other; events arrive out of order (payment before order-created).

Test: deliver events reversed and duplicated, and assert the terminal state is still correct.

## 8. Contract drift

The provider changes a field and the app breaks or silently loses data.

- **Strict deserialization**: unknown field → hard failure. Safe but brittle.
- **Lenient deserialization**: unknown field silently dropped. Dangerous.

Test both directions: extra unknown field must not crash, missing optional field must not become `null` silently, and missing **required** field must fail loudly.

## 9. Credential lifecycle

OAuth tokens expire mid-run; refresh under concurrency races.

Test: force expiry, then fire 50 requests concurrently and assert exactly one refresh and no 401 storm.

## 10. Pagination and partial reads

Provider paginates; app reads page 1 and reports total. Test with more items than one page.

## 11. Rate-limit handling

A 429 must trigger backoff, not a retry immediately, and must not surface as a user error if the request is retryable.

```python
def test_429_backs_off(stub, app):
    stub.return_429_every_nth(2)
    app.run_batch()
    assert stub.max_requests_per_second() <= stub.documented_limit
```

## 12. Data leakage into logs and traces

Provider payloads carry PII and tokens. Assert redaction at the outgoing-client layer.

## 13. Clock and timezone assumptions

Signed webhook timestamps, token `nbf`, expiry windows. A skewed clock turns valid requests into rejections. Test near-boundary values.

## 14. Degradation correctness (not just survival)

The highest-value assertion set for a third-party app:

| Provider state | Acceptable | Unacceptable |
|---|---|---|
| down | 503 + clear error, or stale-with-flag | 200 with fabricated data |
| slow (2s) | timeout bounded, fallback used | connection exhaustion, cascading timeouts |
| 429 | backoff then success | immediate user-facing error, retry loop |
| 500 | bounded retry, then error | infinite retry, or silent empty result |
| partial field missing | degrade the specific feature | whole page fails |

## Turning this into tests

For each item above that applies, write one test that **fails when the bad behaviour occurs**. A test that only exercises the happy path, or that asserts a status code without checking the resulting state, does not cover any of this.
