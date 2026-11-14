#!/usr/bin/env bash
# Probe a LOCAL backend you own for access-control and leakage issues.
# Usage: probe.sh <base-url> [--dry-run] [--i-own-this-target] [options]
#
# Safety: refuses any non-local host. Sending requests requires
# --i-own-this-target. Destructive verbs require --allow-destructive.
set -euo pipefail

url=""
dry_run=0
authorized=0
allow_destructive=0
concurrency=4
budget=200
delay_ms=50
token=""
alt_token=""

usage() {
  cat >&2 <<'EOF'
usage: probe.sh <base-url> [options]
  --dry-run              print the plan and send nothing (start here)
  --i-own-this-target    required to send traffic; asserts authorization
  --allow-destructive    permit DELETE/PATCH/destructive verbs
  --concurrency N        parallel requests (default 4)
  --budget N             max requests (default 200)
  --delay-ms N           delay between batches (default 50)
  --token JWT            primary bearer token
  --alt-token JWT        second principal, for cross-user checks

Only localhost / 127.0.0.1 / ::1 / *.test / *.localhost are accepted.
EOF
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) dry_run=1; shift ;;
    --i-own-this-target) authorized=1; shift ;;
    --allow-destructive) allow_destructive=1; shift ;;
    --concurrency) concurrency="${2:-}"; shift 2 ;;
    --budget) budget="${2:-}"; shift 2 ;;
    --delay-ms) delay_ms="${2:-}"; shift 2 ;;
    --token) token="${2:-}"; shift 2 ;;
    --alt-token) alt_token="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    -*) echo "error: unknown option '$1'" >&2; usage ;;
    *) url="$1"; shift ;;
  esac
done

[ -n "$url" ] || usage

case "$concurrency$budget$delay_ms" in
  *[!0-9]*|"") echo "error: --concurrency/--budget/--delay-ms must be integers" >&2; exit 1 ;;
esac

if ! [[ "$url" =~ ^https?:// ]]; then
  echo "error: URL must start with http:// or https://" >&2
  exit 1
fi

host="${url#*://}"
host="${host%%/*}"
host="${host%%\?*}"
host="${host%%#*}"
host_port="$host"
host="${host%%:*}"
# IPv6 in brackets: [::1]:8080
case "$host_port" in
  \[*\]:*) host="$(printf '%s' "$host_port" | sed 's/^\[\(.*\)\]:.*$/\1/')" ;;
  \[*\]) host="$(printf '%s' "$host_port" | tr -d '[]')" ;;
esac

is_local() {
  case "$1" in
    localhost|127.0.0.1|::1|0.0.0.0|host.docker.internal) return 0 ;;
    *.localhost|*.test) return 0 ;;
    # 127.0.0.0/8
    127.*) return 0 ;;
    *) return 1 ;;
  esac
}

if ! is_local "$host"; then
  echo "REFUSED: '$host' is not a local target." >&2
  echo "" >&2
  echo "This skill only tests systems you run yourself. Allowed: localhost," >&2
  echo "127.0.0.0/8, ::1, *.localhost, *.test." >&2
  echo "" >&2
  echo "Testing a third-party or production domain without written authorization" >&2
  echo "is likely illegal. Generate a suite with gen-suite.sh instead." >&2
  exit 2
fi

echo "target: $url (local host: $host)"
echo "budget: $budget requests, concurrency $concurrency, delay ${delay_ms}ms"

plan_shown=0
show_plan() {
  [ "$plan_shown" -eq 1 ] && return
  plan_shown=1
  cat <<'EOF'

== request plan ==
  1. unauthenticated GET on a protected route      -> expect 401/403
  2. malformed Authorization header                -> expect 401/403
  3. tampered token signature                      -> expect 401/403
  4. expired token                                 -> expect 401/403
  5. primary token on own object                   -> expect 2xx (baseline)
  6. primary token on secondary principal's object -> expect 403/404
  7. alt token on primary's object                 -> expect 403/404
  8. extra ownership fields in PATCH/POST          -> must not persist
  9. parallel duplicate action burst                -> side effect must be once
 10. error paths for stack traces / SQL / paths    -> must not appear
 11. response headers for cache-control on auth    -> must not be public
EOF
  if [ "$allow_destructive" -eq 0 ]; then
    echo "  destructive verbs (DELETE etc): DISABLED (pass --allow-destructive)"
  else
    echo "  destructive verbs: ENABLED"
  fi
  echo ""
}

show_plan

if [ "$dry_run" -eq 1 ]; then
  echo "dry run: nothing sent."
  echo "to actually probe a local dev server you own, add --i-own-this-target"
  exit 0
fi

if [ "$authorized" -eq 0 ]; then
  echo "REFUSED: sending requests requires --i-own-this-target." >&2
  echo "That flag is your assertion that you own or are authorized to test this host." >&2
  exit 2
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "error: curl is required" >&2
  exit 1
fi

sent=0
probe() {
  local method="$1" path="$2" auth="$3" note="$4"
  shift 4 || true
  local extra=("$@")

  case "$method" in
    DELETE|PATCH|PUT)
      if [ "$allow_destructive" -eq 0 ]; then
        echo "SKIP   $method $path — destructive verbs disabled ($note)"
        return 0
      fi
      ;;
  esac

  if [ "$sent" -ge "$budget" ]; then
    return 0
  fi
  sent=$((sent + 1))

  local args=(-s -o /dev/null -w '%{http_code}' -X "$method" --max-time 10)
  [ -n "$auth" ] && args+=(-H "Authorization: Bearer $auth")
  if [ "${#extra[@]}" -gt 0 ]; then
    args+=("${extra[@]}")
  fi
  args+=("$url$path")

  local code
  code="$(curl "${args[@]}" 2>/dev/null || echo "000")"
  printf '%-6s %-4s %-40s -> %s  (%s)\n' "$code" "$method" "$path" "${auth:+auth}" "$note"
}

echo ""
echo "== authentication =="
probe GET /api/me "" "no credentials"
probe GET /api/me "not-a-jwt" "malformed token"
probe GET /api/me "${token:-}" "primary token baseline"
if [ -n "$token" ] && [ "${#token}" -gt 8 ]; then
  tampered="${token%????}AAAA"
  probe GET /api/me "$tampered" "tampered signature"
fi

echo ""
echo "== authorization (needs two principals + their own object ids) =="
if [ -z "$alt_token" ]; then
  echo "SKIP   cross-user checks — pass --alt-token with a second principal"
  echo "       single-account probing cannot prove a boundary failure"
else
  echo "       supply the two object ids to compare; this script does not guess them"
fi

echo ""
echo "== leakage =="
probe GET "/api/me" "${token:-}" "inspect fields for secrets"
probe GET "/api/items/not-a-number" "${token:-}" "error path must not leak internals"

echo ""
echo "== race (use the generated suite for assertions) =="
echo "       parallel bursts need real assertions:"
echo "       for i in \$(seq 1 $concurrency); do curl -s -o /dev/null -X POST -H 'Authorization: Bearer \$TOKEN' $url/api/checkout & done; wait"
echo "       then assert the side effect happened once"

echo ""
echo "requests sent: $sent / $budget"
echo ""
echo "This script only reports status codes. Confirming a vulnerability requires the"
echo "generated suite, which asserts on state. A 200 here is not a finding."
