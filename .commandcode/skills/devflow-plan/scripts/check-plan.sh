#!/usr/bin/env bash
# Validate a devflow plan artifact before the approval gate.
# Usage: check-plan.sh [project-root]
set -euo pipefail

root="${1:-.}"
file="$root/.devflow/plan.md"
errors=0

fail() { echo "ERROR: $*" >&2; errors=$((errors + 1)); }

[ -f "$file" ] || { echo "ERROR: missing $file (route back to devflow-research)" >&2; exit 1; }

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

[ "$(field devflow)" = "plan" ] || fail "header must contain 'devflow: plan'"

case "$(field upstream)" in
  *research.md) ;;
  *) fail "upstream must point at research.md (found '$(field upstream)')" ;;
esac

case "$(field status)" in
  draft|approved) ;;
  *) fail "status must be 'draft' or 'approved' (found '$(field status)')" ;;
esac

case "$(field approval)" in
  pending|granted) ;;
  *) fail "approval must be 'pending' or 'granted' (found '$(field approval)')" ;;
esac

[ "$(field updated)" != "YYYY-MM-DD" ] || fail "updated date was not set"

for heading in Goal "Non-goals" Steps "Files to touch" "Test plan" "Risks and rollback"; do
  if [ -z "$(section "$heading" | tr -d '[:space:]')" ]; then
    fail "missing or empty section: ## $heading"
  fi
done

steps="$(section Steps | grep -cE '^[0-9]+\.' || true)"
[ "$steps" -ge 1 ] || fail "Steps needs at least one numbered step"

files="$(section "Files to touch" | grep -c '^-[[:space:]]' || true)"
[ "$files" -ge 1 ] || fail "Files to touch needs at least one bullet"

if section "Files to touch" | grep -q '^-[[:space:]]*`\?/'; then
  fail "Files to touch must use project-relative paths, not absolute paths"
fi

tests="$(section "Test plan" | grep -c '^-' || true)"
[ "$tests" -ge 1 ] || fail "Test plan needs at least one runnable command"

if [ "$errors" -gt 0 ]; then
  echo "plan check failed: $errors error(s)" >&2
  exit 1
fi

echo "plan check passed: $file"
