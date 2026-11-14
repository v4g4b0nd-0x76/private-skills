#!/usr/bin/env bash
# Run trigger evals for every skill that has a query set.
# Usage: run-trigger-evals.sh
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failed=0

if [ -z "${TRIGGER_RUNNER:-}" ]; then
  echo "SKIP: TRIGGER_RUNNER is not set, so triggering cannot be measured."
  echo ""
  echo "Set a command that runs one prompt and prints the transcript:"
  echo "  export TRIGGER_RUNNER='cmd run --print-transcript {{prompt}}'"
  echo ""
  echo "Query sets exist for:"
  for d in "$repo_root"/evals/*/; do
    [ -f "$d/eval_queries.json" ] && echo "  - $(basename "${d%/}")"
  done
  echo ""
  echo "Meanwhile, validate the sets without running anything:"
  echo "  scripts/trigger-eval.sh <skill> --dry-run"
  exit 0
fi

for d in "$repo_root"/evals/*/; do
  [ -f "$d/eval_queries.json" ] || continue
  skill="$(basename "${d%/}")"
  if ! bash "$repo_root/scripts/trigger-eval.sh" "$skill"; then
    failed=$((failed + 1))
  fi
done

[ "$failed" -eq 0 ] || { echo "$failed skill(s) failed trigger evals" >&2; exit 1; }
