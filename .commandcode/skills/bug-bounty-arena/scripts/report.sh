#!/usr/bin/env bash
# Render the judged findings into a human report.
# Usage: report.sh <lab>
set -uo pipefail

lab="${1:-}"
[ -n "$lab" ] || { echo "usage: report.sh <lab>" >&2; exit 1; }
arena=".arena/$lab"
judged="$arena/judged.json"

[ -f "$judged" ] || { echo "error: run judge.sh $lab first" >&2; exit 2; }

targets="$arena/targets.json"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

python3 - "$judged" "$targets" > "$tmp" <<'PY'
import json, sys, time

data = json.load(open(sys.argv[1]))
try:
    tgt = json.load(open(sys.argv[2]))
except Exception:
    tgt = {"targets": []}

canon = data["canonical"]
stats = data["stats"]

print("# Bug Bounty Report")
print()
print(f"- **Lab:** {data['lab']}")
print(f"- **Generated:** {time.strftime('%Y-%m-%d %H:%M UTC', time.gmtime())}")
print(f"- **Targets:** {', '.join(t['service'] for t in tgt.get('targets', [])) or 'unknown'}")
print(f"- **Isolation:** internal docker network, no host ports published")
print()
print("## Summary")
print()
print(f"{stats['raw']} raw findings from all hunters collapsed to "
      f"**{stats['unique_confirmed']} unique confirmed** "
      f"({stats['merged_away']} merged as duplicates, {stats['rejected']} rejected).")
print()

top = [c for c in canon if c["severity"] in ("critical", "high")]
if top:
    print("### Act on these first")
    print()
    for c in top:
        print(f"- **{c['severity'].upper()}** — {c['title']} (`{c['endpoint']}`)")
    print()

print("## Confirmed findings")
print()
if not canon:
    print("No finding survived confirmation. That is a valid result: it means every")
    print("claim either lacked reproduction or had no observed effect.")
    print()
for i, c in enumerate(canon, 1):
    print(f"### {i}. {c['title']}")
    print()
    print(f"- **Fingerprint:** `{c['fingerprint']}`")
    print(f"- **Severity:** {c['severity']}  |  **Confidence:** {c['confidence']}  |  **Score:** {c['score']}")
    print(f"- **Target:** {c['target']}  |  **Endpoint:** `{c['endpoint']}`")
    print(f"- **Found by:** {', '.join(c['confirmed_by'])}"
          + (f"  (independent confirmation ×{len(c['confirmed_by'])})" if len(c['confirmed_by']) > 1 else ""))
    print()
    ev = (c.get("evidence") or "").strip()
    if ev:
        print("**Evidence**")
        print()
        print("```")
        print(ev[:3000])
        print("```")
    else:
        print("_No evidence block recorded._")
    print()

if data["merged"]:
    print("## Merged duplicates")
    print()
    print("Same root cause reported by multiple hunters — retained as corroboration, not as separate issues.")
    print()
    print("| Fingerprint | Hunters | Extra reports |")
    print("|---|---|---|")
    for m in data["merged"]:
        print(f"| `{m['fingerprint']}` | {', '.join(m['hunters'])} | {m['duplicates']} |")
    print()

print("## Rejected")
print()
if not data["rejected"]:
    print("None.")
else:
    print("| Hunter | Claim | Reason |")
    print("|---|---|---|")
    for r in data["rejected"]:
        title = (r.get("title") or "").replace("|", "\\|")
        reason = (r.get("reason") or "").replace("|", "\\|")
        print(f"| {r.get('hunter','')} | {title} | {reason} |")
print()

print("## Method")
print()
print("Hunters each owned one vulnerability class and wrote only their own findings.")
print("The judge rejected unproven claims, fingerprinted the rest by "
      "(class + normalised endpoint + root cause), merged duplicates, and ranked "
      "by severity × confidence × impact.")
print()
print("A finding marked `unverified` was not promoted: it needs reproduction before")
print("it is actionable. Absence of a finding is not proof of absence — see the")
print("hunter summaries for what was covered.")
PY

cp "$tmp" "$arena/report.md"
echo "report written: $arena/report.md"
echo ""
sed -n '1,12p' "$arena/report.md"
