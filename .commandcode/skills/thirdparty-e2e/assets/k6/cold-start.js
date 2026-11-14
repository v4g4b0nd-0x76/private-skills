// cold-start: 0 -> peak in 10s. Post-deploy behaviour.
// A system fine under steady load can time out entirely here: empty pools,
// cold caches, no JIT warmup.
import http from 'k6/http';
import { check } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const PEAK = Number(__ENV.RATE || 100);

export const options = {
  scenarios: {
    cold_start: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { target: PEAK, duration: '10s' }, // the entire ramp
        { target: PEAK, duration: '20s' }, // hold at peak
      ],
      gracefulRampDown: '0s',            // no drain: this is a cold deploy
    },
  },
  thresholds: {
    // Expect worse numbers than steady; assert they are bounded, not equal.
    http_req_duration: ['p(95)<3000', 'p(99)<8000'],
    http_req_failed: ['rate<0.05'],
    checks: ['rate>0.95'],
  },
};

export default function () {
  // TODO: the first request a real user makes after a deploy.
  const r = http.get(`${BASE_URL}/api/items`);
  check(r, {
    'no cascade of timeouts': (res) => res.status < 500,
    'did not hang': (res) => res.timings.duration < 10000,
  });
}

// Failure modes this profile exposes that steady load will not:
//   - connection pool exhausted at start (all VUs connect simultaneously)
//   - first-request schema/migration work blocking the listener
//   - autoscaler starting from zero replicas
//   - DNS/TLS handshake cost paid by every new connection at once
