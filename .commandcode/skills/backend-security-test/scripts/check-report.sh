#!/usr/bin/env bash
# Enforce structural rules on a backend security report.
# Usage: check-report.sh <report.md>
set -euo pipefail

file="${1:-}"
usage() {
  echo "usage: check-report.sh <report.md>" >&2
  exit 1
}
[ -n "$file" ] || usage
[ -f "$file" ] || { echo "error: no such report: $file" >&2; exit 2; }

errors=0
fail() { echo "ERROR: $*" >&2; errors=$((errors + 1)); }

count_findings() { grep -c '^### FINDING-' "$file" 2>/dev/null || true; }
findings="$(count_findings)"
findings="${findings:-0}"

for heading in Scope "What was not tested" Findings "Rejected candidates"; do
  if ! grep -qi "^## $heading" "$file"; then
    fail "missing section: ## $heading"
  fi
done

if [ "$findings" -eq 0 ]; then
  echo "note: no ### FINDING- entries; a clean result is valid but say so in ## Findings."
fi

section_of() {
  awk -v want="$1" '
    /^## / { title = substr($0, 4); gsub(/[[:space:]]+$/, "", title);
             in_all = (tolower(title) == "findings"); next }
    in_all { print }
  ' "$file"
}

body="$(section_of findings)"

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
    for field in Severity Class Endpoint Reproduction "Observed" "Expected" Impact Fix Confidence; do
      if ! printf '%s\n' "$b" | grep -qi -- "$field"; then
        fail "finding $i is missing '$field'"
      fi
    done
    if printf '%s\n' "$b" | grep -qi 'Confidence: *confirmed'; then
      printf '%s\n' "$b" | grep -qi 'Reproduction' || fail "finding $i: confirmed without reproduction"
    fi
    if printf '%s\n' "$b" | grep -qi 'TODO\|TBD\|FIXME'; then
      fail "finding $i contains an unfilled placeholder"
    fi
    i=$((i + 1))
  done
fi

if grep -qiE 'confidence:?[*[:space:]]*(high|likely|probably)' "$file"; then
  fail "use only: confirmed | unverified | rejected (see references/false-positive.md)"
fi

# Unfilled template placeholders: <...> where a real value belongs.
if grep -qE '<[A-Za-z][^>]*>' "$file"; then
  count="$(grep -cE '<[A-Za-z][^>]*>' "$file" || true)"
  fail "$count unfilled <placeholder> value(s) — this is still the template"
fi

if grep -qi 'TODO\|TBD' "$file"; then
  fail "report contains unfilled placeholders (TODO/TBD)"
fi

if grep -q '^## What was not tested' "$file"; then
  untested="$(awk '/^## What was not tested/ {f=1; next} /^## / {f=0} f' "$file" | tr -d '[:space:]-')"
  [ -n "$untested" ] || fail "## What was not tested is empty — state the gaps"
fi

if [ "$errors" -gt 0 ]; then
  echo "" >&2
  echo "report check failed: $errors error(s)" >&2
  exit 1
fi

echo "report check passed: $file ($findings finding(s))"
