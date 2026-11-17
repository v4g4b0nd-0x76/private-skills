#!/usr/bin/env bash
# Report whether this host is usable for sub-µs Rust campaigns.
# Usage: doctor.sh [project-root]
# Exit: 0 always when it can report; 2 on bad args. Warnings go to stderr.
set -euo pipefail

root="${1:-.}"
if [ ! -d "$root" ]; then
  echo "error: project root not found: $root" >&2
  echo "usage: doctor.sh [project-root]" >&2
  exit 2
fi

have() { command -v "$1" >/dev/null 2>&1; }
warn() { echo "WARN: $*" >&2; }

echo "== host =="
uname -srm
if have rustc; then
  rustc -vV | sed -n 's/^\(host\|release\): /  \1: /p'
else
  warn "rustc missing"
fi

cpu_model="unknown"
if [ -r /proc/cpuinfo ]; then
  cpu_model="$(awk -F: '/model name/ {gsub(/^ +/,"",$2); print $2; exit}' /proc/cpuinfo)"
elif have sysctl; then
  cpu_model="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown)"
fi
echo "  cpu: $cpu_model"

cache_line="unknown"
if [ "$(uname -s)" = "Darwin" ]; then
  cache_line="$(sysctl -n hw.cachelinesize 2>/dev/null || echo unknown)"
elif [ -r /sys/devices/system/cpu/cpu0/cache/index0/coherency_line_size ]; then
  cache_line="$(cat /sys/devices/system/cpu/cpu0/cache/index0/coherency_line_size)"
fi
echo "  cache_line_bytes: $cache_line"
case "$cache_line" in
  64) echo "  note: pad contended atomics to 128 (CachePadded); hardware line is still 64" ;;
  128) echo "  note: hardware line 128; still prefer CachePadded for shared writers" ;;
esac

echo ""
echo "== latency environment =="
gov="unknown"
turbo="unknown"
smt="unknown"
isol="unknown"
if [ -d /sys/devices/system/cpu ]; then
  if [ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
    gov="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
  fi
  if [ -r /sys/devices/system/cpu/intel_pstate/no_turbo ]; then
    case "$(cat /sys/devices/system/cpu/intel_pstate/no_turbo)" in
      1) turbo="off" ;;
      0) turbo="on" ;;
    esac
  elif [ -r /sys/devices/system/cpu/cpufreq/boost ]; then
    case "$(cat /sys/devices/system/cpu/cpufreq/boost)" in
      0) turbo="off" ;;
      1) turbo="on" ;;
    esac
  fi
  if [ -r /sys/devices/system/cpu/smt/control ]; then
    smt="$(cat /sys/devices/system/cpu/smt/control)"
  fi
  if [ -r /proc/cmdline ]; then
    isol="$(tr ' ' '\n' </proc/cmdline | grep -E '^(isolcpus|nohz_full|rcu_nocbs)=' | paste -sd' ' - || true)"
    [ -n "$isol" ] || isol="(none in /proc/cmdline)"
  fi
fi
echo "  governor: $gov"
echo "  turbo_boost: $turbo"
echo "  smt: $smt"
echo "  isolation: $isol"

[ "$gov" = "performance" ] || warn "governor is '$gov' — lock to performance before claiming ns deltas"
[ "$turbo" = "off" ] || warn "turbo is '$turbo' — frequency jitter inflates tails"
case "$isol" in
  *isolcpus*) ;;
  *) warn "no isolcpus in cmdline — expect context-switch noise in tails" ;;
esac

echo ""
echo "== tools =="
report() {
  local name="$1" purpose="$2"
  if have "$name"; then printf '  %-18s yes   # %s\n' "$name" "$purpose"
  else printf '  %-18s no    # %s\n' "$name" "$purpose"; fi
}
report perf "hardware counters + c2c (Linux)"
report cargo-asm "cargo-show-asm codegen audit"
report pahole "struct padding"
report python3 "gate.py / progress.py / persist_baseline.py"
report divan "note: crate, not a binary — use in benches/"

echo ""
echo "== project =="
if [ -f "$root/Cargo.toml" ]; then
  echo "  Cargo.toml: present"
  if grep -q 'lto' "$root/Cargo.toml" 2>/dev/null; then
    echo "  release LTO: configured (verify fat/thin manually)"
  else
    warn "no lto in Cargo.toml — copy assets/Cargo.toml.fragment.toml"
  fi
else
  warn "no Cargo.toml under $root"
fi
if [ -d "$root/.bench-history" ]; then
  echo "  .bench-history: present ($(find "$root/.bench-history" -type f | wc -l | tr -d ' ') files)"
else
  echo "  .bench-history: missing (create in Phase 2)"
fi

echo ""
echo "== json summary =="
python3 - <<PY
import json
print(json.dumps({
  "cpu_model": """$cpu_model""",
  "cache_line_bytes": """$cache_line""",
  "governor": """$gov""",
  "turbo_boost": """$turbo""",
  "smt": """$smt""",
  "kernel_isolation": """$isol""",
}, indent=2))
PY
