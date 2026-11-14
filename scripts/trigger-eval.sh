#!/usr/bin/env bash
# Measure description triggering accuracy against a labelled query set.
#
# A skill only helps if it activates. This runs each query N times and reports
# the trigger rate, then checks it against the should_trigger label.
#
# Usage: trigger-eval.sh <skill-name> [--runs N] [--threshold 0.5] [--dry-run]
#
# Requires a way to run prompts non-interactively and detect which skill loaded.
# Defaults to the `cmd` CLI; override with TRIGGER_RUNNER="your-command {{prompt}}".
# Use --dry-run to validate the query set without invoking anything.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skill="${1:-}"; shift || true
runs=3
threshold="0.5"
dry=0

usage() {
  cat >&2 <<'EOF'
usage: trigger-eval.sh <skill-name> [options]
  --runs N           repeat each query N times (default 3)
  --threshold R      trigger-rate cut-off for pass/fail (default 0.5)
  --dry-run          validate the query set only; run nothing
EOF
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --runs) runs="${2:-3}"; shift 2 ;;
    --threshold) threshold="${2:-0.5}"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    -h|--help) usage ;;
    *) echo "error: unexpected '$1'" >&2; usage ;;
  esac
done

[ -n "$skill" ] || usage

queries="$repo_root/evals/$skill/eval_queries.json"
[ -f "$queries" ] || {
  echo "error: no query set at evals/$skill/eval_queries.json" >&2
  echo "" >&2
  echo "Write 16-20 queries: 8-10 should_trigger=true, 8-10 false." >&2
  echo "Include near-misses that share keywords but need a different skill." >&2
  exit 2
}

command -v python3 >/dev/null 2>&1 || { echo "error: python3 required" >&2; exit 1; }

# --- validate the query set ------------------------------------------------
summary="$(python3 - "$queries" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception as e:
    print(f"INVALID {e}"); raise SystemExit(1)
pos = sum(1 for q in data if q.get("should_trigger") is True)
neg = sum(1 for q in data if q.get("should_trigger") is False)
bad = [q for q in data if "query" not in q or "should_trigger" not in q]
print(f"TOTAL {len(data)} POS {pos} NEG {neg} BAD {len(bad)}")
PY
)"

case "$summary" in
  INVALID*) echo "error: $summary" >&2; exit 1 ;;
esac

total="$(printf '%s' "$summary" | sed -n 's/.*TOTAL \([0-9]*\).*/\1/p')"
pos="$(printf '%s' "$summary" | sed -n 's/.*POS \([0-9]*\).*/\1/p')"
neg="$(printf '%s' "$summary" | sed -n 's/.*NEG \([0-9]*\).*/\1/p')"
bad="$(printf '%s' "$summary" | sed -n 's/.*BAD \([0-9]*\).*/\1/p')"

echo "== trigger eval: $skill =="
echo "queries: $total ($pos should-trigger, $neg should-not)"

status=0
[ "$bad" -eq 0 ] || { echo "ERROR: $bad malformed queries" >&2; status=1; }
[ "$pos" -ge 8 ] || { echo "ERROR: need >=8 should-trigger queries (have $pos)" >&2; status=1; }
[ "$neg" -ge 8 ] || { echo "ERROR: need >=8 should-not-trigger queries (have $neg)" >&2; status=1; }
[ "$total" -ge 16 ] || { echo "ERROR: need >=16 queries total (have $total)" >&2; status=1; }

# A query set with no near-misses tests nothing; look for keyword overlap.
near="$(python3 - "$queries" <<'PY'
import json, sys, re
data = json.load(open(sys.argv[1]))
pos = [q["query"].lower() for q in data if q.get("should_trigger")]
neg = [q["query"].lower() for q in data if not q.get("should_trigger")]
def words(s): return set(re.findall(r"[a-z]{4,}", s))
shared = 0
for n in neg:
    nw = words(n)
    if any(nw & words(p) for p in pos):
        shared += 1
print(shared)
PY
)"
echo "near-miss negatives (share a keyword with a positive): $near"
[ "${near:-0}" -ge 3 ] || echo "WARN: fewer than 3 near-miss negatives — the set is too easy"

if [ "$dry" -eq 1 ]; then
  echo ""
  echo "dry run: query set validated, nothing executed."
  exit "$status"
fi

runner="${TRIGGER_RUNNER:-}"
if [ -z "$runner" ]; then
  echo "" >&2
  echo "error: no TRIGGER_RUNNER configured." >&2
  echo "" >&2
  echo "Set a command that runs one prompt and reports whether the skill loaded:" >&2
  echo "  export TRIGGER_RUNNER='cmd run --print-transcript {{prompt}}'" >&2
  echo "" >&2
  echo "The output must contain the skill name when the skill was invoked." >&2
  echo "Without a runner this harness can validate the query set but not measure" >&2
  echo "triggering. Use --dry-run for that." >&2
  exit 1
fi

echo ""
echo "runs per query: $runs, threshold: $threshold"
echo ""

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

python3 - "$queries" > "$tmp/queries.tsv" <<'PY'
import json, sys
for i, q in enumerate(json.load(open(sys.argv[1]))):
    q["query"].replace("\t", " ").replace("\n", " ")
    print(f"{i}\t{int(bool(q['should_trigger']))}\t{q['query'].replace(chr(9),' ').replace(chr(10),' ')}")
PY

failures=0
while IFS="$(printf '\t')" read -r idx should q; do
  [ -n "${idx:-}" ] || continue
  hits=0
  for _ in $(seq 1 "$runs"); do
    cmd="${runner//\{\{prompt\}\}/$q}"
    out="$(eval "$cmd" 2>/dev/null || true)"
    case "$out" in *"$skill"*) hits=$((hits + 1)) ;; esac
  done
  rate="$(awk -v h="$hits" -v r="$runs" 'BEGIN{printf "%.2f", h/r}')"
  verdict="$(awk -v rate="$rate" -v want="$should" -v t="$threshold" 'BEGIN{
    trig = (rate+0 >= t+0) ? 1 : 0
    print (trig == want) ? "PASS" : "FAIL"
  }')"
  printf '%-4s should=%s rate=%s  %s\n' "$verdict" "$should" "$rate" "$(printf '%s' "$q" | cut -c1-70)"
  [ "$verdict" = "FAIL" ] && failures=$((failures + 1))
done < "$tmp/queries.tsv"

echo ""
echo "failed queries: $failures"
[ "$failures" -eq 0 ] || status=1
exit "$status"
