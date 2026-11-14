#!/usr/bin/env bash
# Validate that an arena run is real: proven findings, armed destructive work,
# no placeholders left in the report.
# Usage: check-arena.sh <lab>
set -uo pipefail

lab="${1:-}"
[ -n "$lab" ] || { echo "usage: check-arena.sh <lab>" >&2; exit 1; }
arena=".arena/$lab"

errors=0
fail() { echo "ERROR: $*" >&2; errors=$((errors + 1)); return 0; }
ok() { echo "  ok    $*"; }

[ -d "$arena" ] || { echo "error: no lab '$lab'" >&2; exit 2; }

echo "== arena check: $lab =="

# Lab must exist and be isolated.
[ -f "$arena/docker-compose.yml" ] || fail "missing docker-compose.yml (run lab.sh --init)"
if [ -f "$arena/docker-compose.yml" ]; then
  # Match real YAML settings, never comments that mention them.
  if grep -vE '^\s*#' "$arena/docker-compose.yml" | grep -qE '^\s+internal:\s*true\s*$'; then
    ok "network is internal"
  else
    fail "network is not internal (no active 'internal: true')"
  fi
  if grep -vE '^\s*#' "$arena/docker-compose.yml" | grep -qE '^\s+ports:'; then
    fail "compose publishes host ports"
  else
    ok "no host ports published"
  fi
fi

[ -f "$arena/plan.md" ] && ok "hunt plan present" || fail "missing plan.md"

# Hunters must have written their own files only.
hunters=0
for d in "$arena"/hunters/*/; do
  [ -d "$d" ] || continue
  hunters=$((hunters + 1))
done
[ "$hunters" -gt 0 ] && ok "$hunters hunter workspace(s)" || fail "no hunters spawned"

# Judge must have run and produced a sane result.
if [ ! -f "$arena/judged.json" ]; then
  fail "judge has not run (judge.sh $lab)"
else
  python3 - "$arena/judged.json" "$arena" <<'PY'
import json, os, sys
p, arena = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(p))
except Exception as e:
    print(f"ERROR: judged.json is not valid JSON: {e}")
    raise SystemExit(3)
errs = 0
armed = os.path.exists(os.path.join(arena, "DESTRUCTIVE_ARMED"))
for c in d.get("canonical", []):
    if c.get("confidence") == "confirmed" and not (c.get("evidence") or "").strip():
        print(f"ERROR: confirmed finding without evidence: {c.get('title')}")
        errs += 1
    if "destructive" in c.get("fingerprint", "") and not armed:
        print(f"ERROR: destructive finding without armed snapshot: {c.get('title')}")
        errs += 1
s = d.get("stats", {})
print(f"  ok    judged: {s.get('raw', 0)} raw -> {s.get('unique_confirmed', 0)} unique confirmed, "
      f"{s.get('merged_away', 0)} merged, {s.get('rejected', 0)} rejected")
raise SystemExit(1 if errs else 0)
PY
  [ $? -eq 0 ] || errors=$((errors + 1))
fi

# Report must exist and be free of template leftovers.
if [ ! -f "$arena/report.md" ]; then
  fail "no report.md (run report.sh $lab)"
else
  ok "report present"
  if grep -qE '<[A-Za-z][^>]*>' "$arena/report.md"; then
    fail "report contains unfilled <placeholders>"
  fi
  if grep -qi 'TODO\|TBD' "$arena/report.md"; then
    fail "report contains TODO/TBD"
  fi
  # Every confirmed finding must show a fingerprint.
  n_conf="$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(sum(1 for c in d["canonical"] if c["confidence"]=="confirmed"))' "$arena/judged.json" 2>/dev/null || echo 0)"
  n_fp="$(grep -c 'Fingerprint:' "$arena/report.md" 2>/dev/null || echo 0)"
  if [ "${n_conf:-0}" -gt 0 ] && [ "${n_fp:-0}" -lt "${n_conf:-0}" ]; then
    fail "report lists $n_conf confirmed finding(s) but only $n_fp fingerprint block(s)"
  fi
fi

# Secrets must never be committed or inlined in the report.
if [ -f "$arena/report.md" ] && grep -qE '(BEGIN [A-Z ]*PRIVATE KEY|sk_live_[A-Za-z0-9]{10,}|AKIA[0-9A-Z]{16})' "$arena/report.md"; then
  fail "report contains what looks like a live credential — move it to secrets/"
fi

echo ""
if [ "$errors" -eq 0 ]; then
  echo "arena check passed"
  exit 0
fi
echo "arena check failed: $errors error(s)" >&2
exit 1
