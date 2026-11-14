#!/usr/bin/env bash
# Run systems-level correctness checks: UB, data races, leaks, CPU features, unsafe policy.
# Usage: bugs.sh [project-root] [--all] [miri] [loom] [tsan] [asan] [leaks] [cpu] [audit]
set -euo pipefail

root="."
mode=""

usage() {
  cat >&2 <<'EOF'
usage: bugs.sh [project-root] [--all] [miri] [loom] [tsan] [asan] [leaks] [cpu] [audit]
  miri   undefined behavior, provenance, races (nightly, unsafe code)
  loom   exhaustive thread-interleaving exploration (needs cfg(loom) setup)
  tsan   ThreadSanitizer data-race detection (nightly)
  asan   AddressSanitizer memory errors (nightly)
  leaks  leak detection (valgrind, or dhat guidance)
  cpu    CPU-feature portability audit of target_feature/target-cpu usage
  audit  unsafe-block inventory and policy check
  --all  every check available on this host
EOF
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --all) mode="all"; shift ;;
    miri|loom|tsan|asan|leaks|cpu|audit) mode="$1"; shift ;;
    -h|--help) usage ;;
    -*) echo "error: unknown option '$1'" >&2; usage ;;
    *) root="$1"; shift ;;
  esac
done

[ -n "$mode" ] || usage

if [ ! -f "$root/Cargo.toml" ]; then
  echo "error: no Cargo.toml in $root" >&2
  exit 2
fi

cd "$root"

skipped=0
failed=0
ran=0

host_triple() { rustc -vV 2>/dev/null | sed -n 's/^host: //p'; }

note_skip() { echo "SKIP: $*"; skipped=$((skipped + 1)); }
note_fail() { echo "FAIL: $*" >&2; failed=$((failed + 1)); }

has_nightly() { rustup toolchain list 2>/dev/null | grep -q '^nightly'; }

check_miri() {
  echo ""
  echo "== miri (UB / provenance / races) =="
  if ! has_nightly; then
    note_skip "miri needs nightly (rustup toolchain install nightly)"
    return
  fi
  if ! rustup +nightly component list --installed 2>/dev/null | grep -q '^miri'; then
    note_skip "miri component missing (rustup +nightly component add miri)"
    return
  fi
  ran=$((ran + 1))
  if cargo +nightly miri test 2>&1 | tail -25; then
    echo "PASS: miri found no UB in the exercised code"
  else
    note_fail "miri reported UB — treat every report as a real bug"
  fi
}

check_loom() {
  echo ""
  echo "== loom (thread interleavings) =="
  if ! grep -rq 'loom' Cargo.toml 2>/dev/null; then
    note_skip "loom is not a dependency; add it under [target.'cfg(loom)'.dependencies]"
    return
  fi
  if ! grep -rq 'cfg(loom)' src tests 2>/dev/null; then
    note_skip "no cfg(loom) type switch found; loom would see nothing (see references/testing.md)"
    return
  fi
  ran=$((ran + 1))
  echo "running with LOOM_MAX_PREEMPTIONS=${LOOM_MAX_PREEMPTIONS:-3}"
  if LOOM_MAX_PREEMPTIONS="${LOOM_MAX_PREEMPTIONS:-3}" RUSTFLAGS="--cfg loom" \
      cargo test --release 2>&1 | tail -25; then
    echo "PASS: loom found no violation within the explored interleavings"
    echo "note: loom cannot model all Relaxed reorderings; a pass is not a proof"
  else
    note_fail "loom found a concurrency violation"
  fi
}

sanitizer() {
  local name="$1" tool="$2"
  echo ""
  echo "== $name =="
  if ! has_nightly; then
    note_skip "$name needs nightly"
    return
  fi
  local target
  target="$(host_triple)"
  if [ -z "$target" ]; then
    note_skip "could not determine host triple"
    return
  fi
  if [ "$(uname -s)" = "Darwin" ] && [ "$(uname -m)" = "arm64" ] && [ "$tool" = "thread" ]; then
    note_skip "ThreadSanitizer is unreliable on Apple Silicon; run this on Linux CI"
    return
  fi
  ran=$((ran + 1))
  if RUSTFLAGS="-Zsanitizer=$tool" cargo +nightly -Zbuild-std test --target "$target" 2>&1 | tail -25; then
    echo "PASS: $name clean on the exercised paths"
  else
    note_fail "$name reported an error"
  fi
}

check_leaks() {
  echo ""
  echo "== leaks =="
  if command -v valgrind >/dev/null 2>&1; then
    ran=$((ran + 1))
    local bin
    bin="$(find target/release -maxdepth 1 -type f -perm -111 ! -name '*.so' ! -name '*.d' 2>/dev/null | head -1 || true)"
    if [ -z "$bin" ]; then
      note_skip "no release binary built (cargo build --release first)"
      return
    fi
    if valgrind --leak-check=full --errors-for-leak-kinds=definite --error-exitcode=1 "$bin" 2>&1 | tail -20; then
      echo "PASS: no definite leaks"
    else
      note_fail "valgrind reported leaks"
    fi
  else
    note_skip "valgrind unavailable (Apple Silicon macOS) — run heap.sh --leak with dhat-rs"
  fi
}

check_cpu() {
  echo ""
  echo "== cpu features =="
  ran=$((ran + 1))
  local hits
  hits="$(grep -rnE --include='*.rs' 'target_feature|target-cpu' src 2>/dev/null || true)"

  if [ -z "$hits" ]; then
    echo "PASS: no target_feature/target-cpu usage in src/"
  else
    echo "$hits" | sed 's/^/  /'
    echo ""
    local detected
    detected="$(grep -rnE --include='*.rs' 'is_x86_feature_detected|is_aarch64_feature_detected|cfg\(target_feature' src 2>/dev/null || true)"
    if [ -z "$detected" ]; then
      note_fail "target_feature used without runtime detection — this breaks on other CPUs"
      echo "  add is_x86_feature_detected!/is_aarch64_feature_detected! and a scalar fallback" >&2
    else
      echo "runtime detection found:"
      echo "$detected" | sed 's/^/  /'
      echo "verify a scalar fallback path exists and is tested"
    fi
  fi

  local build_cfg=""
  for cfg in .cargo/config.toml .cargo/config Cargo.toml; do
    if [ -f "$cfg" ]; then
      build_cfg="$build_cfg $cfg"
    fi
  done

  if [ -n "$build_cfg" ] && grep -l 'target-cpu=native' $build_cfg >/dev/null 2>&1; then
    note_fail "target-cpu=native in build config — binaries will crash on older CPUs"
  fi

  local flags=""
  flags="$(grep -rn 'target-cpu' .cargo 2>/dev/null || true)"
  if [ -n "$flags" ]; then
    echo "build config cpu flags:"
    echo "$flags" | sed 's/^/  /'
  fi
}

check_audit() {
  echo ""
  echo "== unsafe audit =="
  ran=$((ran + 1))
  local count
  count="$( { grep -rcE --include='*.rs' '\bunsafe\b' src 2>/dev/null || true; } | awk -F: '{s+=$2} END {print s+0}')"
  count="${count:-0}"
  echo "unsafe mentions in src/: $count"

  if [ "$count" -eq 0 ]; then
    echo "PASS: no unsafe in src/"
    return 0
  fi

  local files
  files="$(find src -name '*.rs' 2>/dev/null || true)"
  local undocumented=""
  if [ -n "$files" ]; then
    # shellcheck disable=SC2086
    undocumented="$(awk '
      /unsafe/ {
        if (prev !~ /SAFETY:|safety:/) { print FILENAME ":" FNR ": " $0 }
      }
      { prev = $0 }
    ' $files 2>/dev/null | head -15 || true)"
  fi

  if [ -n "$undocumented" ]; then
    echo "unsafe blocks without a preceding SAFETY comment:"
    echo "$undocumented" | sed 's/^/  /'
    note_fail "every unsafe block must state the invariant it relies on in a SAFETY comment"
  else
    echo "PASS: every unsafe block has a SAFETY comment"
  fi

  echo ""
  echo "clippy (unsafe-relevant lints):"
  cargo clippy --quiet -- -W clippy::undocumented_unsafe_blocks 2>&1 | tail -10 || true
}

case "$mode" in
  miri) check_miri ;;
  loom) check_loom ;;
  tsan) sanitizer "thread sanitizer" "thread" ;;
  asan) sanitizer "address sanitizer" "address" ;;
  leaks) check_leaks ;;
  cpu) check_cpu ;;
  audit) check_audit ;;
  all)
    check_audit
    check_cpu
    check_leaks
    check_miri
    check_loom
    sanitizer "address sanitizer" "address"
    sanitizer "thread sanitizer" "thread"
    ;;
esac

echo ""
echo "== summary =="
echo "  ran: $ran  failed: $failed  skipped: $skipped"
if [ "$skipped" -gt 0 ]; then
  echo "  skipped checks are NOT passes; record why in .devflow/test-report.md"
fi
if [ "$failed" -gt 0 ]; then
  exit 1
fi
