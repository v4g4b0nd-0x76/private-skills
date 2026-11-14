#!/usr/bin/env bash
# Fault injection for third-party integrations via Toxiproxy.
# Usage: faults.sh --list
#        faults.sh --toxiproxy HOST:PORT --scenario latency --proxy NAME [--latency 2000]
set -euo pipefail

tp=""
scenario=""
proxy=""
latency=""
timeout_ms=""
list_only=0
reset=0

usage() {
  cat >&2 <<'EOF'
usage: faults.sh [options]
  --list                     show scenarios and what each proves
  --toxiproxy HOST:PORT      Toxiproxy admin API (default localhost:8474)
  --proxy NAME               toxiproxy proxy name
  --scenario NAME            latency | timeout | down | reset | bandwidth | packet_loss | recovery
  --latency MS               latency toxic value (default 2000)
  --timeout MS               timeout toxic value (default 5000)
  --reset                    enable all proxies and clear toxics
EOF
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --list) list_only=1; shift ;;
    --toxiproxy) tp="${2:-}"; shift 2 ;;
    --proxy) proxy="${2:-}"; shift 2 ;;
    --scenario) scenario="${2:-}"; shift 2 ;;
    --latency) latency="${2:-}"; shift 2 ;;
    --timeout) timeout_ms="${2:-}"; shift 2 ;;
    --reset) reset=1; shift ;;
    -h|--help) usage ;;
    -*) echo "error: unknown option '$1'" >&2; usage ;;
    *) echo "error: unexpected argument '$1'" >&2; usage ;;
  esac
done

scenarios() {
  cat <<'EOF'
Scenarios, and the behaviour each should prove:

  latency     200ms/2s/5s delay          -> bounded timeout, fallback, no thread pinning
  timeout     stalls then closes          -> does the app fail fast and surface the error?
  down        connection refused          -> graceful 503 or explicit degradation, never fake 200
  reset       TCP RST mid-request         -> retry on idempotent calls only, no double side effect
  bandwidth   rate limited                -> throughput collapse handled, not buffered to OOM
  packet_loss dropped chunks              -> retries bounded, no retry storm
  recovery    remove fault, observe       -> backlog drains, breaker closes, no stuck state
EOF
}

if [ "$list_only" -eq 1 ]; then
  scenarios
  exit 0
fi

tp="${tp:-localhost:8474}"

# Refuse to talk to a non-local Toxiproxy admin API BEFORE any network call.
case "$tp" in
  localhost:*|127.0.0.1:*|\[::1\]:*|127.*) ;;
  *) echo "REFUSED: Toxiproxy admin API must be local (got '$tp')" >&2; exit 2 ;;
esac

command -v curl >/dev/null 2>&1 || { echo "error: curl is required" >&2; exit 1; }

api="http://$tp"

health="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$api/version" 2>/dev/null || echo 000)"
if [ "$health" != "200" ]; then
  echo "error: Toxiproxy not reachable at $api (HTTP $health)" >&2
  echo "" >&2
  echo "start it with:" >&2
  echo "  docker compose -f .thirdparty/docker-compose.yml up -d toxiproxy" >&2
  echo "  # or: brew install toxiproxy && toxiproxy-server" >&2
  exit 1
fi

if [ "$reset" -eq 1 ]; then
  curl -s -X POST "$api/reset" && echo "reset: all proxies enabled, toxics cleared"
  exit 0
fi

[ -n "$scenario" ] || usage
[ -n "$proxy" ] || { echo "error: --proxy is required (see: curl -s $api/proxies)" >&2; exit 1; }

add_toxic() {
  local type="$1"; shift
  local body
  body="$(printf '{"name":"%s_%s","type":"%s","stream":"downstream","attributes":{%s}}' \
          "$type" "$proxy" "$type" "$*")"
  echo "adding: $type on $proxy ($*)"
  if curl -s -X POST -H 'Content-Type: application/json' -d "$body" "$api/proxies/$proxy/toxics" >/dev/null; then
    echo "applied. run the assertion now, then: faults.sh --reset"
  else
    echo "error: failed to add toxic (does proxy '$proxy' exist?)" >&2
    exit 1
  fi
}

case "$scenario" in
  latency)
    add_toxic latency "\"latency\":${latency:-2000},\"jitter\":100"
    ;;
  timeout)
    add_toxic timeout "\"timeout\":${timeout_ms:-5000}"
    ;;
  packet_loss)
    add_toxic packet_loss '"loss_rate":0.2,"correlation":0.3'
    ;;
  bandwidth)
    add_toxic bandwidth '"rate":64'
    ;;
  reset)
    add_toxic reset_peer "\"timeout\":1000"
    ;;
  down)
    echo "disabling proxy $proxy"
    curl -s -X POST -H 'Content-Type: application/json' \
      -d '{"enabled":false}' "$api/proxies/$proxy" >/dev/null
    echo "down. run the assertion now, then: faults.sh --reset"
    ;;
  recovery)
    curl -s -X POST "$api/reset" >/dev/null
    echo "recovered: all proxies enabled, toxics cleared."
    echo "now assert the backlog drained and no state is stuck:"
    echo "  - queue depth returns to baseline"
    echo "  - circuit breaker closes"
    echo "  - no duplicate side effects from buffered retries"
    ;;
  *)
    echo "error: unknown scenario '$scenario'" >&2
    echo "" >&2
    scenarios >&2
    exit 1
    ;;
esac
