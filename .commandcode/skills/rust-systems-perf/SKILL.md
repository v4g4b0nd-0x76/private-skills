---
name: rust-systems-perf
description: Design and verify Rust systems code for cache-efficient memory layout, minimal locking, low heap traffic, and predictable performance, with scripts for CPU profiling, heap analytics, coverage gates, and concurrency/UB/leak/CPU-feature tests. Use when writing or reviewing Rust performance-critical, multithreaded, or memory-constrained code, when reducing allocations or lock contention, or when the user asks to profile, benchmark, or harden a Rust binary. Don't use for ordinary Rust refactors, CLI plumbing, or request/response services where latency and allocation are not the constraint.
argument-hint: "[audit | profile | heap | coverage | bugs | <task>]"
metadata:
  version: "1.0"
---

# Rust Systems Performance

Work in the order below. Each step has a gate; do not skip to optimization before measurement.

`$SKILL_DIR` in the commands below means the absolute path of this skill's own directory.

## Step 0 — Establish the environment

```bash
bash $SKILL_DIR/scripts/doctor.sh <project-root>
```

It prints the target triple, the machine's real cache line size, which profilers and sanitizers exist, and review candidates in the source. Read its output before choosing any workflow; on a platform without `perf`/`valgrind` most of the classic advice does not apply.

- Hardware L1 line size is usually **64 bytes on x86-64**, **128 on Apple Silicon**, 32 on some arm/mips, 256 on s390x. Read the value `doctor.sh` printed — do not invent it.
- For false-sharing padding, still use **128** (or `CachePadded`) on x86-64/aarch64/powerpc64: Intel/AMD adjacent-line prefetch can couple two 64-byte lines, so 64-byte separation is not enough. That is a padding width, not a claim that the hardware line is 128.

## Step 1 — Measure before changing anything

1. Build a release profile with debug info, or symbols are useless:
   ```toml
   [profile.release]
   debug = "line-tables-only"
   lto = "thin"
   codegen-units = 1
   panic = "abort"
   ```
   Copy `assets/Cargo.toml.fragment.toml` into the project's `Cargo.toml` and drop what does not apply.
2. Write a `criterion` benchmark or capture a workload. Wall-clock noise on a laptop is larger than most optimizations; a benchmark with a baseline is the only defensible comparison.
3. Profile the CPU:
   ```bash
   bash $SKILL_DIR/scripts/profile.sh <project-root> [--bin <name>]
   ```
4. Record the baseline numbers in your notes before editing. Optimization without a before/after pair is a guess.

## Step 2 — Fix the data layout first

Layout changes dominate and are the cheapest wins. Read [memory-layout.md](references/memory-layout.md) before restructuring.

- Prefer contiguous `Vec<T>` and flat arrays over `Vec<Box<T>>`, linked lists, and pointer-heavy trees. Each pointer hop is a likely cache miss.
- Choose layout by access pattern: array-of-structs for whole-record iteration, struct-of-arrays for scanning one field. Read the how-to in the reference before converting.
- Shrink hot types: reorder fields largest-first, box cold variants of large enums, use `u32`/`NonZero` indices instead of pointers where it fits.
- Avoid hidden allocations: `with_capacity`, `SmallVec`/`ArrayVec` for short collections, `Cow<'_, str>` for mostly-borrowed strings, `clone_from` instead of `clone`.
- Keep one arena or slab per phase instead of many small allocations; batch work to amortize.

Stop calling the allocator on hot paths. `dhat` output in Step 4 is the proof.

## Step 3 — Remove contention before adding threads

Read [concurrency.md](references/concurrency.md).

1. Reduce shared mutable state first. Sharding, per-thread accumulators merged at the end, or message passing beat any lock tuning.
2. Make each thread own its data; use channels for transfer of ownership rather than shared mutation.
3. For counters, prefer per-shard `CachePadded` atomics with `Relaxed` and a final fold, over one contended atomic.
4. Pad every independently written shared value to a full cache line: `crossbeam_utils::CachePadded`, or `#[repr(align(128))]`.
5. Choose the weakest correct ordering (`Relaxed` -> `Acquire`/`Release` -> `SeqCst`) and justify it in a comment.
6. Use `std::sync::Mutex` unless the lock is genuinely hot; then prefer sharding over a spinlock. Spinlocks are unfair and hurt on oversubscribed cores.

Confirm false sharing with evidence, not intuition: `perf c2c` on Linux reports HITM lines.

## Step 4 — Cut heap traffic and prove it

```bash
bash $SKILL_DIR/scripts/heap.sh <project-root> [--bin <name>] [--leak]
```

Read [profiling.md](references/profiling.md) for the tool matrix and platform constraints.

- `--leak` reports blocks still live at exit. Anything nonzero is a real leak: `Rc`/`Arc` cycles, `mem::forget`, `Box::leak`, unbounded caches, or dropped join handles.
- Safe Rust prevents use-after-free, not leaks. Treat a growing `At t-end` number as a defect of the same severity as a failing test.
- Reducing allocation rate by ~10 per million instructions is measurable; do not fight over one allocation in a cold path.

## Step 5 — Verify with gates

```bash
bash $SKILL_DIR/scripts/coverage.sh <project-root> [--min 90]
bash $SKILL_DIR/scripts/bugs.sh <project-root> [--all | miri | loom | asan | tsan | leaks | cpu]
```

- Coverage is a floor, not a goal. Region coverage matters more than line coverage for branch-heavy systems code.
- `bugs.sh` runs what the host supports and skips the rest with a printed reason. A skipped check is not a pass; record it.
- Run the CPU-feature check whenever `target-cpu` or `#[target_feature]` is involved: code that works with `-C target-cpu=native` and breaks on a baseline target is a shipping bug.

## Grounding rules (anti-hallucination)

- Optimize only against a recorded baseline. Do not claim a win without before/after numbers from `criterion`, `perf`, `samply`, or `dhat`.
- Platform facts (`perf`/`valgrind` availability, cache line size, sanitizer support) come from `doctor.sh` output, not assumptions.
- A skipped `bugs.sh` check is not a pass — record the skip reason. Do not invent Miri/Loom results that were not run.
- Prefer `CachePadded` over hand-rolled constants when unsure of the pad width.

## Gotchas

- **64-byte padding is wrong for contended atomics on x86-64/aarch64.** Prefer `CachePadded` (N=128 there) or `#[repr(align(128))]`. On Apple Silicon the hardware line is also 128 (`sysctl -n hw.cachelinesize`).
- **`-C target-cpu=native` is a portability trap.** Build and test artifacts with it if you like, never ship binaries with it. Prefer runtime detection (`is_x86_feature_detected!`, `is_aarch64_feature_detected!`).
- **`valgrind` does not run on Apple Silicon macOS.** Use `dhat-rs` there; it works on all platforms and needs a source hook.
- **`dhat` heap-usage tests must not run in parallel.** Put each in its own integration test file, or use `--test-threads=1`.
- **`loom` only sees the types it replaces.** Code using `std::sync::Mutex` directly is invisible to it; keep a `sync` module that switches types under `cfg(loom)`.
- **Loom test files must start with `#![cfg(loom)]`.** Otherwise plain `cargo test` and `cargo llvm-cov` fail to compile them, breaking the normal test run.
- **`loom` cannot model all `Relaxed` reorderings**, so a green loom run is not proof of correctness for relaxed code.
- **`perf` is Linux-only, `DTrace` is macOS.** `cargo flamegraph` maps to whichever exists; `samply` is the cross-platform choice.
- **Profilers need frame pointers.** Add `-C force-frame-pointers=yes` or the stack traces are fiction.
- **`bencher`/`criterion` in debug mode is meaningless.** Always benchmark `--release`.
- **`strip` in release removes the debug info you just added.** Do not enable both.

## Checklist

- [ ] `doctor.sh` run and platform limits understood
- [ ] Baseline benchmark recorded before edits
- [ ] Layout chosen against an access pattern, not by habit
- [ ] Cache line padding width justified, not hardcoded to 64
- [ ] Lock removal tried before lock tuning
- [ ] Allocation count before/after captured
- [ ] Coverage gate run and threshold met
- [ ] `bugs.sh` checks run or their skips recorded
- [ ] `--release` used for every measurement

## Dependencies

`references/memory-layout.md`, `references/concurrency.md`, `references/profiling.md`, `references/testing.md` hold the detail and are loaded on demand. Scripts: `scripts/doctor.sh`, `scripts/profile.sh`, `scripts/heap.sh`, `scripts/coverage.sh`, `scripts/bugs.sh`. Assets: `assets/Cargo.toml.fragment.toml`, `assets/cache-padded.rs`, `assets/dhat-harness.rs`, `assets/loom-test.rs`.
