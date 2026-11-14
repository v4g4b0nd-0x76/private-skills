#!/usr/bin/env bash
# Validate a devflow research artifact before planning.
# Usage: check-research.sh [project-root]
set -euo pipefail

root="${1:-.}"
file="$root/.devflow/research.md"
errors=0

fail() { echo "ERROR: $*" >&2; errors=$((errors + 1)); }

[ -f "$file" ] || { echo "ERROR: missing $file" >&2; exit 1; }

field() {
  awk -v key="$1" '
    /^---[[:space:]]*$/ { fm++; next }
    fm == 1 {
      if (index($0, key ":") == 1) {
        line = $0
        sub("^" key ":[[:space:]]*", "", line)
        print line
        exit
      }
    }
  ' "$file"
}

section() {
  awk -v want="$1" '
    /^## / { title = substr($0, 4); gsub(/[[:space:]]+$/, "", title);
             in_section = (tolower(title) == tolower(want)); next }
    in_section { print }
  ' "$file"
}

[ "$(field devflow)" = "research" ] || fail "header must contain 'devflow: research'"
[ "$(field status)" = "complete" ] || fail "status must be 'complete' (found '$(field status)')"
[ "$(field updated)" != "YYYY-MM-DD" ] || fail "updated date was not set"

for heading in Task Findings Decisions Sources; do
  if [ -z "$(section "$heading" | tr -d '[:space:]')" ]; then
    fail "missing or empty section: ## $heading"
  fi
done

findings="$(section Findings | grep -c '^-[[:space:]]' || true)"
[ "$findings" -ge 2 ] || fail "Findings needs at least 2 bullets (found $findings)"

sources="$(section Sources | grep -cE '^([0-9]+\.|-)[[:space:]]' || true)"
[ "$sources" -ge 3 ] || fail "Sources needs at least 3 entries (found $sources)"

source_urls="$(section Sources | grep -c 'http' || true)"
[ "$source_urls" -ge 2 ] || fail "Sources needs at least 2 entries with URLs (found $source_urls)"

if section "Open questions" | grep -qi 'BLOCKER'; then
  fail "unresolved BLOCKER in Open questions"
fi

if [ "$errors" -gt 0 ]; then
  echo "research check failed: $errors error(s)" >&2
  exit 1
fi

echo "research check passed: $file"
