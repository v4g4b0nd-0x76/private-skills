#!/usr/bin/env bash
# Run every quality gate in order, fastest first.
#
# Usage: check-all.sh [--with-evals]
#   --with-evals   also attempt agent-driven trigger evals (needs TRIGGER_RUNNER)
#
# Exits non-zero if any gate fails.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
with_evals=0
[ "${1:-}" = "--with-evals" ] && with_evals=1

failed=0
run_gate() {
  local label="$1"; shift
  echo ""
  echo "=============================================================="
  echo "  $label"
  echo "=============================================================="
  if "$@"; then
    echo "  -> OK"
  else
    echo "  -> FAILED"
    failed=$((failed + 1))
  fi
}

run_gate "1/5 structure (agentskills.io spec, frontmatter, links)" \
  bash "$repo_root/scripts/validate-skills.sh"

run_gate "2/5 description quality (triggering heuristics)" \
  bash "$repo_root/scripts/description-lint.sh"

run_gate "3/5 chain coverage (every devflow edge asserted)" \
  bash "$repo_root/scripts/chain-coverage.sh"

run_gate "4/5 script regression (guards, validators, generators)" \
  bash "$repo_root/scripts/script-tests.sh"

echo ""
echo "=============================================================="
echo "  5/5 research completeness (sources + verification log)"
echo "=============================================================="
research_fail=0
for d in "$repo_root"/.commandcode/skills/*/; do
  n="$(basename "${d%/}")"
  f="$repo_root/research/$n.md"
  if [ ! -f "$f" ]; then
    echo "  FAIL $n: no research log"; research_fail=$((research_fail + 1)); continue
  fi
  srcs="$(grep -cE '^\|[[:space:]]*[0-9]+[[:space:]]*\|' "$f" 2>/dev/null || true)"
  srcs="${srcs:-0}"
  urls="$(grep -oE 'https?://[^ |)]+' "$f" 2>/dev/null | sort -u | wc -l | tr -d ' ')"
  if [ "$srcs" -lt 3 ] && [ "$urls" -lt 3 ]; then
    echo "  FAIL $n: fewer than 3 sources (rows=$srcs urls=$urls)"; research_fail=$((research_fail + 1))
  fi
  if ! grep -qi 'verification\|verified\|tested' "$f"; then
    echo "  WARN $n: no verification section — was the skill ever run?"
  fi
done
if [ "$research_fail" -eq 0 ]; then echo "  -> OK"; else echo "  -> FAILED ($research_fail)"; failed=$((failed + 1)); fi

if [ "$with_evals" -eq 1 ]; then
  run_gate "6/6 trigger evals (agent-driven)" bash "$repo_root/scripts/run-trigger-evals.sh"
else
  echo ""
  echo "note: trigger evals not run (pass --with-evals). The description lint is a"
  echo "      heuristic; only real runs measure whether a skill activates."
fi

echo ""
echo "=============================================================="
if [ "$failed" -eq 0 ]; then
  echo "ALL GATES PASSED"
else
  echo "$failed GATE(S) FAILED"
fi
echo "=============================================================="
[ "$failed" -eq 0 ] || exit 1
