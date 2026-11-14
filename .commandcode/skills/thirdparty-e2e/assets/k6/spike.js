// spike: ramp to 10x then return. Reveals autoscaling lag, queue growth,
// 429 storms — and whether the system RECOVERS afterwards.
import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const BASE_RATE = Number(__ENV.RATE || 50);
const PEAK_RATE = BASE_RATE * 10;

export const options = {
  scenarios: {
    spike: {
      executor: 'ramping-arrival-rate',
      startRate: BASE_RATE,
      timeUnit: '1s',
      preAllocatedVUs: Math.max(50, BASE_RATE * 4),
      maxVUs: Math.max(200, PEAK_RATE * 2),
      stages: [
        { target: BASE_RATE, duration: '30s' },  // baseline
        { target: PEAK_RATE, duration: '60s' },  // spike
        { target: BASE_RATE, duration: '120s' }, // does it recover?
      ],
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<1500', 'p(99)<5000'],
    // During a spike the error budget is looser, but never zero-tolerance-free.
    http_req_failed: ['rate<0.05'],
    checks: ['rate>0.95'],
  },
};

export default function () {
  // TODO: point at the path the marketing email / launch actually hits.
  const r = http.get(`${BASE_URL}/api/items`);
  check(r, {
    'status is 200 or 429': (res) => res.status === 200 || res.status === 429,
  });

  // A 429 is acceptable under spike only if the app backs off rather than
  // hammering. Record it, then assert recovery in test_failures.py.
  if (r.status === 429) {
    sleep(2);
  } else {
    sleep(Math.random() * 0.5);
  }
}
