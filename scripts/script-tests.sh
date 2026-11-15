#!/usr/bin/env bash
# Regression tests for every skill script: the safety guards and the
# accept/reject behaviour that past bugs were found in.
#
# These are the assertions that caught real defects during development
# (unguarded greps, missing host guards, silently-passing checks). Keep them.
#
# Usage: script-tests.sh [--verbose]
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skills="$repo_root/.commandcode/skills"
verbose=0
[ "${1:-}" = "--verbose" ] && verbose=1

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

pass=0; fail=0

ok() {
  pass=$((pass + 1))
  if [ "$verbose" -eq 1 ]; then echo "  PASS  $*"; fi
  return 0
}
no() { fail=$((fail + 1)); echo "  FAIL  $*" >&2; return 0; }

# expect_exit <code> <label> <cmd...>
expect_exit() {
  local want="$1" label="$2"; shift 2
  local out; out="$("$@" 2>&1)"; local got=$?
  if [ "$got" -eq "$want" ]; then ok "$label"
  else
    no "$label (want exit $want, got $got)"
    [ "$verbose" -eq 1 ] && printf '%s\n' "$out" | head -3 | sed 's/^/        /'
  fi
}

# expect_contains <text> <label> <cmd...>
expect_contains() {
  local needle="$1" label="$2"; shift 2
  local out; out="$("$@" 2>&1 || true)"
  case "$out" in *"$needle"*) ok "$label" ;; *) no "$label (missing '$needle')" ;; esac
}

section() { echo ""; echo "== $* =="; }

# ---------------------------------------------------------------------------
section "structure: no unguarded-grep crashes (set -euo pipefail)"
# A script that greps a missing pattern must exit 0, not abort the run.
S="$work/empty"; mkdir -p "$S/src"
printf '[package]\nname = "fixture"\nversion = "0.1.0"\nedition = "2021"\n' > "$S/Cargo.toml"
echo 'fn main() {}' > "$S/src/main.rs"

if [ -x "$skills/rust-systems-perf/scripts/bugs.sh" ]; then
  expect_exit 0 "bugs.sh audit survives no unsafe/no matches" \
    bash "$skills/rust-systems-perf/scripts/bugs.sh" "$S" audit
  expect_exit 0 "bugs.sh cpu survives no target_feature" \
    bash "$skills/rust-systems-perf/scripts/bugs.sh" "$S" cpu
fi

# ---------------------------------------------------------------------------
section "safety guards: non-local targets are refused"
PSS="$skills/backend-security-test/scripts/probe.sh"
LGS="$skills/thirdparty-e2e/scripts/loadgen.sh"
FLT="$skills/thirdparty-e2e/scripts/faults.sh"

expect_exit 2 "probe.sh refuses a public host"            bash "$PSS" https://example.com --i-own-this-target
expect_exit 2 "probe.sh refuses a real API"               bash "$PSS" https://api.github.com --i-own-this-target
expect_exit 2 "probe.sh refuses a private IP"             bash "$PSS" http://10.0.0.5:8080 --i-own-this-target
expect_exit 2 "probe.sh requires ownership assertion"     bash "$PSS" http://localhost:8080
expect_exit 0 "probe.sh dry-run needs no assertion"       bash "$PSS" http://localhost:8080 --dry-run

expect_exit 2 "loadgen refuses a public host"             bash "$LGS" https://example.com --profile steady --i-own-this-target
expect_exit 2 "loadgen requires ownership assertion"      bash "$LGS" http://localhost:8080 --profile steady
expect_exit 2 "loadgen refuses a different staging host"  bash "$LGS" https://prod.myco.dev --profile steady --staging-host staging.myco.dev --i-own-this-target

expect_exit 2 "faults refuses a non-local admin API"      bash "$FLT" --toxiproxy evil.example.com:8474 --scenario down --proxy x
expect_exit 0 "faults --list touches no network"          bash "$FLT" --list

# ---------------------------------------------------------------------------
section "rendered fixtures: refuse before any network call"
# faults.sh must not probe the admin API before validating the host.
out="$(bash "$FLT" --toxiproxy evil.example.com:8474 --scenario down --proxy x 2>&1 || true)"
case "$out" in
  *REFUSED*) ok "faults refuses before probing" ;;
  *) no "faults probed before refusing" ;;
esac

# ---------------------------------------------------------------------------
section "validators: accept valid, reject invalid"
RES="$skills/devflow-research/scripts/check-research.sh"
PLAN="$skills/devflow-plan/scripts/check-plan.sh"

T="$work/chk"; mkdir -p "$T/.devflow"
cat > "$T/.devflow/research.md" <<'MD'
---
devflow: research
status: complete
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

- small

## Open questions

- none

## Sources

1. A — https://example.com/a
2. B — https://example.com/b
3. local — src/app.ts
MD
expect_exit 0 "check-research accepts a sourced artifact" bash "$RES" "$T"
sed -i.bak 's/^status: complete/status: draft/' "$T/.devflow/research.md"
expect_exit 1 "check-research rejects status draft" bash "$RES" "$T"
# Restore complete status, then strip citations from Findings
sed -i.bak 's/^status: draft/status: complete/' "$T/.devflow/research.md"
sed -i.bak 's/^- a — .*/- a invented without a source/' "$T/.devflow/research.md"
expect_exit 1 "check-research rejects unsourced findings" bash "$RES" "$T"
# Restore a valid artifact for later tests that may reuse $T
cat > "$T/.devflow/research.md" <<'MD'
---
devflow: research
status: complete
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

- small

## Open questions

- none

## Sources

1. A — https://example.com/a
2. B — https://example.com/b
3. local — src/app.ts
MD

cat > "$T/.devflow/plan.md" <<'MD'
---
devflow: plan
status: draft
upstream: .devflow/research.md
approval: pending
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

- `src/app.ts` — add x

## Test plan

- `npm test` — passes

## Risks and rollback

- revert
MD
expect_exit 0 "check-plan accepts a complete plan" bash "$PLAN" "$T"
sed -i.bak 's|^- `src/app.ts` — add x|- /absolute/path.ts — bad|' "$T/.devflow/plan.md"
expect_exit 1 "check-plan rejects absolute paths" bash "$PLAN" "$T"

# ---------------------------------------------------------------------------
section "report gates: placeholders and vague vocabulary are rejected"
BSR="$skills/backend-security-test/scripts/check-report.sh"
TPR="$skills/thirdparty-e2e/scripts/check-report.sh"

expect_exit 1 "backend report rejects its own template" bash "$BSR" "$skills/backend-security-test/assets/report.md"
expect_exit 1 "thirdparty report rejects its own template" bash "$TPR" "$skills/thirdparty-e2e/assets/report.md"

GOOD="$work/good-tp.md"
cat > "$GOOD" <<'MD'
# Third-Party E2E Report

## Third-party requirements

| Provider | Purpose | Auth | Rate limit | Fallback | Test approach |
|---|---|---|---|---|---|
| pay | charge | key | 100rps | fail | sandbox |
| mail | email | oauth | 50rps | queue | wiremock |

## Load conditions tested

- steady @100rps, degraded with 2s latency

## Unexpected behaviour

### FINDING-001 Silent success on provider outage

- **Provider:** pay
- **Severity:** Critical
- **Behaviour:** silent-success
- **Condition:** provider down under steady load
- **Reproduction:**
  ```
  1. faults.sh --scenario down
  2. loadgen.sh --profile degraded
  ```
- **Observed:** 200 with paid
- **Expected:** 503
- **Impact:** unpaid orders ship
- **Fix:** propagate provider error

## What was not tested

- soak: nightly only

## Summary

Silent success is critical.
MD
expect_exit 0 "thirdparty report accepts a complete finding" bash "$TPR" "$GOOD"
sed 's/^- \*\*Condition:\*\*.*/- **Notes:** none/' "$GOOD" > "$work/nocond.md"
expect_exit 1 "thirdparty report rejects a finding with no condition" bash "$TPR" "$work/nocond.md"
sed 's/- \*\*Fix:\*\*.*/- **Fix:** TODO/' "$GOOD" > "$work/todo.md"
expect_exit 1 "thirdparty report rejects a TODO" bash "$TPR" "$work/todo.md"

# ---------------------------------------------------------------------------
section "generators: idempotent, refuse accidental overwrite"
GEN_TP="$skills/thirdparty-e2e/scripts/gen-e2e.sh"
APP="$work/app"; mkdir -p "$APP/src"; echo '{"dependencies":{}}' > "$APP/package.json"

expect_exit 0 "gen-e2e writes a suite"        bash "$GEN_TP" "$APP"
expect_exit 1 "gen-e2e refuses to overwrite"  bash "$GEN_TP" "$APP"
expect_exit 0 "gen-e2e --force overwrites"    bash "$GEN_TP" "$APP" --force
for f in conftest.py test_contracts.py test_failures.py test_resilience.py test_degradation.py; do
  [ -f "$APP/.thirdparty/e2e/$f" ] && ok "generated $f" || no "missing $f"
done

LGEN="$skills/thirdparty-e2e/scripts/loadgen.sh"
expect_exit 0 "loadgen --generate writes profiles" bash "$LGEN" "$APP" --generate
for p in smoke steady spike soak cold-start degraded; do
  [ -f "$APP/.thirdparty/load/$p.js" ] && ok "generated profile $p" || no "missing profile $p"
done

# ---------------------------------------------------------------------------
section "generated suites: collect and refuse non-local targets"
if command -v python3 >/dev/null 2>&1; then
  if python3 -c "import pytest, requests" 2>/dev/null; then
    out="$(cd "$APP" && python3 -m pytest .thirdparty/e2e --collect-only -q 2>&1 || true)"
    case "$out" in
      *"tests collected"*|*"test collected"*) ok "generated e2e suite collects" ;;
      *) no "generated e2e suite does not collect" ;;
    esac

    out="$(cd "$APP/.thirdparty/e2e" && APP_URL=https://prod.example.com python3 -c 'import conftest' 2>&1 || true)"
    case "$out" in
      *REFUSED*) ok "generated conftest refuses a non-local target" ;;
      *) no "generated conftest accepted a non-local target" ;;
    esac
  else
    echo "  SKIP  python pytest/requests not installed"
  fi
else
  echo "  SKIP  python3 not available"
fi

# ---------------------------------------------------------------------------
section "k6 profiles: thresholds present (a profile without them proves nothing)"
for f in "$skills/thirdparty-e2e/assets/k6"/*.js; do
  if grep -q 'thresholds' "$f"; then ok "thresholds: $(basename "$f")"; else no "no thresholds: $(basename "$f")"; fi
done

# ---------------------------------------------------------------------------
section "skill hygiene: research logs and links"
for d in "$skills"/*/; do
  n="$(basename "${d%/}")"
  if [ -f "$repo_root/research/$n.md" ]; then ok "research log: $n"; else no "missing research/$n.md"; fi
done

# ---------------------------------------------------------------------------
section "installer: multi-agent targets"
INST="$repo_root/scripts/install-skills.sh"
PROJ="$work/inst"; mkdir -p "$PROJ"

expect_exit 0 "installer --list prints the matrix"     bash "$INST" --list
expect_exit 0 "installer dry-run writes nothing"       bash "$INST" "$PROJ" --agent agents,claude --dry-run
[ ! -d "$PROJ/.agents" ] && ok "dry-run left no directories" || no "dry-run created .agents/"

expect_exit 0 "installer writes shared .agents target" bash "$INST" "$PROJ" --agent agents
[ -f "$PROJ/.agents/skills/devflow/SKILL.md" ] && ok "installed .agents/skills/devflow" || no "missing .agents install"

expect_exit 0 "installer writes .claude target"        bash "$INST" "$PROJ" --agent claude
[ -f "$PROJ/.claude/skills/devflow/SKILL.md" ] && ok "installed .claude/skills/devflow" || no "missing .claude install"

expect_exit 1 "installer refuses to overwrite"         bash "$INST" "$PROJ" --agent agents
expect_exit 0 "installer --force overwrites"           bash "$INST" "$PROJ" --agent agents --force
expect_exit 1 "installer rejects an unknown agent"     bash "$INST" "$PROJ" --agent bogus
expect_exit 1 "installer rejects a missing target"     bash "$INST" "$work/nope" --agent agents

# Symlink mode must resolve (Codex and Cursor follow symlinks).
PROJ2="$work/inst-link"; mkdir -p "$PROJ2"
expect_exit 0 "installer --link succeeds"              bash "$INST" "$PROJ2" --agent agents --link
if [ -L "$PROJ2/.agents/skills/devflow" ] && head -1 "$PROJ2/.agents/skills/devflow/SKILL.md" | grep -q '^---'; then
  ok "symlinked skill resolves to a readable SKILL.md"
else
  no "symlinked skill does not resolve"
fi

# Installed copies must still satisfy the spec (name == directory, spec fields).
expect_exit 0 "installed copy passes validation" bash "$repo_root/scripts/validate-skills.sh" "$PROJ/.agents/skills"

# Native per-agent dirs stay separate when requested explicitly.
PROJ3="$work/inst-native"; mkdir -p "$PROJ3"
expect_exit 0 "installer supports native dirs"         bash "$INST" "$PROJ3" --agent codex,cursor
[ -d "$PROJ3/.codex/skills" ] && [ -d "$PROJ3/.cursor/skills" ] \
  && ok "explicit codex+cursor get separate dirs" || no "native dirs not separate"

# ---------------------------------------------------------------------------
section "arena: isolation guards, evidence gate, dedup"
ARENA="$skills/bug-bounty-arena/scripts"
AW="$work/arena-proj"; mkdir -p "$AW"; cd "$AW" || exit 1

expect_exit 0 "arena lab init creates an isolated lab"  bash "$ARENA/lab.sh" demo --init
expect_exit 0 "arena status verifies isolation"         bash "$ARENA/lab.sh" demo --status
expect_exit 2 "arm destructive without snapshot refused" bash "$ARENA/lab.sh" demo --arm-destructive

# A compose that publishes ports must be rejected.
mkdir -p "$work/badlab/.arena/bad"
sed -E 's|networks: \[arena\]|networks: [arena]\n    ports: ["3000:3000"]|' \
  "$skills/bug-bounty-arena/assets/docker-compose.yml" > "$work/badlab/.arena/bad/docker-compose.yml"
( cd "$work/badlab" && bash "$ARENA/lab.sh" bad --status >/dev/null 2>&1 )
[ $? -eq 1 ] && ok "arena status rejects published host ports" || no "published ports not rejected"

# A comment mentioning internal:true must not count as the real setting.
mkdir -p "$work/cmtlab/.arena/cmt"
printf 'services:\n  a:\n    image: x\nnetworks:\n  arena:\n    name: arena_net\n    # internal: true\n' \
  > "$work/cmtlab/.arena/cmt/docker-compose.yml"
( cd "$work/cmtlab" && bash "$ARENA/lab.sh" cmt --status >/dev/null 2>&1 )
[ $? -eq 1 ] && ok "arena status ignores a commented-out internal setting" || no "comment-only isolation accepted"

cd "$AW" || exit 1
expect_exit 0 "arena spawns hunters" bash "$ARENA/arena.sh" demo --spawn a01-bola,a02-dup

echo 'GET /basket/2 returned another user basket' > "$work/ev.txt"
expect_exit 1 "confirmed finding without evidence refused" \
  bash "$ARENA/arena.sh" demo --record a01-bola --class bola --severity high \
       --endpoint "GET /basket/2" --title "no evidence" 

expect_exit 0 "confirmed finding with evidence accepted" \
  bash "$ARENA/arena.sh" demo --record a01-bola --class bola --severity high \
       --endpoint "GET /basket/2" --title "Cross-user basket read" \
       --evidence-file "$work/ev.txt" --fingerprint missing-owner-check
expect_exit 0 "duplicate from second hunter accepted" \
  bash "$ARENA/arena.sh" demo --record a02-dup --class bola --severity critical \
       --endpoint "GET /basket/9/" --title "IDOR exposes baskets" \
       --evidence-file "$work/ev.txt" --fingerprint missing-owner-check
expect_exit 0 "destructive finding refused when unarmed" \
  bash "$ARENA/arena.sh" demo --record a01-bola --class logic --severity high \
       --status unverified --endpoint "DELETE /basket/1" --title "maybe"

# Judge must merge the two into one and keep the endpoint-normalised fingerprint.
expect_exit 0 "judge runs" bash "$ARENA/judge.sh" demo
if python3 -c '
import json,sys
d=json.load(open(".arena/demo/judged.json"))
c=d["canonical"]
assert len(c)==1, f"expected 1 merged finding, got {len(c)}"
assert c[0]["duplicate_count"]==1, "duplicate not counted"
assert len(c[0]["confirmed_by"])==2, "both hunters not credited"
' 2>/dev/null; then
  ok "judge merges same root cause across hunters"
else
  no "judge did not merge duplicates correctly"
fi

# Different verb on the same path must NOT merge.
expect_exit 0 "record different-verb finding" \
  bash "$ARENA/arena.sh" demo --record a01-bola --class bola --severity high \
       --endpoint "PATCH /basket/2" --title "Cross-user basket write" \
       --evidence-file "$work/ev.txt" --fingerprint missing-owner-check
expect_exit 0 "re-judge" bash "$ARENA/judge.sh" demo
if python3 -c '
import json
d=json.load(open(".arena/demo/judged.json"))
assert len(d["canonical"])==2, f"expected 2 (different verbs), got {len(d['canonical'])}"
' 2>/dev/null; then
  ok "judge keeps different verbs separate"
else
  no "judge collapsed different verbs"
fi

expect_exit 0 "report renders"           bash "$ARENA/report.sh" demo
expect_exit 0 "arena check passes"       bash "$ARENA/check-arena.sh" demo

# A live credential in the report must be caught.
echo 'key = "AKIAIOSFODNN7EXAMPLE"' >> .arena/demo/report.md
expect_exit 1 "arena check catches a live credential" bash "$ARENA/check-arena.sh" demo
bash "$ARENA/report.sh" demo >/dev/null 2>&1

cd "$repo_root" || exit 1

echo ""
echo "script tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
