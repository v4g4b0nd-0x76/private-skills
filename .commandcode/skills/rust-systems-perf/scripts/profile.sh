#!/usr/bin/env bash
# Profile a Rust binary's CPU usage, choosing the best tool for this host.
# Usage: profile.sh [project-root] [--bin NAME] [--args "..."] [--tool perf|samply|instruments|callgrind] [--stat]
set -euo pipefail

root="."
bin_name=""
run_args=""
tool="auto"
stat_only=0

usage() {
  cat >&2 <<'EOF'
usage: profile.sh [project-root] [options]
  --bin NAME       binary target to profile (default: package default)
  --args "..."     arguments passed to the binary
  --tool NAME      perf | samply | instruments | callgrind (default: auto)
  --stat           counters only (perf stat), no stacks
EOF
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --bin) bin_name="${2:-}"; shift 2 ;;
    --args) run_args="${2:-}"; shift 2 ;;
    --tool) tool="${2:-}"; shift 2 ;;
    --stat) stat_only=1; shift ;;
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

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: cargo not found" >&2
  exit 2
fi

echo "== building release with symbols =="
export RUSTFLAGS="${RUSTFLAGS:-} -C force-frame-pointers=yes -C symbol-mangling-version=v0"
cargo build --release ${bin_name:+--bin "$bin_name"} 2>&1 | tail -5

target_dir="$(
  cargo metadata --format-version 1 --no-deps 2>/dev/null \
    | sed -n 's/.*"target_directory":"\([^"]*\)".*/\1/p'
)"
target_dir="${target_dir:-target}"

bin_path=""
if [ -n "$bin_name" ]; then
  bin_path="$target_dir/release/$bin_name"
else
  bin_path="$(find "$target_dir/release" -maxdepth 1 -type f -perm -111 ! -name '*.d' ! -name '*.so' ! -name '*.rlib' 2>/dev/null | head -1)"
fi

if [ -z "$bin_path" ] || [ ! -x "$bin_path" ]; then
  echo "error: could not locate a built binary; pass --bin <name>" >&2
  exit 1
fi
echo "binary: $bin_path"

choose_tool() {
  case "$(uname -s)" in
    Linux)
      command -v perf >/dev/null 2>&1 && echo perf || echo none
      ;;
    Darwin)
      command -v samply >/dev/null 2>&1 && echo samply || echo instruments
      ;;
    *) echo none ;;
  esac
}

if [ "$tool" = "auto" ]; then
  tool="$(choose_tool)"
fi

if [ "$stat_only" -eq 1 ]; then
  if ! command -v perf >/dev/null 2>&1; then
    echo "error: --stat needs perf (Linux only)" >&2
    exit 1
  fi
  echo ""
  echo "== perf stat (counters) =="
  # shellcheck disable=SC2086
  perf stat -e cycles,instructions,cache-references,cache-misses,branches,branch-misses \
    "$bin_path" $run_args
  exit 0
fi

echo ""
case "$tool" in
  perf)
    if ! command -v perf >/dev/null 2>&1; then
      echo "error: perf not installed (apt install linux-perf)" >&2
      exit 1
    fi
    echo "== perf record (sampling) =="
    # shellcheck disable=SC2086
    perf record -F 999 -g --call-graph dwarf -o perf.data "$bin_path" $run_args
    echo ""
    echo "Top self-time symbols:"
    perf report -i perf.data --stdio --no-children --percent-limit 1 2>/dev/null | head -40
    echo ""
    echo "For cache-line contention (false sharing) run:"
    echo "  perf c2c record -- $bin_path $run_args && perf c2c report"
    ;;

  samply)
    if ! command -v samply >/dev/null 2>&1; then
      echo "error: samply not installed (cargo install samply)" >&2
      exit 1
    fi
    echo "== samply (opens Firefox Profiler) =="
    # shellcheck disable=SC2086
    samply record "$bin_path" $run_args
    ;;

  instruments)
    echo "== Instruments =="
    echo "Open Instruments > Time Profiler and attach to:"
    echo "  $bin_path"
    echo ""
    echo "Or run from the command line:"
    echo "  xcrun xctrace record --template 'Time Profiler' --launch -- \"$bin_path\" $run_args"
    ;;

  callgrind)
    if ! command -v valgrind >/dev/null 2>&1; then
      echo "error: valgrind not installed or unsupported on this host" >&2
      exit 1
    fi
    echo "== callgrind (deterministic instruction counts) =="
    # shellcheck disable=SC2086
    valgrind --tool=callgrind --callgrind-out-file=callgrind.out "$bin_path" $run_args
    echo "inspect with: kcachegrind callgrind.out"

    ;;

  none)
    echo "error: no supported CPU profiler on this host" >&2
    echo "install samply (cross-platform) or run on Linux with perf" >&2
    exit 1
    ;;

  *)
    echo "error: unknown --tool '$tool'" >&2
    exit 1
    ;;
esac

echo ""
echo "== interpretation =="
echo "  high self time in one function : algorithmic or vectorization problem"
echo "  low IPC, many cache misses    : data layout problem (references/memory-layout.md)"
echo "  lock/futex or syscall frames  : contention or I/O (references/concurrency.md)"
