#!/usr/bin/env bash
# Verify every devflow chain edge behaves as documented.
# This is the "chain coverage" gate: each transition is asserted, not assumed.
#
# Usage: chain-coverage.sh
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skills="$repo_root/.commandcode/skills"
next="$skills/devflow/scripts/next.sh"
stale="$skills/devflow/scripts/mark-stale.sh"
check_research="$skills/devflow-research/scripts/check-research.sh"
check_plan="$skills/devflow-plan/scripts/check-plan.sh"
check_scope="$skills/devflow-implement/scripts/check-scope.sh"
check_diff="$skills/devflow-review/scripts/check-diff.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

pass=0
fail=0

ok() { echo "  PASS  $*"; pass=$((pass + 1)); }
no() { echo "  FAIL  $*" >&2; fail=$((fail + 1)); }

expect_first() {
  local want="$1" label="$2"; shift 2
  local got
  got="$("$@" 2>/dev/null | head -n1)"
  if [ "$got" = "$want" ]; then ok "$label"; else no "$label (want '$want', got '$got')"; fi
}

expect_exit() {
  local want="$1" label="$2"; shift 2
  "$@" >/dev/null 2>&1
  local got=$?
  if [ "$got" -eq "$want" ]; then ok "$label"; else no "$label (want exit $want, got $got)"; fi
}

# ---- fixtures ----------------------------------------------------------
P="$work/proj"
mkdir -p "$P/src" "$P/.devflow"
cd "$P" || exit 1
git init -q 2>/dev/null || true
git config user.email t@t 2>/dev/null || true
git config user.name t 2>/dev/null || true
printf 'export const x = 1;\n' > src/app.ts
printf '{"scripts":{"test":"echo ok"}}\n' > package.json
git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1

write_research() {
cat > .devflow/research.md <<MD
---
devflow: research
status: $1
upstream: none
approval: not-required
updated: 2026-11-14
---

# Research: x

## Task

Do x.

## Findings

- a — https://example.com/a
- b — src/app.ts

## Decisions

- keep small

## Open questions

- $2

## Sources

1. A — https://example.com/a
2. B — https://example.com/b
3. local — src/app.ts
MD
}

write_plan() {
local bench_env="${3:-not-required}"
local latency="${4:-false}"
cat > .devflow/plan.md <<MD
---
devflow: plan
status: $1
upstream: .devflow/research.md
approval: $2
bench_env: $bench_env
latency_campaign: $latency
updated: 2026-11-14
---

# Plan: x

## Goal

x works.

## Non-goals

- none

## Steps

1. edit src/app.ts

## Files to touch

- \`src/app.ts\` — add x

## Test plan

- \`npm test\` — suite passes

## Bench environment

$(if [ "$bench_env" = "required" ]; then cat <<'BENCH'
- Owned deps (run for real): postgres:16-alpine on localhost
- Third-party deps (simulate): payments via WireMock + Toxiproxy
- Fixture / mock data sources: recorded sandbox capture under .bench-env/fixtures/
- Isolation: dedicated compose project, localhost-only ports
- Evidence of readiness: check-bench-env.sh exit 0
BENCH
else echo "- not applicable"; fi)

## Risks and rollback

- revert src/app.ts
MD
}

write_bench_env() {
cat > .devflow/bench-env.md <<MD
---
devflow: bench-env
status: $1
upstream: .devflow/plan.md
approval: not-required
updated: 2026-11-14
---

# Bench environment: x

## Summary

- Profile active: baseline-zero
- Compose project: bench
- Evidence: check-bench-env.sh

## Owned dependencies (real)

| Service | Image/tag | Port | Health URL | Notes |
| --- | --- | --- | --- | --- |
| postgres | postgres:16-alpine | 54329 | pg_isready | |

## Third-party simulations

| Provider | Layer | Listen via | Prod-like latency source | Fixture path |
| --- | --- | --- | --- | --- |
| payments | WireMock | Toxiproxy | SLA p50=12ms | .bench-env/fixtures/charge.json |

## Mock / fixture data

- Sources: recorded sandbox
- Paths: .bench-env/fixtures/
- Uniqueness / cleanup: per-run ids

## Latency profiles

| Profile | What it sets | When to use |
| --- | --- | --- |
| baseline-zero | no delay | dual-gate |
| prod-like | SLA delays | budget share |

## Readiness

- [x] Owned services healthy
- [x] Third-party stubs loaded
- [x] check-bench-env.sh exits 0
MD
}

write_test_report() {
cat > .devflow/test-report.md <<MD
---
devflow: test
status: $1
upstream: .devflow/implement.md
approval: granted
updated: 2026-11-14
verdict: $2
---

# Test report: x

## Commands run

| # | Command | Exit | Result | Notes |
|---|---------|------|--------|-------|
| 1 | \`npm test\` | 0 | pass | |

## Goal check

- met by test

## Failures

- none

## Waivers

- none
MD
}

write_implement() {
cat > .devflow/implement.md <<MD
---
devflow: implement
status: complete
upstream: .devflow/plan.md
approval: not-required
updated: 2026-11-14
---

# Implementation: x

## Completed steps

- [x] edit src/app.ts

## Changes

- \`src/app.ts\` — x
MD
}

write_review() {
cat > .devflow/review.md <<MD
---
devflow: review
status: complete
upstream: .devflow/test-report.md
approval: not-required
updated: 2026-11-14
verdict: $1
---

# Review: x

## Summary

Reviewed.

## Findings

- none
MD
}

echo "== chain coverage: devflow =="
echo ""

echo "-- routing: forward edges --"
expect_first "NEXT: devflow-research" "no artifacts -> research" bash "$next" "$P"

write_research draft "- none"
expect_first "NEXT: devflow-research" "research draft -> stays in research" bash "$next" "$P"

write_research complete "- none"
expect_first "NEXT: devflow-plan" "research complete -> plan" bash "$next" "$P"

write_plan draft pending
expect_first "GATE: plan approval required" "plan pending -> gate" bash "$next" "$P"

write_plan approved granted
expect_first "NEXT: devflow-implement" "plan approved -> implement" bash "$next" "$P"

write_implement
expect_first "GATE: test run approval required" "implement done -> test gate" bash "$next" "$P"

write_test_report complete pass
expect_first "NEXT: devflow-review" "tests pass -> review" bash "$next" "$P"

write_review approve
expect_first "DONE" "review approve -> done" bash "$next" "$P"

echo ""
echo "-- routing: backward edges (the ones that are usually untested) --"
write_test_report draft fail
expect_first "NEXT: devflow-implement" "test fail -> back to implement" bash "$next" "$P"

# The documented contract: implement marks downstream artifacts stale before
# writing its own output. Model that here or the fixture is unrealistic.
bash "$stale" "$P" test review >/dev/null 2>&1
write_implement
write_test_report complete pass
expect_first "NEXT: devflow-review" "restored test pass -> review" bash "$next" "$P"

write_review changes-requested
expect_first "NEXT: devflow-implement" "changes requested -> back to implement" bash "$next" "$P"

bash "$stale" "$P" test review >/dev/null 2>&1
expect_first "GATE: test run approval required" "after stale, re-gate tests" bash "$next" "$P"

echo ""
echo "-- stale propagation --"
bash "$stale" "$P" research >/dev/null 2>&1
expect_first "NEXT: devflow-research" "research stale -> restart chain" bash "$next" "$P"
if grep -q '^status: stale' .devflow/review.md; then ok "mark-stale sets status"; else no "mark-stale did not set status"; fi
if ! grep -q '^verdict: approve' .devflow/review.md; then ok "mark-stale clears verdict"; else no "mark-stale left a stale verdict"; fi

echo ""
echo "-- validators: accept valid, reject invalid --"
write_research complete "- none"
expect_exit 0 "check-research accepts valid" bash "$check_research" "$P"
write_research complete "- unresolved question — BLOCKER"
expect_exit 1 "check-research rejects BLOCKER" bash "$check_research" "$P"

write_plan draft pending
expect_exit 0 "check-plan accepts valid" bash "$check_plan" "$P"
sed -i.bak 's/^## Non-goals/## Other/' .devflow/plan.md 2>/dev/null || sed -i '' 's/^## Non-goals/## Other/' .devflow/plan.md
expect_exit 1 "check-plan rejects missing Non-goals" bash "$check_plan" "$P"
write_plan draft pending

echo ""
echo "-- plan: bench_env / latency_campaign --"
write_plan draft pending required false
expect_exit 0 "check-plan accepts bench_env required" bash "$check_plan" "$P"
write_plan draft pending not-required true
expect_exit 1 "check-plan rejects latency without bench_env" bash "$check_plan" "$P"
write_plan draft pending not-required false

echo ""
echo "-- scope enforcement --"
printf 'export const x = 1;\nexport const y = 2;\n' > src/app.ts
expect_exit 0 "check-scope accepts in-scope change" bash "$check_scope" "$P"
printf 'export const z = 3;\n' > src/other.ts
expect_exit 1 "check-scope rejects out-of-scope file" bash "$check_scope" "$P"
rm -f src/other.ts

echo ""
echo "-- review diff scan --"
printf 'export const x=1;\nconst api_key = "supersecretvalue123";\n' > src/app.ts
expect_exit 1 "check-diff blocks a credential" bash "$check_diff" "$P"
printf 'export const x=1;\nexport const y=2;\n' > src/app.ts
expect_exit 0 "check-diff passes clean diff" bash "$check_diff" "$P"

echo ""
echo "-- stage scripts are reachable --"
for s in devflow/scripts/status.sh devflow/scripts/next.sh devflow/scripts/mark-stale.sh \
         devflow-research/scripts/check-research.sh devflow-plan/scripts/check-plan.sh \
         devflow-implement/scripts/check-scope.sh devflow-review/scripts/check-diff.sh \
         devflow-test/scripts/run-gates.sh; do
  if [ -x "$skills/$s" ]; then ok "executable: $s"; else no "not executable: $s"; fi
done

echo ""
echo "chain coverage: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
