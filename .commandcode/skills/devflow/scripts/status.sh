#!/usr/bin/env bash
# Print the devflow artifact table for a project.
# Usage: status.sh [project-root]
set -euo pipefail

root="${1:-.}"
dir="$root/.devflow"

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
  ' "$2"
}

if [ ! -d "$dir" ]; then
  echo "No .devflow/ in $root — next stage: devflow-research"
  exit 0
fi

printf '%-12s %-10s %-14s %s\n' STAGE STATUS APPROVAL ARTIFACT
for pair in "research:research.md" "plan:plan.md" "implement:implement.md" \
            "test:test-report.md" "review:review.md"; do
  stage="${pair%%:*}"
  file="$dir/${pair#*:}"
  if [ -f "$file" ]; then
    printf '%-12s %-10s %-14s %s\n' \
      "$stage" "$(field status "$file")" "$(field approval "$file")" "$file"
  else
    printf '%-12s %-10s %-14s %s\n' "$stage" "-" "-" "$file (missing)"
  fi
done
