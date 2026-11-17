---
devflow: bench-env
status: draft
upstream: .devflow/plan.md
approval: not-required
updated: YYYY-MM-DD
---

# Bench environment: <module-or-task>

## Summary

- Profile active: `baseline-zero` | `prod-like` | `fault`
- Compose project: `<name>`
- Evidence: `check-bench-env.sh` exit code / log path

## Owned dependencies (real)

| Service | Image/tag | Port | Health URL | Notes |
| --- | --- | --- | --- | --- |
| | | | | |

## Third-party simulations

| Provider | Layer (WireMock/sandbox/record) | Listen via | Prod-like latency source | Fixture path |
| --- | --- | --- | --- | --- |
| | | Toxiproxy `:…` → WireMock | SLA / RUM p50=… | `.bench-env/fixtures/…` |

## Mock / fixture data

- Sources: <recorded capture | synthetic generator command>
- Paths: `.bench-env/fixtures/…`
- Uniqueness / cleanup: <how>

## Latency profiles

| Profile | What it sets | When to use |
| --- | --- | --- |
| baseline-zero | no added delay | dual-gate primary |
| prod-like | documented delays | realism / budget share |
| fault | bounded errors | resilience only |

## Commands

```bash
# bring up
docker compose -p <project> -f .bench-env/docker-compose.yml up -d --wait

# validate
bash $SKILL_DIR/scripts/check-bench-env.sh <project-root>

# tear down
docker compose -p <project> -f .bench-env/docker-compose.yml down -v
```

## Inventory evidence

- thirdparty-e2e inventory (if run): `.thirdparty/requirements.md` or script stdout path
- Deviations from plan Bench environment: <none | list>

## Readiness

- [ ] Owned services healthy
- [ ] Third-party stubs loaded (happy + at least one hostile)
- [ ] `check-bench-env.sh` exits 0
- [ ] App config points at proxy/stub ports (not production)
