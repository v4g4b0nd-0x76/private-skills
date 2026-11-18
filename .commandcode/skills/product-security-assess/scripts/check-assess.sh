#!/usr/bin/env bash
# Harness gate for a product-security-assess run.
# Usage: check-assess.sh <run-id>
# Exit: 0 pass, 1 fail, 2 missing workspace
set -uo pipefail

run_id="${1:-}"
[ -n "$run_id" ] || { echo "usage: check-assess.sh <run-id>" >&2; exit 1; }

root=".product-security/$run_id"
[ -d "$root" ] || { echo "error: no run '$run_id'" >&2; exit 2; }

errors=0
fail() { echo "ERROR: $*" >&2; errors=$((errors + 1)); return 0; }
ok() { echo "  ok    $*"; }

echo "== product-security-assess check: $run_id =="

[ -f "$root/roe.md" ] && ok "roe.md" || fail "missing roe.md"
[ -f "$root/targets.json" ] && ok "targets.json" || fail "missing targets.json"
[ -f "$root/phase.json" ] && ok "phase.json" || fail "missing phase.json"
[ -f "$root/RESTORE.md" ] && ok "RESTORE.md" || fail "missing RESTORE.md"

if [ -f "$root/roe.md" ]; then
  if grep -qE '^authorized:[[:space:]]*true[[:space:]]*$' "$root/roe.md"; then
    ok "ROE authorized"
  else
    fail "ROE authorized is not true"
  fi
fi

if [ -f "$root/targets.json" ]; then
  n="$(python3 -c 'import json;print(len(json.load(open("'"$root/targets.json"'")).get("hosts",[])))' 2>/dev/null || echo 0)"
  [ "${n:-0}" -gt 0 ] && ok "$n allowlisted host(s)" || fail "empty allowlist"
fi

phase="$(python3 -c 'import json;print(json.load(open("'"$root/phase.json"'"))["phase"])' 2>/dev/null || echo "")"
[ "$phase" = "report" ] && ok "phase=report" || fail "phase must be report (got '$phase')"

for f in assets.json scans/black.json scans/gray.json findings/black.jsonl findings/gray.jsonl whitebox/surface.md whitebox/gaps.md report.md; do
  [ -f "$root/$f" ] && ok "$f" || fail "missing $f"
done

if [ -f "$root/assets.json" ]; then
  if python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));raise SystemExit(0 if d.get("hosts") is not None else 1)' "$root/assets.json" 2>/dev/null; then
    ok "assets.json parseable"
  else
    fail "assets.json invalid"
  fi
fi

# Info must not appear in ranked findings
if [ -f "$root/report.md" ]; then
  if awk '
    BEGIN { bad=0 }
    /^## Ranked findings/ {r=1; next}
    /^## / {r=0}
    r && tolower($0) ~ /severity:[[:space:]]*info/ { bad=1 }
    END { exit bad ? 2 : 0 }
  ' "$root/report.md"; then
    ok "no Info in ranked findings"
  else
    fail "ranked findings contain Severity Info"
  fi
  if grep -qE '<[A-Za-z][^>]*>' "$root/report.md"; then
    fail "report contains unfilled <placeholders>"
  fi
fi

# High/Critical need evidence
if [ -f "$root/report.md" ]; then
  if python3 - "$root/report.md" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r"## Ranked findings\n(.*?)(?:\n## |\Z)", text, re.S)
body = m.group(1) if m else ""
blocks = re.split(r"\n### FINDING-\d+\n", body)
errs = 0
for b in blocks[1:]:
    sev = re.search(r"Severity:\s*(\w+)", b, re.I)
    ev = re.search(r"Evidence:\s*(.*)", b, re.I)
    if not sev:
        continue
    if sev.group(1).lower() in ("high", "critical"):
        e = (ev.group(1).strip() if ev else "")
        if not e or e.lower() in ("none", "n/a", "-"):
            print("ERROR: High/Critical finding missing evidence", file=sys.stderr)
            errs += 1
raise SystemExit(1 if errs else 0)
PY
  then
    ok "High/Critical evidence present"
  else
    errors=$((errors + 1))
  fi
fi

# Destructive gate
if [ -f "$root/DESTRUCTIVE_ARMED" ]; then
  ok "DESTRUCTIVE_ARMED present"
  if python3 - "$root/RESTORE.md" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
body = text.split("## Restore steps", 1)[-1].split("## Verification", 1)[0]
steps = re.findall(r'(?m)^\d+\.\s*(.*)$', body)
if not any(s.strip() for s in steps):
    raise SystemExit(1)
raise SystemExit(0)
PY
  then
    ok "RESTORE.md has steps"
  else
    fail "DESTRUCTIVE_ARMED but RESTORE.md has no steps"
  fi
  # scan files claiming destructive must match arm
  for s in "$root/scans/black.json" "$root/scans/gray.json"; do
    [ -f "$s" ] || continue
    dest="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("destructive", False))' "$s" 2>/dev/null || echo false)"
    if [ "$dest" = "True" ] || [ "$dest" = "true" ]; then
      ok "$(basename "$s") destructive flag consistent with arm"
    fi
  done
else
  # if any scan marks destructive true without arm → fail
  for s in "$root/scans/"*.json; do
    [ -f "$s" ] || continue
    dest="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("destructive", False))' "$s" 2>/dev/null || echo false)"
    if [ "$dest" = "True" ] || [ "$dest" = "true" ]; then
      fail "$(basename "$s") has destructive=true without DESTRUCTIVE_ARMED"
    fi
  done
fi

# Secrets must not appear in artifacts
if grep -REq '(BEGIN [A-Z ]*PRIVATE KEY|sk_live_[A-Za-z0-9]{10,}|AKIA[0-9A-Z]{16})' "$root" --include='*.md' --include='*.json' --include='*.jsonl' 2>/dev/null; then
  fail "workspace contains what looks like a live credential"
else
  ok "no inline credential patterns"
fi

echo ""
if [ "$errors" -eq 0 ]; then
  echo "assess check passed"
  exit 0
fi
echo "assess check failed: $errors error(s)" >&2
exit 1
