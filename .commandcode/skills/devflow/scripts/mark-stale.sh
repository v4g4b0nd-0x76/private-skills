#!/usr/bin/env bash
# Mark devflow artifacts stale after an upstream change.
# Usage: mark-stale.sh <project-root> <research|plan|implement|bench-env|test|review>...
set -euo pipefail

root="${1:-.}"
shift || true

if [ "$#" -eq 0 ]; then
  echo "usage: mark-stale.sh <project-root> <research|plan|implement|bench-env|test|review>..." >&2
  exit 1
fi

file_for() {
  case "$1" in
    research) echo "research.md" ;;
    plan) echo "plan.md" ;;
    implement) echo "implement.md" ;;
    bench-env|benchenv) echo "bench-env.md" ;;
    test) echo "test-report.md" ;;
    review) echo "review.md" ;;
    *) echo "" ;;
  esac
}

for stage in "$@"; do
  name="$(file_for "$stage")"
  if [ -z "$name" ]; then
    echo "error: unknown stage '$stage' (research|plan|implement|bench-env|test|review)" >&2
    exit 1
  fi

  file="$root/.devflow/$name"
  if [ ! -f "$file" ]; then
    echo "skip: $file does not exist"
    continue
  fi
  if ! grep -q '^status:' "$file"; then
    echo "error: $file has no status field" >&2
    exit 1
  fi

  tmp="$(mktemp)"
  awk '/^---[[:space:]]*$/ { fm++ }
       fm == 1 && /^status:/ { print "status: stale"; next }
       fm == 1 && /^verdict:/ { print "verdict:"; next }
       { print }' "$file" > "$tmp"
  mv "$tmp" "$file"
  echo "stale: $file"
done
