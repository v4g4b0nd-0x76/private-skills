#!/usr/bin/env bash
# Run LLVM source-based coverage with a threshold gate.
# Usage: coverage.sh [project-root] [--min PERCENT] [--html] [--workspace] [--no-gate]
set -euo pipefail

root="."
min_lines=""
min_regions=""
html=0
workspace=0
gate=1

usage() {
  cat >&2 <<'EOF'
usage: coverage.sh [project-root] [options]
  --min PERCENT     fail below this line-coverage percentage (default from CI env or 0)
  --regions PERCENT fail below this region-coverage percentage
  --html            also write an HTML report to target/llvm-cov/html
  --workspace       cover all workspace crates
  --no-gate         report only, never fail on the threshold
EOF
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --min) min_lines="${2:-}"; shift 2 ;;
    --regions) min_regions="${2:-}"; shift 2 ;;
    --html) html=1; shift ;;
    --workspace) workspace=1; shift ;;
    --no-gate) gate=0; shift ;;
    -h|--help) usage ;;
    -*) echo "error: unknown option '$1'" >&2; usage ;;
    *) root="$1"; shift ;;
  esac
done

if [ ! -f "$root/Cargo.toml" ]; then
  echo "error: no Cargo.toml in $root" >&2
  exit 2
fi

cd "$root"

if ! command -v cargo-llvm-cov >/dev/null 2>&1 && ! cargo llvm-cov --version >/dev/null 2>&1; then
  echo "error: cargo-llvm-cov not installed" >&2
  echo "" >&2
  echo "  cargo install cargo-llvm-cov --locked" >&2
  echo "  rustup component add llvm-tools-preview" >&2
  exit 1
fi

args=(llvm-cov --summary-only)
[ "$workspace" -eq 1 ] && args+=(--workspace)
[ "$html" -eq 1 ] && args+=(--html)

if [ "$gate" -eq 0 ]; then
  args+=(--no-fail-fast)
fi

echo "== coverage =="
echo "running: cargo ${args[*]}"

set +e
out="$(cargo "${args[@]}" 2>&1)"
status=$?
set -e
printf '%s\n' "$out"

if [ "$status" -ne 0 ]; then
  echo "" >&2
  echo "coverage run failed (exit $status)" >&2
  exit "$status"
fi

if [ "$gate" -eq 1 ]; then
  if [ -z "$min_lines" ] && [ -z "$min_regions" ]; then
    echo ""
    echo "report only: pass --min <percent> to enforce a line-coverage gate."
    echo "region coverage is the metric that matters for branch-heavy systems code;"
    echo "add --regions <percent> once the baseline is stable."
  else
    echo ""
    echo "== threshold =="
    fail=0
    if [ -n "$min_lines" ]; then echo "  lines:   >= $min_lines%"; fi
    if [ -n "$min_regions" ]; then echo "  regions: >= $min_regions%"; fi

    cargo llvm-cov report --json --summary-only --output-path .coverage-summary.json >/dev/null 2>&1 || true
    if [ -f .coverage-summary.json ]; then
      read_lines="$(sed -n 's/.*"lines":{"count":[0-9]*,"covered":[0-9]*,"percent":\([0-9.]*\).*/\1/p' .coverage-summary.json | head -1)"
      read_regions="$(sed -n 's/.*"regions":{"count":[0-9]*,"covered":[0-9]*,"percent":\([0-9.]*\).*/\1/p' .coverage-summary.json | head -1)"
      rm -f .coverage-summary.json

      if [ -n "$min_lines" ] && [ -n "${read_lines:-}" ]; then
        echo "  actual lines:   ${read_lines}%"
        awk -v a="$read_lines" -v m="$min_lines" 'BEGIN{exit !(a+0 < m+0)}' && { echo "  FAIL: line coverage below threshold" >&2; fail=1; }
      fi
      if [ -n "$min_regions" ] && [ -n "${read_regions:-}" ]; then
        echo "  actual regions: ${read_regions}%"
        awk -v a="$read_regions" -v m="$min_regions" 'BEGIN{exit !(a+0 < m+0)}' && { echo "  FAIL: region coverage below threshold" >&2; fail=1; }
      fi
    else
      echo "  warn: could not read the JSON summary; threshold not enforced" >&2
    fi

    [ "$fail" -eq 0 ] || exit 1
    echo "  pass"
  fi
fi

if [ "$html" -eq 1 ]; then
  echo ""
  echo "html report: target/llvm-cov/html/index.html"
fi

echo ""
echo "== coverage notes =="
echo "  region coverage > line coverage: a partially-taken branch is still a bug"
echo "  check that unsafe blocks and error paths are covered, not just happy paths"
echo "  exclude generated code with --ignore-filename-regex, never by deleting tests"
