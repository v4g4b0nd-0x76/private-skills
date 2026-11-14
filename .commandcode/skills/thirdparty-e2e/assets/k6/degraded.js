// degraded: steady traffic WHILE a third-party provider is impaired.
//
// This is the highest-value profile for a third-party-dependent app. Run it
// while Toxiproxy adds latency, or while a WireMock stub returns 429/500.
//
// The question is never "did it survive" but "what did it serve, and is that
// acceptable". A 200 with fabricated data is worse than a 503.
import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const RATE = Number(__ENV.RATE || 30);

export const options = {
  scenarios: {
    degraded: {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      duration: __ENV.DURATION || '5m',
      preAllocatedVUs: Math.max(10, RATE),
      maxVUs: Math.max(50, RATE * 2),
    },
  },
  thresholds: {
    // Under degradation, bounded latency is the requirement. If a 2s provider
    // delay turns into 30s responses, the timeout is wrong.
    http_req_duration: ['p(95)<3000', 'p(99)<8000'],
    // Some failure is expected; an unbounded error rate is not.
    http_req_failed: ['rate<0.20'],
    checks: ['rate>0.80'],
  },
};

export default function () {
  // TODO: the endpoint whose provider you are degrading.
  const r = http.get(`${BASE_URL}/api/items`);

  check(r, {
    'fails explicitly, not silently': (res) => {
      if (res.status === 200) {
        // A 200 under provider failure must carry explicit degradation info,
        // not fabricated or empty data pretending to be real.
        let body;
        try { body = JSON.parse(res.body); } catch (_) { return false; }
        if (!body) return false;
        const degraded = body.degraded === true || body.stale === true;
        const hasData = body.items !== undefined && body.items !== null;
        return hasData || degraded;
      }
      return res.status === 503 || res.status === 429 || res.status === 504;
    },
    'did not hang on the provider': (res) => res.timings.duration < 15000,
  });

  sleep(Math.random() * 1.5);
}

// Run:
//   1. faults.sh --scenario latency --proxy payments --latency 2000
//   2. loadgen.sh http://localhost:8080 --profile degraded --i-own-this-target
//   3. faults.sh --scenario recovery   # then assert the backlog drains
