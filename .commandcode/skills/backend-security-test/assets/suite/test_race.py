"""Race conditions / TOCTOU.

Sequential calls prove nothing. These tests fire synchronized bursts and
assert on the SIDE EFFECT, not on response codes.

Races are intermittent: each test repeats several rounds before trusting a pass.
"""

import concurrent.futures

import pytest

ROUNDS = 10
BURST = 20


def _burst(fn, n=BURST):
    with concurrent.futures.ThreadPoolExecutor(max_workers=n) as pool:
        futures = [pool.submit(fn, i) for i in range(n)]
        return [f.result() for f in futures]


def test_duplicate_checkout_single_effect(alice, bob):
    """A coupon/credit must be redeemed once under concurrency."""
    pytest.skip("fill in a resource with a one-shot side effect (coupon, credits)")

    # coupon = create_coupon(alice)
    # for _ in range(ROUNDS):
    #     results = _burst(lambda i: alice.post("/api/checkout", json={"coupon": coupon}))
    #     successes = [r for r in results if r.status_code < 300]
    #     assert len(successes) <= 1, f"coupon redeemed {len(successes)} times"


def test_parallel_state_change_is_consistent(alice):
    """Approve/reject concurrently: the final state must be exactly one of them."""
    RESOURCE = "tasks"  # TODO
    obj = alice.own(RESOURCE)

    for _ in range(ROUNDS):
        def act(i):
            verb = "approve" if i % 2 == 0 else "reject"
            return alice.post(f"/api/{RESOURCE}/{obj}/{verb}")

        results = _burst(act)
        codes = [r.status_code for r in results]
        ok = [c for c in codes if 200 <= c < 300]
        assert len(ok) <= 1, f"conflicting transitions both accepted: {codes}"

        after = alice.get(f"/api/{RESOURCE}/{obj}")
        if after.status_code == 200:
            assert after.json().get("status") in ("approved", "rejected", "active")


def test_idempotent_transfer_not_double_applied(alice):
    """Replay with the same idempotency key must not move money twice."""
    pytest.skip("fill in a transfer/withdrawal endpoint")

    # key = uuid.uuid4().hex
    # r1 = alice.post("/api/transfers", json={"amount": 100}, headers={"Idempotency-Key": key})
    # r2 = alice.post("/api/transfers", json={"amount": 100}, headers={"Idempotency-Key": key})
    # assert balance_delta(alice) == 100, "idempotency key not enforced"


def test_concurrent_limit_not_exceeded(alice):
    """A quota must hold under a parallel burst, not just when called serially."""
    pytest.skip("fill in a limited resource (invites, API keys, uploads)")

    # results = _burst(lambda i: alice.post("/api/invites", json={"email": f"x{i}@t.test"}))
    # created = len([r for r in results if r.status_code < 300])
    # assert created <= QUOTA, f"quota exceeded under concurrency: {created}"


def test_signup_race_single_account(unique_email):
    import requests
    from conftest import BASE_URL, TIMEOUT

    payload = {"email": unique_email, "password": "Aa1!aaaaaaa"}

    def register(i):
        return requests.post(f"{BASE_URL}/api/auth/register", json=payload, timeout=TIMEOUT)

    results = _burst(register)
    created = [r for r in results if 200 <= r.status_code < 300]
    assert len(created) <= 1, f"duplicate accounts created: {len(created)}"
