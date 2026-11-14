#!/usr/bin/env bash
# Print the next devflow action for a project.
# Usage: next.sh [project-root]
# Exit codes: 0 action printed, 2 not a directory.
set -euo pipefail

root="${1:-.}"
dir="$root/.devflow"

if [ ! -d "$root" ]; then
  echo "error: project root not found: $root" >&2
  exit 2
fi

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

value() {
  [ -f "$1" ] && field "$2" "$1" || echo ""
}

describe() {
  if [ ! -f "$1" ]; then
    echo "missing"
    return
  fi
  local s
  s="$(field status "$1")"
  echo "${s:-no status}"
}

done_state() { case "$1" in complete|approved) return 0;; *) return 1;; esac; }

report() {
  printf 'NEXT: %s\nWHY: %s\n' "$1" "$2"
  exit 0
}

gate() {
  printf 'GATE: %s\nACTION: %s\n' "$1" "$2"
  exit 0
}

if [ ! -d "$dir" ]; then
  report devflow-research "no .devflow/ artifacts yet"
fi

research="$dir/research.md"
plan="$dir/plan.md"
implement="$dir/implement.md"
test="$dir/test-report.md"
review="$dir/review.md"

if ! done_state "$(value "$research" status)"; then
  report devflow-research "research.md is $(describe "$research")"
fi

if [ "$(value "$plan" approval)" = "pending" ]; then
  gate "plan approval required" \
    "show .devflow/plan.md, ask the user, then set status: approved and approval: granted"
fi

if [ "$(value "$plan" status)" != "approved" ]; then
  report devflow-plan "plan.md is $(describe "$plan")"
fi

if ! done_state "$(value "$implement" status)"; then
  report devflow-implement "implement.md is $(describe "$implement")"
fi

if [ "$(value "$test" verdict)" = "fail" ]; then
  report devflow-implement "test-report verdict is fail; fix the failures and rerun the gates"
fi

if ! done_state "$(value "$test" status)"; then
  gate "test run approval required" \
    "show the commands run-gates.sh plans to run, ask the user, then run them"
fi

if ! done_state "$(value "$review" status)"; then
  report devflow-review "review.md is $(describe "$review")"
fi

if [ "$(value "$review" verdict)" = "changes-requested" ]; then
  report devflow-implement "review requested changes; mark test and review stale before rerunning"
fi

printf 'DONE\nVERDICT: %s\n' "$(value "$review" verdict)"
