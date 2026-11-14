// smoke: 1 VU, 30s. Not a load test — proves wiring, auth, and the target.
// Run this first, always. If it fails, nothing above it is meaningful.
import http from 'k6/http';
import { check } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

export const options = {
  vus: 1,
  duration: __ENV.DURATION || '30s',
  thresholds: {
    http_req_failed: ['rate<0.01'],
    checks: ['rate>0.99'],
  },
};

export default function () {
  const health = http.get(`${BASE_URL}/health`);
  check(health, {
    'health is 200': (r) => r.status === 200,
    'health answered fast': (r) => r.timings.duration < 1000,
  });

  // TODO: replace with the real entry path of your most critical journey.
  const index = http.get(`${BASE_URL}/`);
  check(index, { 'index reachable': (r) => r.status < 500 });
}
