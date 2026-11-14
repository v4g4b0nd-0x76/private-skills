#!/usr/bin/env bash
# Report the profiling/testing capabilities of this host and audit a Rust project.
# Usage: doctor.sh [project-root]
set -euo pipefail

root="${1:-.}"

if [ ! -d "$root" ]; then
  echo "error: project root not found: $root" >&2
  exit 2
fi

echo "== host =="
uname -srm
if command -v rustc >/dev/null 2>&1; then
  rustc -vV | sed -n 's/^\(host\|release\): /  \1: /p'
else
  echo "  rustc: MISSING (install via https://rustup.rs)" >&2
fi

cache_line="unknown"
if [ "$(uname -s)" = "Darwin" ]; then
  cache_line="$(sysctl -n hw.cachelinesize 2>/dev/null || echo unknown)"
elif [ -r /sys/devices/system/cpu/cpu0/cache/index0/coherency_line_size ]; then
  cache_line="$(cat /sys/devices/system/cpu/cpu0/cache/index0/coherency_line_size)"
fi

cpu_count="$( (nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null) || echo unknown)"
echo "  cpus: $cpu_count"
echo "  cache line: $cache_line bytes"

case "$cache_line" in
  64) echo "  WARN: 64-byte line is the x86 assumption; still pad to 128 or use CachePadded" ;;
  128) echo "  note: pad independently-written shared values to 128 bytes, not 64" ;;
  unknown) echo "  WARN: could not detect cache line; use CachePadded rather than a constant" ;;
esac

echo ""
echo "== tools =="
have() { command -v "$1" >/dev/null 2>&1; }
report() {
  local name="$1" purpose="$2"
  if have "$name"; then
    printf '  %-18s yes   # %s\n' "$name" "$purpose"
  else
    printf '  %-18s no    # %s\n' "$name" "$purpose"
  fi
}

report cargo-llvm-cov "coverage (cargo install cargo-llvm-cov)"
report cargo-flamegraph "flame graphs (cargo install flamegraph)"
report samply "cross-platform CPU profiler (cargo install samply)"
report perf "Linux CPU profiling + perf c2c false sharing"
report valgrind "callgrind/cachegrind/dhat/leaks (Linux)"
report heaptrack "heap timeline (Linux)"
report strace "syscall counts (Linux)"
report pahole "struct padding inspection (Linux)"
report cargo-nextest "faster test runner"
report rustfilt "symbol demangling"

echo ""
echo "== rustup =="
if have rustup; then
  rustup toolchain list 2>/dev/null | sed 's/^/  /' || true
  for comp in miri llvm-tools-preview rust-src; do
    if rustup component list --installed 2>/dev/null | grep -q "^$comp"; then
      echo "  component $comp: yes"
    else
      echo "  component $comp: no"
    fi
  done
else
  echo "  rustup: MISSING (needed for miri, llvm-tools, nightly sanitizers)" >&2
fi

echo ""
echo "== platform limits =="
case "$(uname -s)" in
  Darwin)
    if [ "$(uname -m)" = "arm64" ]; then
      echo "  valgrind: unavailable on Apple Silicon macOS -> use dhat-rs for heap data"
      echo "  perf:     unavailable -> use samply or Instruments"
      echo "  TSan:     may be unavailable on arm64 -> verify before relying on it"
    else
      echo "  perf: unavailable (Linux only) -> use samply or Instruments"
    fi
    ;;
  Linux)
    paranoid="$(cat /proc/sys/kernel/perf_event_paranoid 2>/dev/null || echo unknown)"
    echo "  perf_event_paranoid: $paranoid (values >2 block perf for non-root)"
    echo "  perf c2c: available only with perf installed and kernel support"
    ;;
  *)
    echo "  unsupported host: most profilers above will not work"
    ;;
esac

echo ""
echo "== project audit =="
if [ ! -f "$root/Cargo.toml" ]; then
  echo "  no Cargo.toml in $root — skipping source audit"
  exit 0
fi

rel_root="$(cd "$root" && pwd)"

has_profile_field() {
  awk -v want="$1" '
    /^\[profile\.release\]/ { insec = 1; next }
    /^\[/ { insec = 0 }
    insec && $0 ~ "^[[:space:]]*" want "[[:space:]]*=" { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$2"
}

echo "  release profile:"
for field in debug lto codegen-units panic; do
  if has_profile_field "$field" "$root/Cargo.toml"; then
    echo "    $field: set"
  else
    echo "    $field: MISSING (see assets/Cargo.toml.fragment.toml)"
  fi
done

scan() {
  local label="$1" pattern="$2" hint="$3"
  local out
  out="$(grep -rnE --include='*.rs' "$pattern" "$rel_root/src" 2>/dev/null | head -12 || true)"
  if [ -n "$out" ]; then
    echo ""
    echo "  $label"
    printf '%s\n' "$out" | sed 's/^/    /'
    echo "    -> $hint"
  fi
}

scan "hardcoded cache-line padding (use 128 or CachePadded)" \
  'repr\(align\((8|16|32|64)\)\)' \
  "align 64 is wrong on x86-64/aarch64 and Apple Silicon"

scan "unpadded shared atomics to review for false sharing" \
  '^(pub )?static .*Atomic|struct .*\{[^}]*Atomic' \
  "pad each independently-written value with CachePadded"

scan "unsafe blocks (need a safety comment and miri)" \
  '\bunsafe\b' \
  "run bugs.sh miri; document the invariant"

scan "target_feature without visible runtime detection" \
  'target_feature|target-cpu' \
  "add is_x86_feature_detected!/is_aarch64_feature_detected! and a scalar fallback"

scan "allocation in hot-path shapes" \
  'to_vec\(\)|to_owned\(\)|\.clone\(\)|format!\(|String::new\(\)|Vec::new\(\)' \
  "confirm with heap.sh that these are not on the hot path"

scan "unbounded growth candidates" \
  'HashMap::new\(\)|Vec::new\(\)|\.push\(' \
  "prefer with_capacity; check At t-end in dhat output"

scan "Rc/Arc cycles and leak-prone escapes" \
  'Rc<|Arc<|mem::forget|Box::leak|ManuallyDrop' \
  "break cycles with Weak; verify with heap.sh --leak"

echo ""
echo "next: profile.sh, heap.sh, coverage.sh, bugs.sh (see SKILL.md Step 5)"
