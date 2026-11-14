#!/usr/bin/env bash
# Inventory third-party dependencies: outbound clients, provider SDKs, endpoints, packages.
# Usage: inventory.sh <app-root> [--json]
set -euo pipefail

root=""
json=0

for arg in "$@"; do
  case "$arg" in
    --json) json=1 ;;
    -h|--help) echo "usage: inventory.sh <app-root> [--json]" >&2; exit 1 ;;
    -*) echo "error: unknown option '$arg'" >&2; exit 1 ;;
    *) root="$arg" ;;
  esac
done

[ -n "$root" ] && [ -d "$root" ] || { echo "error: app root not found: ${root:-<none>}" >&2; exit 2; }
cd "$root"

files="$(find . -type d \( -name node_modules -o -name target -o -name vendor -o -name .git \
          -o -name dist -o -name build -o -name .venv -o -name venv -o -name __pycache__ \
          -o -name coverage -o -name .next \) -prune -o \
        -type f \( -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.go' -o -name '*.rs' \
          -o -name '*.java' -o -name '*.rb' -o -name '*.php' -o -name '*.cs' -o -name '*.kt' \) -print 2>/dev/null || true)"

[ -n "$files" ] || { echo "error: no source files under $root" >&2; exit 1; }

find_hits() {
  # shellcheck disable=SC2086
  printf '%s\n' "$files" | xargs grep -nE -- "$1" 2>/dev/null | head -"${2:-12}" || true
}

count_hits() {
  # shellcheck disable=SC2086
  printf '%s\n' "$files" | xargs grep -lE -- "$1" 2>/dev/null | wc -l | tr -d ' '
}

P_HARDCODED='https?://[a-zA-Z0-9._-]+'
P_ENDPOINT='(BASE_URL|base_url|API_URL|api_url|ENDPOINT|endpoint|HOST|_URL)'
P_SDK='stripe|twilio|sendgrid|mailgun|postmark|slack|github|salesforce|hubspot|openai|anthropic|aws-sdk|boto3|google-cloud|azure|paypal|braintree|adyen|plaid|shopify|segment|datadog|sentry|auth0|okta|keycloak|firebase|supabase'
P_AUTH='api[_-]?key|apikey|bearer|client_secret|access_token|Authorization|X-Api-Key|OAuth|oauth2'
P_RETRY='retry|backoff|max_retries|maxNetworkRetries|retries|jitter|Retry-After'
P_TIMEOUT='timeout|connect_timeout|read_timeout|deadline'
P_WEBHOOK='webhook|callback|signature|hmac|X-Signature|verify_signature'
P_HTTP='requests\.|httpx\.|axios|fetch\(|http\.Client|reqwest|RestTemplate|WebClient|HttpClient|urllib|curl'

if [ "$json" -eq 1 ]; then
  cat <<EOF
{
  "root": "$(pwd)",
  "files_scanned": $(printf '%s\n' "$files" | wc -l | tr -d ' '),
  "hardcoded_endpoints": $(count_hits "$P_HARDCODED"),
  "provider_sdks": $(count_hits "$P_SDK"),
  "auth_sites": $(count_hits "$P_AUTH"),
  "retry_sites": $(count_hits "$P_RETRY"),
  "timeout_sites": $(count_hits "$P_TIMEOUT"),
  "webhook_sites": $(count_hits "$P_WEBHOOK"),
  "http_clients": $(count_hits "$P_HTTP")
}
EOF
  exit 0
fi

echo "== third-party inventory: $(pwd) =="
echo "files scanned: $(printf '%s\n' "$files" | wc -l | tr -d ' ')"
echo ""

echo "== provider SDKs / packages =="
for manifest in package.json pyproject.toml requirements.txt Cargo.toml go.mod Gemfile composer.json; do
  [ -f "$manifest" ] || continue
  echo "  [$manifest]"
  found="$(grep -nEi "$P_SDK" "$manifest" 2>/dev/null | head -10 || true)"
  if [ -n "$found" ]; then
    printf '%s\n' "$found" | sed 's/^/    /'
  else
    echo "    (no known provider packages)"
  fi
done

echo ""
echo "== hardcoded / configured endpoints =="
find_hits "$P_HARDCODED" 12

echo ""
echo "== endpoint config keys =="
find_hits "$P_ENDPOINT" 12

# Config files (.env and friends) hold most provider endpoints, and they are
# not source files, so scan them separately.
config_files="$(find . -maxdepth 3 -type f \( -name '.env' -o -name '.env.*' -o -name '*.env' \
                  -o -name 'config.yaml' -o -name 'config.yml' -o -name 'application*.yml' \
                  -o -name 'application*.properties' -o -name 'values*.yaml' \) \
                -not -path './.git/*' 2>/dev/null || true)"
if [ -n "$config_files" ]; then
  echo "  [config files]"
  # shellcheck disable=SC2086
  printf '%s\n' "$config_files" | while IFS= read -r cf; do
    [ -n "$cf" ] || continue
    grep -nEi '(_URL|_HOST|_ENDPOINT|BASE_URL|SECRET|_KEY|TOKEN|WEBHOOK)' "$cf" 2>/dev/null \
      | sed "s|^|    $cf:|" | head -12 || true
  done
fi

echo ""
echo "== outbound HTTP call sites =="
find_hits "$P_HTTP" 12

echo ""
echo "== auth / credentials =="
find_hits "$P_AUTH" 10

echo ""
echo "== retry / backoff policy =="
find_hits "$P_RETRY" 10

echo ""
echo "== timeouts =="
find_hits "$P_TIMEOUT" 10

echo ""
echo "== inbound webhooks / signature checks =="
find_hits "$P_WEBHOOK" 10

echo ""
echo "== dependency advisories =="
adv=0
if [ -f Cargo.toml ] && command -v cargo >/dev/null 2>&1; then
  command -v cargo-audit >/dev/null 2>&1 && echo "  run: cargo audit" || { echo "  cargo audit not installed (cargo install cargo-audit)"; adv=1; }
fi
if [ -f package.json ] && command -v npm >/dev/null 2>&1; then
  echo "  run: npm audit --omit=dev"
fi
if [ -f pyproject.toml ] || [ -f requirements.txt ]; then
  command -v pip-audit >/dev/null 2>&1 && echo "  run: pip-audit" || echo "  pip-audit not installed (pip install pip-audit)"
fi

echo ""
echo "next:"
echo "  1. record every provider in .thirdparty/requirements.md (assets/integration-requirements.md)"
echo "  2. for each: can it run locally? sandbox? neither? -> references/testing-layers.md"
echo "  3. gen-e2e.sh <root> --out .thirdparty/e2e"
