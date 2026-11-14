# Business Logic Abuse and Race Conditions

Load this when testing workflow validity, state machines, money/inventory operations, or anything with a counter or limit.

## The mindset

Logic bugs are not pattern-matchable. Ask: **what does the server assume, and who can violate it?**

For each endpoint list the invariants it must uphold ("a coupon is used once", "only the owner approves", "stock never goes negative", "a refund never exceeds the charge"), then try to break each one. A test that passes is not proof; the invariant is what you attack.

## Categories worth testing

### 1. State machine violations

Skipped steps, repeated steps, out-of-order steps:

```python
# Valid order: create -> pay -> ship -> deliver
# Attack: deliver before pay
assert alice.post(f"/orders/{order}/deliver").status in (400, 409, 403)
# Attack: repeat a one-shot transition
assert alice.post(f"/orders/{order}/pay").status in (409, 400)   # second time
# Attack: transition a cancelled order
```

Every transition should validate the *current* state, not just the requested one.

### 2. Value manipulation

- Negative quantities (converts a charge into a credit).
- Zero price, extreme quantity, integer overflow on total.
- Currency mismatch: pay in a cheaper currency than the one priced.
- Client-supplied totals: send your own `total`, `discount`, `tax` and see if it is trusted.
- Rounding: repeated tiny transactions to accumulate rounding gain.
- Coupon stacking, applying an expired coupon, applying a coupon from another tenant.

### 3. Resource and limit bypass

- Negative or fractional amounts on withdrawals/refunds.
- Exceeding a quota by using a different endpoint or an aggregated path.
- Trial/subscription extension by manipulating dates in the request.
- Bypassing a paywall by using the internal/alternate route or a preview endpoint.
- Limit on "one per user" enforced only in the UI or only per session.

### 4. Workflow authorization (distinct from BOLA)

Even with correct object ownership, *which* actor may perform *which* transition may be unenforced: a customer approving their own refund, a reviewer approving their own submission, a transfer requiring two parties where one can do both.

### 5. Race conditions (TOCTOU)

The single most valuable class for business logic and the one most often missed. The bug is an assumption that a check-then-act pair is atomic.

Standard targets: double-spend, duplicate redemption, over-booking, exceeding a limit, creating two accounts with the same email, concurrent approve + reject.

Method — synchronization matters more than repetition:

```python
import concurrent.futures

def test_coupon_single_use(client, alice, coupon):
    with concurrent.futures.ThreadPoolExecutor(max_workers=20) as pool:
        futures = [pool.submit(alice.post, "/checkout", json={"coupon": coupon}) for _ in range(20)]
        results = [f.result() for f in futures]
    successes = [r for r in results if r.status == 200]
    assert len(successes) == 1, f"coupon redeemed {len(successes)} times"
```

Rules for a valid race test:
- Fire all requests **in parallel** and aligned to a common barrier; sequential calls prove nothing.
- Use a fresh resource per run, or reset state.
- Assert on the **side effect** (balance, row count, order count), not on response codes alone.
- Repeat 10–50 times; races are intermittent. A single green run is not evidence of absence.
- Same-endpoint, same-account, and cross-endpoint duplicates are different bugs — test both.
- HTTP/2/QUIC changes scheduling but does not remove TOCTOU; do not assume a new protocol fixed it.

Relevant weaknesses: CWE-362 (race condition), CWE-367 (TOCTOU), CWE-841 (improper workflow enforcement).

### 6. Idempotency and replay

- Replay a captured request (withdrawal, transfer, invite) and check for a second effect.
- Remove or alter the idempotency key, or reuse one across different payloads.
- Send the same idempotency key concurrently.

### 7. Multi-step and cross-tenant confusion

- Start a flow as tenant A, finish it as tenant B.
- Use an invite/accept token from a different context.
- Interleave two flows and check that state does not cross.

## Judging the result

A logic finding needs:
1. The broken invariant, stated in one sentence.
2. A reproduction that shows the wrong end state (not just a response code).
3. Evidence the state was actually persisted (re-read it with a fresh GET).
4. The impact in business terms: money, inventory, access, reputation.

If the end state is correct, there is no finding regardless of what the response said.
