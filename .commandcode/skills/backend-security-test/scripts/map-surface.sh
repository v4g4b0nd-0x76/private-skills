#!/usr/bin/env bash
# Map a backend's logic surface: routes, identity sources, object refs, ownership fields.
# Usage: map-surface.sh <backend-root> [--json]
set -euo pipefail

root=""
json=0

for arg in "$@"; do
  case "$arg" in
    --json) json=1 ;;
    -h|--help)
      echo "usage: map-surface.sh <backend-root> [--json]" >&2
      exit 1
      ;;
    -*) echo "error: unknown option '$arg'" >&2; exit 1 ;;
    *) root="$arg" ;;
  esac
done

if [ -z "$root" ] || [ ! -d "$root" ]; then
  echo "error: backend root not found: ${root:-<none>}" >&2
  exit 2
fi

cd "$root"

# Collect source files, excluding vendored/build/test-noise directories.
src_files() {
  find . \
    -type d \( -name node_modules -o -name target -o -name vendor -o -name .git \
                -o -name dist -o -name build -o -name .venv -o -name venv \
                -o -name __pycache__ -o -name coverage \) -prune -o \
    -type f \( -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.go' \
                -o -name '*.rs' -o -name '*.java' -o -name '*.kt' -o -name '*.rb' \
                -o -name '*.php' -o -name '*.cs' \) -print 2>/dev/null
}

files="$(src_files || true)"
if [ -z "$files" ]; then
  echo "error: no source files found under $root" >&2
  exit 1
fi

count_hits() {
  # shellcheck disable=SC2086
  printf '%s\n' "$files" | xargs grep -lE -- "$1" 2>/dev/null | wc -l | tr -d ' '
}

hits() {
  # shellcheck disable=SC2086
  printf '%s\n' "$files" | xargs grep -nE -- "$1" 2>/dev/null | head -"${2:-10}" || true
}

frame() {
  local name="$1"
  case "$name" in
    django) command -v python3 >/dev/null 2>&1 && find . -name 'urls.py' -o -name 'views.py' 2>/dev/null | head -1 ;;
    express) find . -name 'package.json' -not -path '*/node_modules/*' 2>/dev/null | head -1 ;;
    actix|axum|rocket) find . -name 'Cargo.toml' 2>/dev/null | head -1 ;;
    spring) find . -name 'pom.xml' -o -name 'build.gradle*' 2>/dev/null | head -1 ;;
    rails) find . -name 'Gemfile' 2>/dev/null | head -1 ;;
    laravel) find . -name 'artisan' 2>/dev/null | head -1 ;;
    fastapi|flask) find . -name 'pyproject.toml' -o -name 'requirements.txt' 2>/dev/null | head -1 ;;
  esac
}

if [ "$json" -eq 1 ]; then
  cat <<EOF
{
  "root": "$(pwd)",
  "files_scanned": $(printf '%s\n' "$files" | wc -l | tr -d ' '),
  "routes": $(count_hits '(app|router)\.(get|post|put|patch|delete)|@(app|router)\.(route|get|post)|#\[(get|post|put|delete|patch)|@(Get|Post|Put|Delete)Mapping|Route::(get|post|put|delete)|(get|post|put|patch|delete) *\('),
  "auth_decorators": $(count_hits 'login_required|requires_auth|authenticate|@PreAuthorize|before_action|jwt_required|require_auth'),
  "ownership_fields": $(count_hits 'owner_id|ownerId|user_id|userId|account_id|accountId|tenant_id|tenantId|organization_id|org_id'),
  "privileged_actions": $(count_hits 'delete|approve|transfer|refund|invite|impersonate|revoke|promote|grant'),
  "sensitive_fields": $(count_hits 'password|secret|token|api_key|ssn|iban|card_number|mfa')
}
EOF
  exit 0
fi

echo "== backend logic surface: $(pwd) =="
echo "files scanned: $(printf '%s\n' "$files" | wc -l | tr -d ' ')"
echo ""

echo "== detected stack =="
for f in django express actix axum rocket spring rails laravel fastapi flask; do
  marker="$(frame "$f" || true)"
  [ -n "${marker:-}" ] && echo "  $f: $marker"
done

echo ""
echo "== entry points (routes / handlers) =="
hits '(app|router)\.(get|post|put|patch|delete)\s*\(|@(app|router)\.(route|get|post)\s*\(|#\[(get|post|put|delete|patch)\s*\(|@(Get|Post|Put|Delete|Patch|Request)Mapping|Route::(get|post|put|delete)|(get|post|put|patch|delete)\s*\(' 20

echo ""
echo "== authorization checks (verify these cover every object path) =="
hits 'login_required|requires_auth|authenticate|@PreAuthorize|before_action|jwt_required|require_auth|is_authenticated|require_permission|has_role' 15

echo ""
echo "== ownership / tenant fields in requests (BOLA rebinding candidates) =="
hits 'owner_id|ownerId|user_id|userId|account_id|accountId|tenant_id|tenantId|organization_id|org_id|msg\.Sender' 15

echo ""
echo "== privileged state-changing actions (Action-Level BOLA) =="
hits '"\/(delete|approve|transfer|refund|invite|impersonate|revoke|promote|grant|archive)' 10
hits '(delete|approve|transfer|refund|invite|impersonate|revoke|promote|grant|archive)\w*\s*\(' 10

echo ""
echo "== sensitive fields (data-leakage checks) =="
hits 'password_hash|password|secret|api_key|access_token|refresh_token|ssn|iban|card_number|mfa_secret' 15

echo ""
echo "== raw / unscoped queries (ownership scoping may be bypassed) =="
hits '\.raw\(|\.extra\(|execute\(|findOne\(|query\(' 10

echo ""
echo "next steps:"
echo "  1. read references/logic-surface.md and write .security/surface.md"
echo "  2. gen-suite.sh <root> --out .security/suite"
echo "  3. prioritize routes that mutate an object identified in the path or body"
