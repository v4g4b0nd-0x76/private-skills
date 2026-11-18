# False-positive filter

Load before marking any finding `confirmed`.

For each candidate:

1. Is the input attacker-controlled, or server/config only?
2. Does middleware, gateway, or DB scoping already enforce the boundary?
3. Did the request cross a security boundary, or only return 200 on an owned object?
4. Would it reproduce on a second principal / second object?
5. Is the “leak” actually public by design?

Survive → `confirmed` with evidence.
Fail → `unverified` or `rejected` with the reason in the finding notes.

Never promote Info noise (missing headers alone, verbose banners) into ranked
findings — that is what the Info filter is for.
