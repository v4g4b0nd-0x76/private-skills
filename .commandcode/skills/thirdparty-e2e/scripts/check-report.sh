#!/usr/bin/env bash
# Enforce structural rules on a third-party E2E report.
# Usage: check-report.sh <report.md>
set -euo pipefail

file="${1:-}"
[ -n "$file" ] || { echo "usage: check-report.sh <report.md>" >&2; exit 1; }
[ -f "$file" ] || { echo "error: no such report: $file" >&2; exit 2; }

errors=0
fail() { echo "ERROR: $*" >&2; errors=$((errors + 1)); }

for heading in "Third-party requirements" "Load conditions tested" "Unexpected behaviour" "What was not tested"; do
  grep -qi "^## $heading" "$file" || fail "missing section: ## $heading"
done

findings="$(grep -c '^### FINDING-' "$file" 2>/dev/null || true)"
findings="${findings:-0}"

if [ "$findings" -gt 0 ]; then
  block() {
    awk -v n="$1" '
      /^### FINDING-/ { idx++; current = (idx == n); next }
      /^## / && !/^### / { if (current) exit }
      current { print }
    ' "$file"
  }

  i=1
  while [ "$i" -le "$findings" ]; do
    b="$(block "$i")"
    for field in Provider Severity Behaviour Reproduction "Observed" "Expected" Condition Impact Fix; do
      printf '%s\n' "$b" | grep -qi -- "$field" || fail "finding $i is missing '$field'"
    done
    if printf '%s\n' "$b" | grep -qi 'TODO\|TBD'; then
      fail "finding $i has unfilled placeholders"
    fi
    i=$((i + 1))
  done
fi

# The requirements table must actually list providers.
if grep -q '^## Third-party requirements' "$file"; then
  rows="$(awk '/^## Third-party requirements/ {f=1; next} /^## / {f=0} f' "$file" | grep -c '^|' || true)"
  [ "${rows:-0}" -ge 3 ] || fail "## Third-party requirements needs a populated table (header + rows)"
fi

# Load conditions must name at least one profile or fault scenario.
if grep -q '^## Load conditions tested' "$file"; then
  body="$(awk '/^## Load conditions tested/ {f=1; next} /^## / {f=0} f' "$file" | tr -d '[:space:]-')"
  [ -n "$body" ] || fail "## Load conditions tested is empty — name the profiles and fault scenarios run"
fi

if grep -qE '<[A-Za-z][^>]*>' "$file"; then
  fail "$(grep -cE '<[A-Za-z][^>]*>' "$file") unfilled <placeholder>(s) — still the template"
fi

if grep -qi 'TODO\|TBD' "$file"; then
  fail "report contains unfilled placeholders (TODO/TBD)"
fi

if [ "$errors" -gt 0 ]; then
  echo "" >&2
  echo "report check failed: $errors error(s)" >&2
  exit 1
fi

echo "report check passed: $file ($findings finding(s))"
