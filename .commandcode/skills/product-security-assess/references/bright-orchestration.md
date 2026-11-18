# Bright orchestration

Load before any live scan step.

## Sequence

1. **Project + Repeater** — Bright `setup-repeater` for private or live company reachability. Repeater proxies cloud engine → target without opening inbound firewall holes.
2. **Entrypoints** — register HTTP APIs and app URLs from `assets.json` / OpenAPI / code map. Exclude irreversible actions unless destructive is armed.
3. **Auth (gray)** — Bright `setup-auth` with a non-mutating protected resource (e.g. profile/me). Store `authObjectId` in `scans/gray.json` only — never paste passwords into the workspace.
4. **Tests** — call Bright `listTests`; drop deprecated/disabled; select by buckets matching the surface (`api`, `server_side`, `client_side`, `business_logic`). Do **not** hardcode a remembered tag list.
5. **Destructive** — omit destructive/special-case tests unless `.product-security/<run>/DESTRUCTIVE_ARMED` exists.
6. **Run + monitor** — `runScan` per group; wait for completion; pull findings into JSONL.

## Asset rules

- Only hosts on the ROE allowlist.
- No speculative subdomain enumeration that expands past written scope.
- Client JS / source maps: extract API paths for entrypoint registration only.

## Failure modes

| Symptom | Action |
|---------|--------|
| Repeater disconnected | Stop; fix Repeater; do not invent findings |
| Auth failure loop | Fix auth object; do not continue gray as “mostly done” |
| Scan timeout | Record gap in report; do not treat as pass |
