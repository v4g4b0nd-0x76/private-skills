#!/usr/bin/env bash
# Heap analytics for a Rust project: allocation sites, peak, and leaks.
# Usage: heap.sh [project-root] [--bin NAME] [--leak] [--tool dhat-rs|valgrind|heaptrack]
set -euo pipefail

root="."
bin_name=""
leak_mode=0
tool="auto"

usage() {
  cat >&2 <<'EOF'
usage: heap.sh [project-root] [options]
  --bin NAME     binary target (default: package default)
  --leak         leak-focused run (valgrind --leak-check=full when available)
  --tool NAME    dhat-rs | valgrind | heaptrack (default: best available)
EOF
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --bin) bin_name="${2:-}"; shift 2 ;;
    --leak) leak_mode=1; shift ;;
    --tool) tool="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    -*) echo "error: unknown option '$1'" >&2; usage ;;
    *) root="$1"; shift ;;
  esac
done

if [ ! -f "$root/Cargo.toml" ]; then
  echo "error: no Cargo.toml in $root" >&2
  exit 2
fi

cd "$root"

target_dir="$(
  cargo metadata --format-version 1 --no-deps 2>/dev/null \
    | sed -n 's/.*"target_directory":"\([^"]*\)".*/\1/p'
)"
target_dir="${target_dir:-target}"

have_crossbeam_padded() {
  grep -q 'crossbeam-utils' Cargo.toml 2>/dev/null
}

dhat_is_wired() {
  echo ""
  echo "== wiring dhat-rs =="
  if [ -f src/main.rs ] && grep -q 'dhat' src/main.rs; then
    echo "  src/main.rs already references dhat — leaving it alone"
    return 0
  fi

  echo "  dhat needs a global allocator + a profiler guard in main."
  echo "  Copy assets/dhat-harness.rs into your binary and add to Cargo.toml:"
  echo ""
  echo "    [dependencies]"
  echo '    dhat = { version = "0.3", optional = true }'
  echo ""
  echo "    [features]"
  echo '    dhat-heap = ["dep:dhat"]'
  echo ""
  echo "    [profile.release]"
  echo "    debug = 1"
  echo ""
  echo "  This script does not modify your source; the hook must be intentional."
  return 1
}

if [ "$tool" = "auto" ]; then
  if [ "$leak_mode" -eq 1 ] && command -v valgrind >/dev/null 2>&1; then
    tool="valgrind"
  elif command -v valgrind >/dev/null 2>&1; then
    tool="valgrind"
  elif command -v heaptrack >/dev/null 2>&1; then
    tool="heaptrack"
  else
    tool="dhat-rs"
  fi
fi

echo "selected tool: $tool"
have_crossbeam_padded && echo "note: crossbeam-utils present — check CachePadded padding width"

case "$tool" in
  valgrind)
    if ! command -v valgrind >/dev/null 2>&1; then
      echo "error: valgrind unavailable on this host" >&2
      echo "on Apple Silicon macOS use --tool dhat-rs instead" >&2
      exit 1
    fi
    cargo build --release ${bin_name:+--bin "$bin_name"} 2>&1 | tail -3
    bin_path=""
    if [ -n "$bin_name" ]; then
      bin_path="$target_dir/release/$bin_name"
    else
      bin_path="$(find "$target_dir/release" -maxdepth 1 -type f -perm -111 ! -name '*.d' ! -name '*.so' ! -name '*.rlib' 2>/dev/null | head -1)"
    fi
    [ -x "${bin_path:-}" ] || { echo "error: binary not found; pass --bin <name>" >&2; exit 1; }

    if [ "$leak_mode" -eq 1 ]; then
      echo ""
      echo "== valgrind leak check =="
      valgrind --leak-check=full --show-leak-kinds=all --error-exitcode=1 "$bin_path"
    else
      echo ""
      echo "== valgrind dhat (allocation sites) =="
      valgrind --tool=dhat "$bin_path"
      echo ""
      echo "open dhat.out in https://nnethercote.github.io/dh_view/dh_view.html"
    fi
    ;;

  heaptrack)
    cargo build --release ${bin_name:+--bin "$bin_name"} 2>&1 | tail -3
    bin_path="$target_dir/release/${bin_name:-$(find "$target_dir/release" -maxdepth 1 -type f -perm -111 ! -name '*.so' -exec basename {} \; | head -1)}"
    [ -x "$bin_path" ] || { echo "error: binary not found; pass --bin <name>" >&2; exit 1; }
    echo ""
    echo "== heaptrack =="
    heaptrack "$bin_path"
    echo "analyze with: heaptrack_gui heaptrack.$(basename "$bin_path").*.zstd"
    ;;

  dhat-rs)
    if dhat_is_wired; then
      echo ""
      echo "== running dhat-rs profiler =="
      cargo run --release --features dhat-heap ${bin_name:+--bin "$bin_name"}
      echo ""
      if [ -f dhat-heap.json ]; then
        echo "output: dhat-heap.json"
        echo "open:   https://nnethercote.github.io/dh_view/dh_view.html"
        echo ""
        echo "look at:"
        echo "  Total        allocation traffic — the rate to reduce"
        echo "  At t-gmax    peak live memory — the number to cap"
        echo "  At t-end     LIVE AT EXIT — nonzero means a leak"
      else
        echo "note: dhat-heap.json not written (did you call process::exit?)"
      fi
    else
      exit 1
    fi
    ;;

  *)
    echo "error: unknown --tool '$tool'" >&2
    exit 1
    ;;
esac

echo ""
echo "== allocation reduction checklist =="
echo "  Vec::with_capacity where the size is known"
echo "  SmallVec/ArrayVec for short-lived collections"
echo "  Cow<'_, str> instead of String for mostly-borrowed text"
echo "  clone_from instead of clone to reuse buffers"
echo "  hoist workhorse buffers out of loops and clear() them"
