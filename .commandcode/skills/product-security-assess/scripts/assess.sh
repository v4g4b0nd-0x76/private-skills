#!/usr/bin/env bash
# Product security assessment workspace + phase gates.
# Exit: 0 ok, 1 usage/validation, 2 safety refusal.
# Usage: assess.sh <run-id> --init --target <host> [--extra-host <h>]...
#        assess.sh <run-id> --tools | --recon
#        assess.sh <run-id> --phase black|gray|white [--suite]
#        assess.sh <run-id> --write-restore | --arm-destructive | --status
set -euo pipefail

skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
run_id="${1:-}"
shift || true

usage() {
  cat >&2 <<'EOF'
usage: assess.sh <run-id> <action>
  --init --target <domain-or-ip> [--extra-host <h>]...
  --tools
  --recon [--skip-nuclei] [--skip-ffuf] [--skip-nmap]
  --phase black|gray|white [--suite]
  --write-restore
  --arm-destructive
  --status
EOF
  exit 1
}

[ -n "$run_id" ] || usage

action=""
target=""
extra_hosts=()
phase=""
suite=0
recon_args=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --init) action="init"; shift ;;
    --tools) action="tools"; shift ;;
    --recon) action="recon"; shift ;;
    --skip-nuclei|--skip-ffuf|--skip-nmap)
      recon_args+=("$1"); shift ;;
    --phase)
      action="phase"
      phase="${2:-}"
      shift 2 || usage
      ;;
    --suite) suite=1; shift ;;
    --write-restore) action="write-restore"; shift ;;
    --arm-destructive) action="arm-destructive"; shift ;;
    --status) action="status"; shift ;;
    --target)
      target="${2:-}"
      shift 2 || usage
      ;;
    --extra-host)
      extra_hosts+=("${2:-}")
      shift 2 || usage
      ;;
    -h|--help) usage ;;
    *) echo "error: unexpected '$1'" >&2; usage ;;
  esac
done

[ -n "$action" ] || usage

root=".product-security/$run_id"
roe="$root/roe.md"
phase_file="$root/phase.json"
targets_file="$root/targets.json"
restore_file="$root/RESTORE.md"
armed_file="$root/DESTRUCTIVE_ARMED"

refuse() { echo "REFUSED: $*" >&2; exit 2; }
die() { echo "error: $*" >&2; exit 1; }

iso_now() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

write_phase() {
  local p="$1" armed="${2:-false}"
  cat > "$phase_file" <<JSON
{
  "phase": "$p",
  "armed_destructive": $armed,
  "updated": "$(iso_now)"
}
JSON
}

roe_authorized() {
  [ -f "$roe" ] || return 1
  grep -qE '^authorized:[[:space:]]*true[[:space:]]*$' "$roe"
}

roe_field() {
  # roe_field <key>  — reads YAML-ish frontmatter key (key may contain dots)
  local key="$1"
  awk -v k="$key" '
    BEGIN { fm=0 }
    /^---[[:space:]]*$/ { fm++; next }
    fm==1 && $0 ~ ("^" k ":") {
      sub(/^[^:]+:[[:space:]]*/, "")
      gsub(/^"/, ""); gsub(/"$/, "")
      print
      exit
    }
  ' "$roe"
}

host_allowed() {
  local h="$1"
  python3 - "$targets_file" "$h" <<'PY'
import json, sys
path, host = sys.argv[1], sys.argv[2]
try:
    data = json.load(open(path))
except Exception:
    raise SystemExit(1)
hosts = {x.lower() for x in data.get("hosts", [])}
raise SystemExit(0 if host.lower() in hosts else 1)
PY
}

ensure_workspace() {
  [ -d "$root" ] || die "run --init first (missing $root)"
}

case "$action" in
  tools)
    bash "$skill_dir/scripts/ensure-tools.sh" --check \
      || bash "$skill_dir/scripts/ensure-tools.sh" --install
    ;;

  recon)
    ensure_workspace
    bash "$skill_dir/scripts/recon.sh" "$run_id" ${recon_args[@]+"${recon_args[@]}"}
    ;;

  init)
    [ -n "$target" ] || die "--init requires --target <domain-or-ip>"
    if [ -e "$root" ]; then
      die "$root already exists (remove it to re-init)"
    fi
    mkdir -p "$root/findings" "$root/scans" "$root/whitebox"
    cp "$skill_dir/assets/roe.md" "$roe"
    cp "$skill_dir/assets/restore.md" "$restore_file"
    # Inject target into Scope section
    {
      hosts_json=$(printf '%s\n' "$target" "${extra_hosts[@]+"${extra_hosts[@]}"}" | python3 -c 'import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))')
      cat > "$targets_file" <<JSON
{
  "hosts": $hosts_json,
  "created": "$(iso_now)"
}
JSON
    }
    # Annotate ROE scope with hosts
    python3 - "$roe" "$targets_file" <<'PY'
import json, sys
roe_path, targets_path = sys.argv[1], sys.argv[2]
hosts = json.load(open(targets_path))["hosts"]
text = open(roe_path).read()
bullet = "\n".join(f"- {h}" for h in hosts)
text = text.replace("- Targets: (domains / IPs / ports from init)", bullet or "- (none)")
open(roe_path, "w").write(text)
PY
    write_phase "init" false
    printf '.product-security/\n' > .gitignore.product-security 2>/dev/null || true
    echo "created $root"
    echo "hosts: $(python3 -c 'import json;print(", ".join(json.load(open("'"$targets_file"'"))["hosts"]))')"
    echo "next: set authorized: true in $roe, then --phase black"
    ;;

  status)
    ensure_workspace
    echo "run: $run_id"
    echo "root: $root"
    if [ -f "$phase_file" ]; then
      echo "phase: $(python3 -c 'import json;print(json.load(open("'"$phase_file"'"))["phase"])')"
      echo "armed: $(python3 -c 'import json;print(json.load(open("'"$phase_file"'"))["armed_destructive"])')"
    fi
    if roe_authorized; then echo "roe: authorized=true"; else echo "roe: authorized=false"; fi
    echo "hosts: $(python3 -c 'import json;print(", ".join(json.load(open("'"$targets_file"'"))["hosts"]))' 2>/dev/null || echo none)"
    [ -f "$armed_file" ] && echo "DESTRUCTIVE_ARMED: yes" || echo "DESTRUCTIVE_ARMED: no"
    cred="$(roe_field 'credentials.ref' || true)"
    code="$(roe_field 'code-root' || true)"
    echo "credentials.ref: ${cred:-"(empty)"}"
    echo "code-root: ${code:-"(empty)"}"
    ;;

  write-restore)
    ensure_workspace
    if [ ! -f "$restore_file" ]; then
      cp "$skill_dir/assets/restore.md" "$restore_file"
    fi
    echo "edit $restore_file then run --arm-destructive"
    ;;

  arm-destructive)
    ensure_workspace
    roe_authorized || refuse "ROE authorized: true required before arming destructive"
    [ -f "$restore_file" ] || refuse "missing RESTORE.md — run --write-restore first"
    # Require real content: at least one numbered step with non-empty text after "1."
    if ! python3 - "$restore_file" <<'PY'
import sys, re
text = open(sys.argv[1]).read()
# reject leftover empty template steps: lines that are just "1. " or "1."
steps = re.findall(r'(?m)^(\d+)\.\s*(.*)$', text)
filled = [s for n, s in steps if s.strip() and not s.strip().startswith("<")]
# also require baseline / health non-placeholder lines
if len(filled) < 2:
    raise SystemExit(1)
if "YYYY-MM-DD" in text and "Captured at:" in text:
    # still ok if other steps filled; only fail if restore steps empty
    pass
# fail if the three restore steps are blank in the template sense
body = text.split("## Restore steps", 1)[-1].split("## Verification", 1)[0]
step_bodies = re.findall(r'(?m)^\d+\.\s*(.*)$', body)
if not any(s.strip() for s in step_bodies):
    raise SystemExit(1)
raise SystemExit(0)
PY
    then
      refuse "RESTORE.md has no usable restore steps — fill steps before arming"
    fi
    echo "armed at $(iso_now)" > "$armed_file"
    cur="$(python3 -c 'import json;print(json.load(open("'"$phase_file"'"))["phase"])')"
    write_phase "$cur" true
    echo "destructive armed: $armed_file"
    ;;

  phase)
    ensure_workspace
    case "$phase" in
      black|gray|white) ;;
      *) die "--phase must be black|gray|white" ;;
    esac
    roe_authorized || refuse "set authorized: true in $roe before --phase $phase"
    cur="$(python3 -c 'import json;print(json.load(open("'"$phase_file"'"))["phase"])')"

    require_hosts_on_allowlist() {
      python3 - "$targets_file" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
if not d.get("hosts"):
    raise SystemExit(1)
raise SystemExit(0)
PY
      [ $? -eq 0 ] || refuse "targets.json allowlist is empty"
    }
    require_hosts_on_allowlist

    advance_ok() {
      local need="$1"
      [ "$cur" = "$need" ] || refuse "phase order: current=$cur, need completed '$need' before $phase"
    }

    case "$phase" in
      black)
        [ "$cur" = "init" ] || [ "$cur" = "black" ] || refuse "phase order: black requires init (current=$cur)"
        # Ensure skeleton artifacts exist for harness; agent fills real Bright data
        if [ ! -f "$root/assets.json" ]; then
          python3 - "$root/assets.json" "$targets_file" <<'PY'
import json, sys
out, tf = sys.argv[1], sys.argv[2]
hosts = json.load(open(tf))["hosts"]
json.dump({"hosts": hosts, "urls": [], "notes": "fill from Bright / ROE scope"}, open(out, "w"), indent=2)
open(out, "a").write("\n")
PY
        fi
        if [ ! -f "$root/scans/black.json" ]; then
          armed=false
          [ -f "$armed_file" ] && armed=true
          cat > "$root/scans/black.json" <<JSON
{
  "phase": "black",
  "authObjectId": null,
  "destructive": $armed,
  "status": "pending",
  "scanIds": [],
  "tests": []
}
JSON
        fi
        [ -f "$root/findings/black.jsonl" ] || : > "$root/findings/black.jsonl"
        write_phase "black" "$([ -f "$armed_file" ] && echo true || echo false)"
        echo "phase black ready: write Bright results into $root/scans/black.json and $root/findings/black.jsonl"
        echo "destructive_armed=$([ -f "$armed_file" ] && echo yes || echo no) — omit Bright destructive tests unless armed"
        ;;

      gray)
        [ "$cur" = "black" ] || [ "$cur" = "gray" ] || refuse "phase order: gray requires black (current=$cur)"
        [ -f "$root/scans/black.json" ] || refuse "missing black scan artifact"
        cred="$(roe_field 'credentials.ref' || true)"
        [ -n "${cred// /}" ] || refuse "roe credentials.ref is empty — required for gray"
        if [ ! -f "$root/scans/gray.json" ]; then
          armed=false
          [ -f "$armed_file" ] && armed=true
          cat > "$root/scans/gray.json" <<JSON
{
  "phase": "gray",
  "authObjectId": null,
  "destructive": $armed,
  "status": "pending",
  "scanIds": [],
  "tests": [],
  "credentials.ref": "$cred"
}
JSON
        fi
        [ -f "$root/findings/gray.jsonl" ] || : > "$root/findings/gray.jsonl"
        write_phase "gray" "$([ -f "$armed_file" ] && echo true || echo false)"
        echo "phase gray ready: set authObjectId in $root/scans/gray.json after Bright setup-auth"
        ;;

      white)
        [ "$cur" = "gray" ] || [ "$cur" = "white" ] || refuse "phase order: white requires gray (current=$cur)"
        [ -f "$root/scans/gray.json" ] || refuse "missing gray scan artifact"
        code="$(roe_field 'code-root' || true)"
        [ -n "${code// /}" ] || refuse "roe code-root is empty — required for white"
        [ -d "$code" ] || refuse "code-root is not a directory: $code"
        mkdir -p "$root/whitebox"
        if [ ! -f "$root/whitebox/surface.md" ]; then
          cat > "$root/whitebox/surface.md" <<MD
# Whitebox surface

code-root: $code

## Entry points

- (map routes / handlers)

## Identity sources

- 

## Object references

- 

## Privileged actions

- 
MD
        fi
        if [ ! -f "$root/whitebox/gaps.md" ]; then
          cat > "$root/whitebox/gaps.md" <<MD
# Whitebox gaps

Candidates only — not live exploit steps.

## Missing ownership checks

- 

## IDOR-prone object refs

- 

## Privilege boundaries

- 
MD
        fi
        if [ "$suite" -eq 1 ]; then
          mapper="$skill_dir/../backend-security-test/scripts/map-surface.sh"
          mkdir -p "$root/whitebox/suite"
          if [ -x "$mapper" ] || [ -f "$mapper" ]; then
            bash "$mapper" "$code" > "$root/whitebox/suite/map-surface.txt" 2>&1 || true
            echo "wrote map-surface output to $root/whitebox/suite/map-surface.txt"
          else
            echo "note: backend-security-test map-surface.sh not found; suite dir created empty" >&2
          fi
          # Local suite must not target live allowlisted hosts from this script
          cat > "$root/whitebox/suite/README.md" <<MD
# Local suite note

Generate and run suites only against a company-owned local/staging harness.
Do not point pytest/probe traffic at live domains from this directory unless
Bright-mediated and DESTRUCTIVE_ARMED when mutating.
MD
        fi
        [ -f "$root/findings/white.jsonl" ] || : > "$root/findings/white.jsonl"
        write_phase "white" "$([ -f "$armed_file" ] && echo true || echo false)"
        echo "phase white ready: complete $root/whitebox/surface.md and gaps.md"
        ;;
    esac
    ;;

  *) usage ;;
esac
