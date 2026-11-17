#!/usr/bin/env bash
# Validate that a production-grade bench environment is ready.
# Usage: check-bench-env.sh [project-root] [--require-up]
# Exit: 0 ready, 1 not ready, 2 bad args.
set -euo pipefail

root="${1:-.}"
require_up=0
for arg in "$@"; do
  case "$arg" in
    --require-up) require_up=1 ;;
    -h|--help)
      echo "usage: check-bench-env.sh [project-root] [--require-up]" >&2
      exit 2
      ;;
  esac
done

if [ ! -d "$root" ]; then
  echo "error: project root not found: $root" >&2
  exit 2
fi

errors=0
fail() { echo "ERROR: $*" >&2; errors=$((errors + 1)); }
warn() { echo "WARN: $*" >&2; }

env_dir="$root/.bench-env"
artifact="$root/.devflow/bench-env.md"
plan="$root/.devflow/plan.md"

[ -d "$env_dir" ] || fail "missing $env_dir — run setup-bench-env.sh"
[ -f "$env_dir/docker-compose.yml" ] || fail "missing docker-compose.yml"
[ -f "$env_dir/toxiproxy.json" ] || fail "missing toxiproxy.json"
[ -d "$env_dir/wiremock/mappings" ] || fail "missing wiremock/mappings"
[ -d "$env_dir/fixtures" ] || fail "missing fixtures/"

# At least one mapping besides (or including) health
map_count="$(find "$env_dir/wiremock/mappings" -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
[ "$map_count" -ge 1 ] || fail "no WireMock mappings under wiremock/mappings"

# Reject :latest pins
if grep -E 'image:.*:latest' "$env_dir/docker-compose.yml" >/dev/null 2>&1; then
  fail "docker-compose.yml uses :latest — pin image tags"
fi

# Prefer localhost binds for admin ports
if grep -E '^\s*-\s*"?[0-9]+:(8080|8474)' "$env_dir/docker-compose.yml" >/dev/null 2>&1; then
  warn "compose may expose admin ports on all interfaces — prefer 127.0.0.1 binds"
fi

# Softflow plan consistency when present
if [ -f "$plan" ]; then
  bench_env="$(awk '/^---[[:space:]]*$/{fm++;next} fm==1 && /^bench_env:/{sub(/^bench_env:[[:space:]]*/,""); print; exit}' "$plan")"
  [ -n "$bench_env" ] || bench_env="not-required"
  if [ "$bench_env" = "required" ]; then
    [ -f "$artifact" ] || fail "plan.bench_env=required but missing $artifact"
  fi
fi

if [ -f "$artifact" ]; then
  # Must document profiles and fixture paths (anti-hallucination)
  grep -qE 'baseline-zero|prod-like' "$artifact" || fail "bench-env.md must name baseline-zero / prod-like profiles"
  grep -qE '\.bench-env/|fixtures/' "$artifact" || fail "bench-env.md must cite fixture paths under .bench-env/"
  if grep -qiE '\bTODO\b|TBD|fill me|lorem' "$artifact"; then
    fail "bench-env.md still contains TODO/TBD placeholders"
  fi
fi

if [ "$require_up" -eq 1 ]; then
  if ! command -v docker >/dev/null 2>&1; then
    fail "docker missing but --require-up set"
  else
    if ! docker compose -p bench -f "$env_dir/docker-compose.yml" ps --status running 2>/dev/null | grep -q .; then
      fail "compose project 'bench' has no running services — docker compose up -d --wait"
    fi
  fi
fi

if [ "$errors" -gt 0 ]; then
  echo "bench-env check failed: $errors error(s)" >&2
  exit 1
fi

echo "bench-env check passed: $env_dir"
