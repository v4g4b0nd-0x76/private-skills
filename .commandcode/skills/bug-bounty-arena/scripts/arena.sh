#!/usr/bin/env bash
# Spawn hunters and record their findings.
# Usage: arena.sh <lab> --spawn id[,id...] | --list | --record <hunter> [...]
set -uo pipefail

skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lab="${1:-}"; shift || true
action=""

usage() {
  cat >&2 <<'EOF'
usage: arena.sh <lab> <action>
  --spawn a01-bola,a02-injection   create hunter workspaces
  --list                           show hunters and their finding counts
  --record <hunter> [options]      append a finding

record options:
  --class C          bola|injection|authn|authz|logic|leakage|other
  --severity S       critical|high|medium|low
  --endpoint E       "GET /rest/basket/2"
  --title T          one line, the effect
  --evidence-file F  file containing reproduction + observed output
  --fingerprint F    optional root-cause token, e.g. missing-owner-check
  --status S         confirmed|unverified|rejected  (default confirmed)
  --target T         target service name (default from targets.json[0])
  --destructive      mark this finding as relying on destructive technique
EOF
  exit 1
}

[ -n "$lab" ] || usage
arena=".arena/$lab"
[ -d "$arena" ] || { echo "error: no lab '$lab' (run lab.sh $lab --init)" >&2; exit 2; }

case "$lab" in
  */*|..|.) echo "error: invalid lab name" >&2; exit 1 ;;
esac

while [ "$#" -gt 0 ]; do
  case "$1" in
    --spawn|--list|--record) action="${1#--}"; shift ;;
    -h|--help) usage ;;
    *) break ;;
  esac
done

[ -n "$action" ] || usage

case "$action" in
  spawn)
    ids="${1:-}"
    [ -n "$ids" ] || { echo "error: --spawn needs a comma-separated id list" >&2; exit 1; }
    IFS=',' read -r -a list <<< "$ids"
    for id in "${list[@]}"; do
      id="$(printf '%s' "$id" | tr -d '[:space:]')"
      [ -n "$id" ] || continue
      case "$id" in
        */*|..|.) echo "error: invalid hunter id '$id'" >&2; exit 1 ;;
      esac
      d="$arena/hunters/$id"
      mkdir -p "$d"
      [ -f "$d/findings.jsonl" ] || : > "$d/findings.jsonl"
      [ -f "$d/summary.md" ] || cat > "$d/summary.md" <<MD
# Hunter $id

- Target: $(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["targets"][0]["service"])' "$arena/targets.json" 2>/dev/null || echo unknown)
- Class: ${id#*-}
- Status: not started

## Coverage

<what you tested, what you ruled out>

## Would test next

<next hypotheses if given more budget>
MD
      echo "spawned $id -> $d"
    done
    echo ""
    echo "each hunter must follow references/hunter-protocol.md and write only its own findings.jsonl"
    ;;

  list)
    echo "hunters in $arena:"
    printf '  %-16s %-12s %s\n' ID CLASS FINDINGS
    for d in "$arena"/hunters/*/; do
      [ -d "$d" ] || continue
      id="$(basename "$d")"
      n="$(grep -c . "$d/findings.jsonl" 2>/dev/null || echo 0)"
      cls="$(python3 - "$d/summary.md" <<'PY' 2>/dev/null || echo unknown
import re, sys
try:
    t = open(sys.argv[1]).read()
    m = re.search(r"^- Class: (.+)$", t, re.M)
    print(m.group(1).strip() if m else "unknown")
except Exception:
    print("unknown")
PY
)"
      printf '  %-16s %-12s %s\n' "$id" "$cls" "$n"
    done
    if [ -f "$arena/DESTRUCTIVE_ARMED" ]; then
      echo ""
      echo "  destructive mode: ARMED"
    else
      echo ""
      echo "  destructive mode: not armed (non-destructive only)"
    fi
    ;;

  record)
    hunter="${1:-}"; shift || true
    [ -n "$hunter" ] || { echo "error: --record needs a hunter id" >&2; exit 1; }
    hd="$arena/hunters/$hunter"
    [ -d "$hd" ] || { echo "error: unknown hunter '$hunter' (spawn it first)" >&2; exit 1; }

    class=""; severity=""; endpoint=""; title=""; evidence_file=""
    fingerprint=""; status="confirmed"; target=""; destructive=0

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --class) class="${2:-}"; shift 2 ;;
        --severity) severity="${2:-}"; shift 2 ;;
        --endpoint) endpoint="${2:-}"; shift 2 ;;
        --title) title="${2:-}"; shift 2 ;;
        --evidence-file) evidence_file="${2:-}"; shift 2 ;;
        --fingerprint) fingerprint="${2:-}"; shift 2 ;;
        --status) status="${2:-}"; shift 2 ;;
        --target) target="${2:-}"; shift 2 ;;
        --destructive) destructive=1; shift ;;
        -h|--help) usage ;;
        *) echo "error: unknown option '$1'" >&2; exit 1 ;;
      esac
    done

    [ -n "$class" ] || { echo "error: --class required" >&2; exit 1; }
    [ -n "$severity" ] || { echo "error: --severity required" >&2; exit 1; }
    [ -n "$title" ] || { echo "error: --title required" >&2; exit 1; }

    case "$class" in
      bola|injection|authn|authz|logic|leakage|other) ;;
      *) echo "error: --class must be bola|injection|authn|authz|logic|leakage|other" >&2; exit 1 ;;
    esac
    case "$severity" in
      critical|high|medium|low) ;;
      *) echo "error: --severity must be critical|high|medium|low" >&2; exit 1 ;;
    esac
    case "$status" in
      confirmed|unverified|rejected) ;;
      *) echo "error: --status must be confirmed|unverified|rejected" >&2; exit 1 ;;
    esac

    # Confirmed findings need evidence. Rejections do not.
    if [ "$status" = "confirmed" ] && { [ -z "$evidence_file" ] || [ ! -f "$evidence_file" ]; }; then
      echo "error: a confirmed finding requires --evidence-file that exists" >&2
      echo "       (status codes are not proof; see references/hunter-protocol.md)" >&2
      exit 1
    fi

    # Destructive findings need an armed snapshot.
    if [ "$destructive" -eq 1 ]; then
      if [ ! -f "$arena/DESTRUCTIVE_ARMED" ]; then
        echo "REFUSED: destructive finding but destructive mode is not armed." >&2
        echo "  run: lab.sh $lab --snapshot && lab.sh $lab --arm-destructive" >&2
        exit 2
      fi
    fi

    evidence=""
    [ -n "$evidence_file" ] && [ -f "$evidence_file" ] && evidence="$(cat "$evidence_file")"

    if [ -z "$target" ]; then
      target="$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["targets"][0]["service"])' "$arena/targets.json" 2>/dev/null || echo unknown)"
    fi

    python3 - "$hd/findings.jsonl" "$hunter" "$class" "$severity" "$endpoint" \
              "$title" "$fingerprint" "$status" "$target" "$destructive" "$evidence" <<'PY'
import json, sys, time
path, hunter, cls, sev, ep, title, fp, status, target, destructive, evidence = sys.argv[1:12]
rec = {
    "hunter": hunter,
    "class": cls,
    "severity": sev,
    "endpoint": ep,
    "title": title,
    "fingerprint": fp,
    "status": status,
    "target": target,
    "destructive": destructive == "1",
    "evidence": evidence,
    "recorded_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
}
with open(path, "a") as f:
    f.write(json.dumps(rec) + "\n")
print(f"recorded [{status}/{sev}] {title}")
PY
    ;;
esac
