#!/usr/bin/env bash
# Detect and optionally run project verification gates.
# Usage: run-gates.sh [project-root] [--run]
# Without --run it only prints the commands (safe, read-only).
set -euo pipefail

root=""
run=0

for arg in "$@"; do
  case "$arg" in
    --run) run=1 ;;
    -h|--help)
      echo "usage: run-gates.sh [project-root] [--run]" >&2
      exit 1
      ;;
    -*) echo "error: unknown option '$arg'" >&2; exit 1 ;;
    *) root="$arg" ;;
  esac
done
root="${root:-.}"

if [ ! -d "$root" ]; then
  echo "error: project root not found: $root" >&2
  exit 2
fi
cd "$root"

gates=()
add() { gates+=("$1"); }

if [ -f package.json ] && command -v node >/dev/null 2>&1; then
  pm="npm"
  [ -f pnpm-lock.yaml ] && pm="pnpm"
  [ -f yarn.lock ] && pm="yarn"
  [ -f bun.lockb ] && pm="bun"
  scripts="$(node -e 'const p=require("./package.json");console.log(Object.keys(p.scripts||{}).join(" "))' 2>/dev/null || true)"
  for name in lint typecheck type-check test; do
    case " $scripts " in
      *" $name "*) add "$pm run $name" ;;
    esac
  done
  [ -f tsconfig.json ] && [ -z "${scripts##*tsc*}" ] && add "$pm exec tsc --noEmit"
fi

if [ -f go.mod ] && command -v go >/dev/null 2>&1; then
  add "go vet ./..."
  add "go test ./..."
fi

if [ -f Cargo.toml ] && command -v cargo >/dev/null 2>&1; then
  add "cargo clippy -- -D warnings"
  add "cargo test"
fi

if [ -f pyproject.toml ] || [ -f setup.py ] || [ -f requirements.txt ]; then
  command -v python3 >/dev/null 2>&1 && add "python3 -m pytest -q"
  grep -q 'ruff' pyproject.toml setup.cfg 2>/dev/null && add "python3 -m ruff check ."
fi

if [ -f Makefile ]; then
  grep -qE '^test:' Makefile && add "make test"
  grep -qE '^lint:' Makefile && add "make lint"
fi

if [ "${#gates[@]}" -eq 0 ]; then
  echo "No gate commands detected."
  echo "Use the Test plan section of .devflow/plan.md and record each command manually."
  exit 0
fi

echo "Gate commands for $root:"
for gate in "${gates[@]}"; do
  echo "  $gate"
done

if [ "$run" -eq 0 ]; then
  echo ""
  echo "Dry run only. Ask the user for approval, then re-run with --run."
  exit 0
fi

echo ""
failures=0
for gate in "${gates[@]}"; do
  echo "==> $gate"
  if bash -o pipefail -c "$gate"; then
    echo "PASS: $gate"
  else
    echo "FAIL: $gate"
    failures=$((failures + 1))
  fi
  echo ""
done

if [ "$failures" -gt 0 ]; then
  echo "$failures of ${#gates[@]} gate(s) failed" >&2
  exit 1
fi

echo "all ${#gates[@]} gate(s) passed"
