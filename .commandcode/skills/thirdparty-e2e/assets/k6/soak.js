// soak: steady traffic for an hour or more.
// Finds what short runs cannot: leaks, connection and fd exhaustion,
// cache growth, token refresh bugs. Watch RSS and connection counts,
// not just latency.
import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const RATE = Number(__ENV.RATE || 20);

export const options = {
  scenarios: {
    soak: {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      duration: __ENV.DURATION || '1h',
      preAllocatedVUs: Math.max(10, RATE),
      maxVUs: Math.max(50, RATE * 2),
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<800', 'p(99)<2000'],
    http_req_failed: ['rate<0.02'],
    // Trend metrics make drift visible over the run instead of at the end.
    'http_req_duration{scenario:soak}': ['p(95)<800'],
  },
};

export default function () {
  // TODO: mix several endpoints; a single hot endpoint will not find leaks
  // caused by the paths you never touch.
  const r = http.get(`${BASE_URL}/api/items`);
  check(r, { 'ok': (res) => res.status === 200 });
  sleep(1 + Math.random() * 2);
}

// What to watch during a soak, alongside these thresholds:
//   - process RSS over time (monotonic rise = leak)
//   - DB connection pool utilisation
//   - file descriptors
//   - queue depth (should oscillate, not climb)
//   - p99 after hour 1 vs hour 0 (drift)
