# Load Profiles That Predict Production

Load this when generating or running load profiles, or choosing thresholds.

## Why shape matters more than volume

A single ramp-to-crash tells you almost nothing. Real traffic has a shape: a baseline, diurnal peaks, a marketing spike, a cold start after deploy. Each shape exposes a different bottleneck, and several failure modes only appear in one of them.

## Profiles

### `smoke` — 1 VU, 30s

Not a load test. Proves wiring, auth, and that the target is the target. Run first, always.

### `steady` — constant arrival rate, 5m

```javascript
export const options = {
  scenarios: {
    steady: { executor: 'constant-arrival-rate', rate: 100, timeUnit: '1s',
              duration: '5m', preAllocatedVUs: 50, maxVUs: 200 },
  },
  thresholds: { http_req_duration: ['p(95)<500', 'p(99)<1500'], http_req_failed: ['rate<0.01'] },
};
```

Baseline latency and error rate. If steady fails, nothing above it matters.

### `spike` — ramp 10x for 60s

```javascript
scenarios: {
  spike: { executor: 'ramping-arrival-rate', startRate: 50, timeUnit: '1s',
           preAllocatedVUs: 200, maxVUs: 1000,
           stages: [{ target: 500, duration: '60s' }, { target: 50, duration: '120s' }] },
}
```

Reveals autoscaling lag, queue growth, 429 storms, and whether the system **recovers** after the spike. Failing to drain the backlog is a finding even if latency returns to normal.

### `soak` — steady for 1h+

Finds what short runs cannot: memory leaks, file descriptor and connection exhaustion, fd/time-drift bugs, cache growth, token refresh bugs. Watch RSS and connection counts over time, not just latency.

### `cold-start` — 0 → peak in 10s

Post-deploy behaviour. Connection pools empty, caches cold, JIT not warmed. A system that is fine under steady load can time out entirely here.

### `degraded` — steady while a provider is slowed

The most valuable profile for a third-party-dependent app. Run steady traffic **while** Toxiproxy adds 2s latency or a stub returns 429. This is where fallbacks either work or silently corrupt results.

## Thresholds

A profile without thresholds is a graph, not a test.

```javascript
thresholds: {
  'http_req_duration{expected_response:true}': ['p(95)<500', 'p(99)<1500'],
  http_req_failed: ['rate<0.01'],
  checks: ['rate>0.99'],
  // per-provider budget: tag requests by dependency
  'http_req_duration{provider:payments}': ['p(95)<800'],
  'http_req_failed{provider:payments}': ['rate<0.005'],
}
```

Rules:
- Latency thresholds are **percentiles**, never averages; a good average can hide a terrible tail.
- Let failing requests have their own budget; don't average them into duration.
- Gate on error rate and check rate always.
- Set thresholds from an observed baseline, then tighten. Inventing `p95<100ms` for an unmeasured system produces a permanently red build that people ignore.

## Model real traffic

Synthetic uniform load measures the wrong thing. Sample real requests (anonymized) and replay their mix:

```javascript
import { SharedArray } from 'k6/data';
const reqs = new SharedArray('reqs', () => JSON.parse(open('./real-traffic.json')));
export default function () {
  const r = reqs[Math.floor(Math.random() * reqs.length)];
  http.request(r.method, r.url, r.body, { headers: r.headers });
}
```

## Capacity ceiling

Increase load until the SLO breaches; record where it breached. That number, not a vibe, is what justifies scaling decisions.

```
RPS  1k  p99  100ms  ok
RPS  5k  p99  200ms  ok
RPS 10k  p99  500ms  ok
RPS 15k  p99 1500ms  breach
RPS 20k  errors climb
```

## Mistakes that produce meaningless numbers

1. **No think time** — back-to-back requests are bots. Add randomized sleep.
2. **Same input every time** — 100% cache hit; the numbers are fiction.
3. **Cold target in metrics** — discard the first 60s, or measure cold-start on purpose.
4. **Load generator saturated** — verify its CPU has headroom; its stats lie otherwise.
5. **No error analysis** — throughput looks great at 5% error rate. Always inspect what failed.
6. **No cleanup** — leftover sandbox state skews later runs.
7. **Debug builds** — measure release builds only.

## Never

- Load-test production without explicit approval and comms; it costs real money and pages people.
- Run destructive scenarios with live credentials.
- Compare numbers across different machines without noting it.
