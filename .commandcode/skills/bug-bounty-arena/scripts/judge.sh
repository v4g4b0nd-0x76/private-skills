#!/usr/bin/env bash
# Judge all hunter findings: reject unproven, deduplicate by root cause, rank.
# Usage: judge.sh <lab> [--dry-run]
set -uo pipefail

lab="${1:-}"; shift || true
dry=0
[ "${1:-}" = "--dry-run" ] && dry=1

[ -n "$lab" ] || { echo "usage: judge.sh <lab> [--dry-run]" >&2; exit 1; }
arena=".arena/$lab"
[ -d "$arena" ] || { echo "error: no lab '$lab'" >&2; exit 2; }

files=("$arena"/hunters/*/findings.jsonl)
if [ ! -e "${files[0]}" ]; then
  echo "no hunter findings to judge" >&2
  exit 2
fi

python3 - "$arena" "$dry" "$lab" <<'PY'
import json, os, re, sys, glob

arena, dry, lab = sys.argv[1], sys.argv[2] == "1", sys.argv[3]

SEV = {"critical": 4, "high": 3, "medium": 2, "low": 1}
CONF = {"confirmed": 1.0, "unverified": 0.4}
IMPACT = {"takeover": 1.0, "authz-bypass": 1.0, "data-read": 0.8, "logic-abuse": 0.7, "info-leak": 0.5}

def norm_endpoint(ep):
    if not ep:
        return ""
    parts = ep.strip().split(None, 1)
    method = parts[0].upper() if parts else ""
    path = parts[1] if len(parts) > 1 else ""
    path = path.split("?")[0]
    path = re.sub(r"/+", "/", path).rstrip("/")
    # identifiers -> :id  (numeric, uuid, long hex)
    path = re.sub(r"/\d+(?=/|$)", "/:id", path)
    path = re.sub(r"/[0-9a-fA-F]{8}-[0-9a-fA-F-]{27,}(?=/|$)", "/:id", path)
    path = re.sub(r"/[0-9a-fA-F]{16,}(?=/|$)", "/:id", path)
    return f"{method} {path}".strip()

def infer_root_cause(rec):
    if rec.get("fingerprint"):
        return rec["fingerprint"]
    t = (rec.get("title", "") + " " + rec.get("class", "")).lower()
    rules = [
        (r"owner|another user|other user|cross-user|idor|bola", "missing-owner-check"),
        (r"tenant|organization|workspace", "missing-tenant-scope"),
        (r"admin|role|privilege|escalat", "trusted-client-role"),
        (r"sql|injection|concat", "unsanitized-query"),
        (r"token|jwt|signature|alg", "weak-token-validation"),
        (r"session|cookie|logout|expire", "session-lifecycle"),
        (r"delete|corrupt|overwrit", "unchecked-state-change"),
        (r"leak|expos|over-fetch|internal", "unfiltered-response"),
        (r"balance|quota|coupon|price|refund", "missing-invariant-check"),
        (r"race|concurr|double", "toctou"),
    ]
    for pat, name in rules:
        if re.search(pat, t):
            return name
    return "unspecified"

def impact_of(rec):
    t = (rec.get("title", "") + " " + rec.get("class", "") + " " + (rec.get("evidence") or "")).lower()
    # Ordered: the first match wins, so put the most severe framing first.
    if re.search(r"takeover|admin session|escalat|credential|password dump|password recovered", t):
        return IMPACT["takeover"]
    if re.search(r"sql injection|injection|union select|command injection|rce|deserial", t):
        return IMPACT["authz-bypass"]
    if re.search(r"owner|another user|cross-user|tenant|authoriz|bola|idor", t):
        return IMPACT["authz-bypass"]
    if re.search(r"read|expos|leak|dump|enumerat", t):
        return IMPACT["data-read"]
    if re.search(r"logic|invariant|quota|coupon|refund|balance|corrupt", t):
        return IMPACT["logic-abuse"]
    return IMPACT["info-leak"]

raw = []
for path in sorted(glob.glob(os.path.join(arena, "hunters", "*", "findings.jsonl"))):
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            rec["_file"] = path
            raw.append(rec)

rejected, candidates = [], []
for rec in raw:
    if rec.get("status") == "rejected":
        rec["reason"] = "recorded as a rejected hypothesis"
        rejected.append(rec)
        continue
    problems = []
    if rec.get("status") == "unverified":
        problems.append("unverified")
    if rec.get("status") == "confirmed" and not (rec.get("evidence") or "").strip():
        problems.append("confirmed without evidence")
    if rec.get("destructive") and not os.path.exists(os.path.join(arena, "DESTRUCTIVE_ARMED")):
        problems.append("destructive without armed snapshot")
    if not rec.get("endpoint"):
        problems.append("no endpoint")
    if problems:
        rec["reason"] = "; ".join(problems)
        rejected.append(rec)
    else:
        candidates.append(rec)

# Fingerprint: class | normalised endpoint | root cause
groups = {}
for rec in candidates:
    fp = "|".join([
        rec.get("class", "other"),
        norm_endpoint(rec.get("endpoint", "")),
        infer_root_cause(rec),
    ])
    groups.setdefault(fp, []).append(rec)

canonical = []
for fp, recs in groups.items():
    best = max(recs, key=lambda r: (SEV.get(r.get("severity"), 0), len(r.get("evidence") or "")))
    hunters = sorted({r["hunter"] for r in recs})
    sev = max((r.get("severity") for r in recs), key=lambda s: SEV.get(s, 0))
    confidence = "confirmed" if any(r.get("status") == "confirmed" for r in recs) else "unverified"
    score = SEV.get(sev, 1) * CONF.get(confidence, 0.4) * impact_of(best)
    canonical.append({
        "fingerprint": fp,
        "title": best.get("title", ""),
        "class": best.get("class", ""),
        "severity": sev,
        "confidence": confidence,
        "target": best.get("target", ""),
        "endpoint": best.get("endpoint", ""),
        "evidence": best.get("evidence", ""),
        "confirmed_by": hunters,
        "duplicate_count": len(recs) - 1,
        "score": round(score, 2),
    })

canonical.sort(key=lambda c: (-c["score"], c["title"]))

merged = [
    {"fingerprint": c["fingerprint"], "hunters": c["confirmed_by"], "duplicates": c["duplicate_count"]}
    for c in canonical if c["duplicate_count"] > 0
]

result = {
    "lab": lab,
    "canonical": canonical,
    "merged": merged,
    "rejected": [
        {"hunter": r.get("hunter"), "title": r.get("title"), "reason": r.get("reason", "")}
        for r in rejected
    ],
    "stats": {
        "raw": len(raw),
        "unique_confirmed": sum(1 for c in canonical if c["confidence"] == "confirmed"),
        "unique_total": len(canonical),
        "merged_away": sum(c["duplicate_count"] for c in canonical),
        "rejected": len(rejected),
    },
}

if dry:
    print(json.dumps(result["stats"], indent=2))
    sys.exit(0)

out = os.path.join(arena, "judged.json")
with open(out, "w") as f:
    json.dump(result, f, indent=2)

s = result["stats"]
print(f"judged {s['raw']} raw finding(s)")
print(f"  unique confirmed : {s['unique_confirmed']}")
print(f"  unique total     : {s['unique_total']}")
print(f"  merged as dupes  : {s['merged_away']}")
print(f"  rejected         : {s['rejected']}")
print("")
print("ranked:")
for c in canonical:
    tag = "confirmed" if c["confidence"] == "confirmed" else c["confidence"]
    extra = f"  (+{c['duplicate_count']} dup)" if c["duplicate_count"] else ""
    print(f"  {c['score']:>4}  {c['severity']:<8} {tag:<9} {c['title']}{extra}")
if not canonical:
    print("  (none — no finding survived confirmation)")
print("")
print(f"written: {out}")
PY
