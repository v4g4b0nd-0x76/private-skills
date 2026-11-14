// steady: constant arrival rate for the baseline window.
// Reveals baseline latency and error rate. If this fails, nothing above matters.
import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const RATE = Number(__ENV.RATE || 100);

export const options = {
  scenarios: {
    steady: {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      duration: __ENV.DURATION || '5m',
      preAllocatedVUs: Math.max(10, Math.ceil(RATE / 4)),
      maxVUs: Math.max(50, RATE * 2),
    },
  },
  thresholds: {
    // Percentiles, never averages: an average hides a terrible tail.
    http_req_duration: ['p(95)<500', 'p(99)<1500'],
    http_req_failed: ['rate<0.01'],
    checks: ['rate>0.99'],
  },
  // Discard the warm-up window; cold caches make the first minute a lie.
  discardResponseBodies: false,
};

export default function () {
  // TODO: replace with the real mix from .thirdparty/requirements.md.
  const r = http.get(`${BASE_URL}/api/items`);
  check(r, {
    'status is 200': (res) => res.status === 200,
    'body is not empty': (res) => (res.body || '').length > 0,
  });
  // Randomised think time: zero delay measures a bot, not a user.
  sleep(Math.random() * 1.5);
}
