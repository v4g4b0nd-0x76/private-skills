#!/usr/bin/env bash
# Merge findings JSONL → report.md; drop Info; dedupe by class+endpoint.
# Usage: report.sh <run-id>
# Exit: 0 ok, 1 validation, 2 safety (unauthorized / wrong phase)
set -euo pipefail

run_id="${1:-}"
[ -n "$run_id" ] || { echo "usage: report.sh <run-id>" >&2; exit 1; }

root=".product-security/$run_id"
[ -d "$root" ] || { echo "error: missing $root" >&2; exit 1; }

roe="$root/roe.md"
phase_file="$root/phase.json"

grep -qE '^authorized:[[:space:]]*true[[:space:]]*$' "$roe" 2>/dev/null \
  || { echo "REFUSED: ROE not authorized" >&2; exit 2; }

cur="$(python3 -c 'import json;print(json.load(open("'"$phase_file"'"))["phase"])' 2>/dev/null || echo "")"
case "$cur" in
  white|report) ;;
  *) echo "REFUSED: report requires white phase complete (current=$cur)" >&2; exit 2 ;;
esac

[ -f "$root/whitebox/surface.md" ] || { echo "error: missing whitebox/surface.md" >&2; exit 1; }

python3 - "$root" <<'PY'
import json, os, re, sys
from datetime import datetime, timezone

root = sys.argv[1]
findings_dir = os.path.join(root, "findings")
hosts = []
tf = os.path.join(root, "targets.json")
if os.path.isfile(tf):
    hosts = json.load(open(tf)).get("hosts", [])

def norm_sev(s):
    s = (s or "").strip().lower()
    m = {
        "critical": "Critical",
        "high": "High",
        "medium": "Medium",
        "moderate": "Medium",
        "low": "Low",
        "info": "Info",
        "informational": "Info",
        "note": "Info",
    }
    return m.get(s, "Medium")

def norm_endpoint(ep):
    ep = (ep or "").strip()
    ep = re.sub(r"/[0-9a-f]{8}-[0-9a-f-]{27,}", "/:id", ep, flags=re.I)
    ep = re.sub(r"/\d+", "/:id", ep)
    return ep

def fingerprint(f):
    return f"{(f.get('class') or '').lower()}|{norm_endpoint(f.get('endpoint'))}"

rows = []
info_rows = []
for name in ("black.jsonl", "gray.jsonl", "white.jsonl"):
    path = os.path.join(findings_dir, name)
    if not os.path.isfile(path):
        continue
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            sev = norm_sev(obj.get("severity"))
            obj["_severity"] = sev
            obj["_fp"] = fingerprint(obj)
            if sev == "Info":
                info_rows.append(obj)
            else:
                rows.append(obj)

# dedupe: keep highest severity, merge phases
order = {"Critical": 0, "High": 1, "Medium": 2, "Low": 3}
merged = {}
for r in rows:
    fp = r["_fp"]
    if fp not in merged:
        merged[fp] = r
        continue
    cur = merged[fp]
    if order.get(r["_severity"], 9) < order.get(cur["_severity"], 9):
        r["_phases"] = sorted(set([cur.get("phase"), r.get("phase"), *cur.get("_phases", [])]) - {None})
        merged[fp] = r
    else:
        phases = set(cur.get("_phases", []) or [])
        phases.add(cur.get("phase"))
        phases.add(r.get("phase"))
        cur["_phases"] = sorted(p for p in phases if p)
        # keep stronger evidence if missing
        if not (cur.get("evidence") or "").strip() and (r.get("evidence") or "").strip():
            cur["evidence"] = r["evidence"]

ranked = sorted(merged.values(), key=lambda x: (order.get(x["_severity"], 9), x.get("title") or ""))

lines = []
lines.append("# Product security assessment report")
lines.append("")
lines.append("## Scope")
lines.append("")
lines.append(f"- Run id: `{os.path.basename(root)}`")
lines.append(f"- Targets: {', '.join(hosts) if hosts else '(none)'}")
lines.append("- Phases completed: black / gray / white")
lines.append(f"- Generated: {datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}")
lines.append("")
lines.append("## What was not tested")
lines.append("")
lines.append("- Record Bright/tooling gaps here; do not invent coverage.")
lines.append("")
lines.append("## Ranked findings")
lines.append("")

if not ranked:
    lines.append("_No ranked findings (Info excluded)._")
    lines.append("")
else:
    for i, f in enumerate(ranked, 1):
        lines.append(f"### FINDING-{i}")
        lines.append("")
        lines.append(f"- Severity: {f['_severity']}")
        lines.append(f"- Class: {f.get('class') or 'unknown'}")
        lines.append(f"- Endpoint: {f.get('endpoint') or 'n/a'}")
        lines.append(f"- Title: {f.get('title') or 'untitled'}")
        lines.append(f"- Phase: {f.get('phase') or ','.join(f.get('_phases') or []) or 'n/a'}")
        lines.append(f"- Fingerprint: `{f['_fp']}`")
        lines.append(f"- Evidence: {f.get('evidence') or 'none'}")
        lines.append(f"- Confidence: {f.get('confidence') or 'unverified'}")
        lines.append(f"- Impact: {f.get('impact') or 'n/a'}")
        lines.append(f"- Fix: {f.get('fix') or 'n/a'}")
        lines.append("")

lines.append("## Info appendix (not ranked)")
lines.append("")
if not info_rows:
    lines.append("- none")
else:
    for f in info_rows:
        lines.append(f"- [{f.get('phase')}] {f.get('title') or f.get('class')} @ {f.get('endpoint') or 'n/a'}")
lines.append("")
lines.append("## Rejected candidates")
lines.append("")
lines.append("- none")
lines.append("")

out = os.path.join(root, "report.md")
open(out, "w").write("\n".join(lines))
print(f"wrote {out} ({len(ranked)} ranked, {len(info_rows)} info dropped)")
PY

# advance phase
python3 - "$root/phase.json" <<'PY'
import json, sys
from datetime import datetime, timezone
path = sys.argv[1]
d = json.load(open(path))
d["phase"] = "report"
d["updated"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
json.dump(d, open(path, "w"), indent=2)
open(path, "a").write("\n")
PY
