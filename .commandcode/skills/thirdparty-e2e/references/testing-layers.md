# Testing Layers: Real vs Virtualized

Load this before choosing how to exercise a dependency, and when a suite is flaky.

## The rule

**Mock what you do not own. Integrate for real with what you do.**

Over-mocking your own services produces green CI and red production. Under-mocking third parties produces a flaky suite that everyone learns to ignore.

## Choosing a layer

| Situation | Layer | Why |
|---|---|---|
| Your own DB/queue/cache | real container | catches dialect, migration, constraint bugs |
| Provider with a sandbox | real sandbox, nightly | only real contract fidelity you can get |
| Provider without sandbox | WireMock with recorded fixtures | deterministic, fast, no quota |
| Provider is slow or flaky in reality | Toxiproxy in front of the stub or sandbox | reproducibility of the bad day |

Half-open option worth knowing: record real sandbox responses once, replay them as fixtures. Contract fidelity is real; behaviour stays deterministic.

## Real dependencies (Testcontainers pattern)

```python
# pytest + testcontainers
@pytest.fixture(scope="session")
def postgres():
    from testcontainers.postgres import PostgresContainer
    with PostgresContainer("postgres:16-alpine") as pg:
        yield pg.get_connection_url()
```

Rules:
- One container per service, per test session; not one per test.
- Use a reaper/cleanup hook so a killed run does not leak containers.
- Never point tests at a shared staging database. Isolation is the point.
- Run migrations as part of the fixture so schema drift is caught.

## Virtualization (WireMock)

Stub the provider, not your own service:

```bash
curl -X POST http://localhost:8080/__admin/mappings -d '{
  "request": {"method": "POST", "urlPath": "/v1/charges"},
  "response": {
    "status": 201,
    "headers": {"Content-Type": "application/json"},
    "jsonBody": {"id": "ch_test_1", "status": "succeeded"},
    "fixedDelayMilliseconds": 1200
  }
}'
```

Always stub the hostile cases next to the happy path:

| Stub | Simulates |
|---|---|
| `201` normal | baseline |
| `500` | provider bug |
| `429` with `Retry-After` | rate limit |
| `503` | planned maintenance |
| slow (`fixedDelayMilliseconds`) | degraded latency |
| connection reset / no response | network failure |
| malformed body | contract drift |
| `200` with missing field | schema regression |
| `200` with extra field | forward compatibility |

A stub suite with only happy paths tests your JSON parser.

## Load and fault tooling

| Need | Tool | Note |
|---|---|---|
| Traffic shape | k6 | thresholds are what gate CI |
| Inject latency/timeout/reset | Toxiproxy | deterministic, per-connection |
| Container-level chaos | Pumba / Chaos Mesh | pod kill, CPU, DNS |
| Real provider chaos | sandbox + feature flags | preferred when the provider supports it |

## Anti-patterns

- **Shared staging** — one broken deploy poisons everyone's run.
- **Fixed sleeps** — replace with deterministic polling on a condition.
- **Assertions on "element exists"** — assert on the acceptance criterion instead.
- **Retry masking** — a passing test that retried 5 times hides a real defect; assert attempt counts.
- **No cleanup** — sandbox state accumulates and later runs see other runs' data.
- **Ice-cream cone** — too many E2E, too few contract/integration tests. Invert the ratio.

## Cost discipline

E2E against real providers is the most expensive test you own: money, quota, latency, and flake. Keep the count small and targeted (one per revenue-critical journey), run nightly rather than per-PR, and move anything whose value is logic verification down to a cheaper layer.
