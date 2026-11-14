#!/usr/bin/env bash
# Set up and manage an isolated bug-bounty lab.
# Usage: lab.sh <lab-name> --init|--up|--down|--status|--snapshot|--arm-destructive|--restore
set -uo pipefail

skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lab="${1:-}"; shift || true
action=""

usage() {
  cat >&2 <<'EOF'
usage: lab.sh <lab-name> <action>
  --init             create the isolated lab (refuses unsafe configs)
  --up               pull images and start containers
  --down             stop and remove containers
  --status           verify isolation and print target URLs
  --snapshot         capture baseline state digests
  --arm-destructive  approve destructive techniques (requires snapshot)
  --restore          verify state against snapshot and restart
  --bootstrap        print the per-target first-run setup steps
EOF
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --init|--up|--down|--status|--snapshot|--arm-destructive|--restore|--bootstrap)
      action="${1#--}"; shift ;;
    -h|--help) usage ;;
    *) echo "error: unexpected '$1'" >&2; usage ;;
  esac
done

[ -n "$lab" ] || usage
[ -n "$action" ] || usage

arena=".arena/$lab"
compose="$arena/docker-compose.yml"

case "$action" in
  init)
    if [ -e "$arena" ]; then
      echo "error: $arena already exists (remove it to re-init)" >&2
      exit 1
    fi
    mkdir -p "$arena/hunters" "$arena/secrets"
    cp "$skill_dir/assets/docker-compose.yml" "$compose"
    cp "$skill_dir/assets/hunt-plan.md" "$arena/plan.md"
    cat > "$arena/rules.md" <<'MD'
# Rules of engagement (generated)

- Test only containers in this lab's `arena` network.
- Banned: denial of service, brute force, host escape, anything outside the lab CIDR.
- Destructive techniques require: lab.sh <lab> --snapshot, then --arm-destructive.
- Never point this lab at production data or endpoints.
- Findings require reproduction and an observed effect; status codes are not proof.

See the skill's references/rules-of-engagement.md for the full contract.
MD
    cat > "$arena/targets.json" <<'JSON'
{
  "network": "arena",
  "internal": true,
  "targets": [
    {"service": "juice-shop", "port": 3000, "url": "http://juice-shop:3000"},
    {"service": "dvwa", "port": 80, "url": "http://dvwa:80"},
    {"service": "webgoat", "port": 8080, "url": "http://webgoat:8080"},
    {"service": "dvna", "port": 9090, "url": "http://dvna:9090"}
  ]
}
JSON
    if ! grep -vE '^\s*#' "$compose" | grep -qE '^\s+internal:\s*true\s*$'; then
      echo "error: generated compose is not network-isolated; refusing" >&2
      rm -rf "$arena"
      exit 1
    fi
    if grep -vE '^\s*#' "$compose" | grep -qE '^\s+ports:'; then
      echo "error: generated compose publishes host ports; refusing" >&2
      rm -rf "$arena"
      exit 1
    fi
    printf '.arena/\n' > .gitignore.arena
    echo "created $arena"
    echo ""
    echo "safety contract satisfied:"
    echo "  - network 'arena' is internal (no outbound route)"
    echo "  - no host ports published"
    echo ""
    echo "next: lab.sh $lab --up"
    ;;

  up)
    [ -f "$compose" ] || { echo "error: run --init first" >&2; exit 2; }
    echo "== pulling images (needed before the network goes internal) =="
    docker compose -f "$compose" pull 2>&1 | tail -6
    echo ""
    echo "== starting =="
    docker compose -f "$compose" up -d 2>&1 | tail -20
    echo ""
    echo "containers started. verify with: lab.sh $lab --status"
    ;;

  down)
    [ -f "$compose" ] || { echo "error: nothing to stop" >&2; exit 2; }
    docker compose -f "$compose" down -v 2>&1 | tail -5
    echo "lab stopped and volumes removed"
    ;;

  status)
    [ -f "$compose" ] || { echo "error: run --init first" >&2; exit 2; }
    rc=0
    echo "== isolation checks =="
    # Match an actual YAML setting, not a comment mentioning it.
    if grep -vE '^\s*#' "$compose" | grep -qE '^\s+internal:\s*true\s*$'; then
      echo "  PASS  compose declares internal: true"
    else
      echo "  FAIL  compose does not set 'internal: true' on its network"; rc=1
    fi
    # 'internal: false' (or any non-true value) is an explicit failure.
    if grep -vE '^\s*#' "$compose" | grep -qE '^\s+internal:\s*(false|no|0)\s*$'; then
      echo "  FAIL  compose explicitly disables the internal network"
      rc=1
    fi
    if grep -vE '^\s*#' "$compose" | grep -qE '^\s+ports:'; then
      echo "  FAIL  compose publishes host ports (reachable from the LAN)"
      grep -nE '^\s+ports:' -A2 "$compose" | sed 's/^/        /'
      rc=1
    else
      echo "  PASS  no host ports published"
    fi

    # Runtime check: does the docker network report internal?
    netname="$(docker network ls --format '{{.Name}}' 2>/dev/null | grep -E "${lab}_arena|arena" | head -1)"
    if [ -n "$netname" ]; then
      internal="$(docker network inspect "$netname" --format '{{.Internal}}' 2>/dev/null || echo unknown)"
      if [ "$internal" = "true" ]; then
        echo "  PASS  docker network '$netname' reports Internal=true"
      else
        echo "  FAIL  docker network '$netname' Internal=$internal (should be true)"; rc=1
      fi
    else
      echo "  SKIP  lab not running yet; runtime network check skipped"
    fi

    echo ""
    echo "== targets =="
    if [ -f "$arena/targets.json" ]; then
      python3 - "$arena/targets.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print(f"  network: {d['network']} (internal={d['internal']})")
for t in d["targets"]:
    print(f"  {t['service']:12} {t['url']}")
PY
    fi
    echo ""
    if [ "$rc" -eq 0 ]; then echo "isolation verified"; else echo "ISOLATION PROBLEM — do not hunt" >&2; fi
    exit "$rc"
    ;;

  snapshot)
    [ -f "$compose" ] || { echo "error: run --init first" >&2; exit 2; }
    mkdir -p "$arena"
    python3 - "$arena/snapshot.json" <<'PY'
import hashlib, json, subprocess, sys, time
out = sys.argv[1]
data = {"taken_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "containers": {}}
try:
    ids = subprocess.run(["docker", "ps", "-q"], capture_output=True, text=True).stdout.split()
except Exception:
    ids = []
for cid in ids:
    try:
        name = subprocess.run(["docker", "inspect", cid, "--format", "{{.Name}}"],
                              capture_output=True, text=True).stdout.strip().lstrip("/")
        image = subprocess.run(["docker", "inspect", cid, "--format", "{{.Config.Image}}"],
                               capture_output=True, text=True).stdout.strip()
        digest = hashlib.sha256(f"{name}:{image}".encode()).hexdigest()[:16]
    except Exception:
        name, image, digest = cid[:12], "unknown", "unknown"
    data["containers"][name] = {"image": image, "digest": digest}
json.dump(data, open(out, "w"), indent=2)
print(f"snapshot: {len(data['containers'])} container(s) -> {out}")
PY
    if [ ! -s "$arena/secrets/.gitignore" ]; then
      printf '*\n!.gitignore\n' > "$arena/secrets/.gitignore"
    fi
    echo "snapshot captured. destructive mode may now be armed."
    ;;

  arm-destructive)
    if [ ! -f "$arena/snapshot.json" ]; then
      echo "REFUSED: no snapshot. Destructive testing requires a baseline." >&2
      echo "  run: lab.sh $lab --snapshot" >&2
      exit 2
    fi
    digest="$(shasum -a 256 "$arena/snapshot.json" 2>/dev/null | awk '{print $1}' || echo unknown)"
    {
      echo "armed_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "snapshot_digest: $digest"
      echo "approved_by: user"
    } > "$arena/DESTRUCTIVE_ARMED"
    echo "destructive mode ARMED"
    echo "  snapshot digest: $digest"
    echo "  restore with: lab.sh $lab --restore"
    ;;

  restore)
    [ -f "$compose" ] || { echo "error: nothing to restore" >&2; exit 2; }
    echo "== restoring lab =="
    docker compose -f "$compose" down -v 2>&1 | tail -3
    docker compose -f "$compose" up -d 2>&1 | tail -10
    if [ -f "$arena/DESTRUCTIVE_ARMED" ]; then
      rm -f "$arena/DESTRUCTIVE_ARMED"
      echo "destructive mode DISARMED (must be re-armed for the next run)"
    fi
    echo ""
    echo "restored. verify with: lab.sh $lab --status"
    echo "note: in-memory targets (juice-shop) are clean; DB-backed targets"
    echo "      need their own DB reset step (see --bootstrap)."
    ;;

  bootstrap)
    cat <<'BOOT'
First-run setup per target (do this before hunting, or every probe 500s):

  DVWA      http://dvwa/login.php
            login admin / password, click "Create / Reset Database"

  WebGoat   http://webgoat:8080/WebGoat/registration
            register a user

  JuiceShop http://juice-shop:3000
            register a user in the UI (no DB step)

  DVNA      http://dvna:9090
            register a user directly
BOOT
    ;;
esac
