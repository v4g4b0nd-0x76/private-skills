#!/usr/bin/env bash
# Generate k6 load profiles, or run one against a local/staging target.
# Usage: loadgen.sh <app-root|url> --generate
#        loadgen.sh <url> --profile <name> --i-own-this-target
set -euo pipefail

skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target=""
generate=0
profile=""
authorized=0
staging_host=""
duration=""

usage() {
  cat >&2 <<'EOF'
usage: loadgen.sh <app-root|url> [options]
  --generate              write k6 profiles into the project
  --profile NAME          smoke | steady | spike | soak | cold-start | degraded
  --duration D            override duration (e.g. 2m, 1h)
  --i-own-this-target     required to send traffic
  --staging-host HOST     allow one exact non-local host (must be staging)

Allowed targets: localhost, 127.0.0.0/8, ::1, *.localhost, *.test,
or a host passed explicitly with --staging-host.
EOF
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --generate) generate=1; shift ;;
    --profile) profile="${2:-}"; shift 2 ;;
    --duration) duration="${2:-}"; shift 2 ;;
    --i-own-this-target) authorized=1; shift ;;
    --staging-host) staging_host="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    -*) echo "error: unknown option '$1'" >&2; usage ;;
    *) target="$1"; shift ;;
  esac
done

[ -n "$target" ] || usage

if [ "$generate" -eq 1 ]; then
  [ -d "$target" ] || { echo "error: app root not found: $target" >&2; exit 2; }
  dest="$target/.thirdparty/load"
  mkdir -p "$dest"
  for p in smoke steady spike soak cold-start degraded; do
    src="$skill_dir/assets/k6/$p.js"
    [ -f "$src" ] || { echo "error: missing assets/k6/$p.js" >&2; exit 1; }
    if [ -f "$dest/$p.js" ]; then
      echo "keep    .thirdparty/load/$p.js"
    else
      cp "$src" "$dest/$p.js"
      echo "created .thirdparty/load/$p.js"
    fi
  done
  echo ""
  echo "next: set BASE_URL and thresholds, then:"
  echo "  loadgen.sh http://localhost:8080 --profile steady --i-own-this-target"
  exit 0
fi

[[ "$target" =~ ^https?:// ]] || { echo "error: target must be a URL (http://...)" >&2; exit 1; }

host="${target#*://}"; host="${host%%/*}"; host="${host%%\?*}"; host="${host%%#*}"
host_port="$host"; host="${host%%:*}"
case "$host_port" in
  \[*\]:*) host="$(printf '%s' "$host_port" | sed 's/^\[\(.*\)\]:.*$/\1/')" ;;
  \[*\]) host="$(printf '%s' "$host_port" | tr -d '[]')" ;;
esac

is_local() {
  case "$1" in
    localhost|127.0.0.1|::1|0.0.0.0) return 0 ;;
    *.localhost|*.test) return 0 ;;
    127.*) return 0 ;;
    *) return 1 ;;
  esac
}

if ! is_local "$host"; then
  if [ -n "$staging_host" ] && [ "$host" = "$staging_host" ]; then
    echo "note: targeting explicitly approved staging host '$host'"
  else
    echo "REFUSED: '$host' is not local and was not approved with --staging-host." >&2
    echo "" >&2
    echo "Load tests cost money, can page people, and against production can cause" >&2
    echo "real outages. If this is staging you own, pass --staging-host $host" >&2
    echo "and get explicit approval before running." >&2
    exit 2
  fi
fi

case "$profile" in
  smoke|steady|spike|soak|cold-start|degraded) ;;
  "") echo "error: --profile is required to run (see --generate)" >&2; exit 1 ;;
  *) echo "error: unknown profile '$profile'" >&2; exit 1 ;;
esac

if [ "$authorized" -eq 0 ]; then
  echo "REFUSED: sending load requires --i-own-this-target." >&2
  echo "That flag asserts you own this target and have approval to load it." >&2
  exit 2
fi

if ! command -v k6 >/dev/null 2>&1; then
  echo "error: k6 is not installed" >&2
  echo "" >&2
  echo "  brew install k6        # macOS" >&2
  echo "  apt install k6         # Debian/Ubuntu (see https://k6.io/docs/get-started/installation/)" >&2
  echo "" >&2
  echo "Without k6 you can still read the generated profiles and run them elsewhere." >&2
  exit 1
fi

script="$skill_dir/assets/k6/$profile.js"
[ -f "$script" ] || { echo "error: missing profile asset $script" >&2; exit 1; }

echo "== $profile vs $target =="
echo "thresholds in the profile decide pass/fail. A run without them proves nothing."
echo ""

k6_args=(-e "BASE_URL=$target")
[ -n "$duration" ] && k6_args+=(-e "DURATION=$duration")

echo "running: k6 run ${k6_args[*]} $script"
k6 run "${k6_args[@]}" "$script"
