# Research: rust-systems-perf

- **Date:** 2026-11-14
- **Change:** created `rust-systems-perf`
- **Purpose:** systems-programming performance skill — cache-aware layout, low contention, low heap traffic, leak strictness, and verification tooling

## Queries run

1. `Rust performance optimization best practices 2026 cache friendly data structures false sharing`
2. `Rust profiling tools 2026 cargo flamegraph samply perf DHAT heap profiling`
3. `cargo-llvm-cov code coverage Rust llvm source based coverage 2026`
4. `Rust concurrency testing loom miri thread sanitizer data race detection 2026`
5. `Rust CachePadded crossbeam false sharing align 64 bytes best practice 2026`
6. `perf c2c false sharing detection HITM Linux 2026`
7. `Rust memory leak detection dhat-rs valgrind heaptrack CI 2026`
8. `cache line size 64 bytes not always x86 arm apple silicon 128 bytes prefetch false sharing portability`

## Sources

| # | Source | Type | What it established |
|---|--------|------|---------------------|
| 1 | https://nnethercote.github.io/perf-book/profiling.html | vendor docs (Rust Perf Book) | profiler matrix; `debug = "line-tables-only"`; `-C force-frame-pointers=yes`; v0 mangling; std lib symbols stay unsymbolized |
| 2 | https://nnethercote.github.io/perf-book/heap-allocations.html | vendor docs | allocation costs; `SmallVec`/`ArrayVec`/`Cow`/`clone_from`; workhorse buffers; ~10 allocs/Minstros is measurable |
| 3 | https://docs.rs/crossbeam-utils/latest/crossbeam_utils/struct.CachePadded.html | crate docs | **CachePadded uses N=128 on x86-64/aarch64/powerpc64**, 32 on arm/mips, 256 on s390x; prefetcher pulls pairs |
| 4 | https://docs.rs/dhat/latest/dhat/ | crate docs | exact API: `dhat::Alloc`, `Profiler::new_heap()`, `HeapStats::get()`, `Profiler::builder().testing()`; parallel-test restriction; `At t-end` = leaks |
| 5 | https://docs.rs/loom/latest/loom/ | crate docs | `cfg(loom)` type-switch pattern; `LOOM_MAX_PREEMPTIONS`; **cannot model all Relaxed reorderings**; needs `yield_now` in spin loops |
| 6 | https://github.com/taiki-e/cargo-llvm-cov | source repo | `--fail-under-lines`, `--fail-under-regions`; region coverage recommended; branch/doctests unstable |
| 7 | https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/monitoring_and_managing_system_status_and_performance/detecting-false-sharing_monitoring-and-managing-system-status-and-performance | vendor docs | `perf c2c` + HITM is the way to confirm false sharing |
| 8 | https://github.com/rust-lang/miri | source repo | Miri detects OOB, use-after-free, uninit reads, provenance, data races |
| 9 | https://github.com/nnethercote/dhat-rs | source repo | heap usage testing; "free all allocations before finishing" assertions |
| 10 | https://github.com/python/cpython/issues/159860 | real bug report | 64-byte padding on Apple Silicon false-shares because the line is 128 — concrete evidence for the 128 decision |

## Project evidence

- Host is `aarch64-apple-darwin`, `hw.cachelinesize = 128`, 12 cores. Confirms 64-byte padding would be wrong here.
- `valgrind`, `perf`, `heaptrack`, `strace`, `pahole` are all absent on this machine; only `rustup`/`cargo`/`clippy` exist. That is why every script probes capabilities and skips with a printed reason instead of assuming Linux.
- `miri` is not installed; `rust-src` is. Reflects the "record skips" rule.
- Taste: web search before documenting conventions (satisfied above), and one directory per unit with scripts inside.

## Decisions

- **Pad to 128, never 64.** Sources 3 and 10 agree that the prefetcher pairs lines and that Apple Silicon is 128. This is the single most likely error an agent makes from memory, so it is in `Gotchas` and in the doctor output.
- **`CachePadded` preferred over a hand-rolled `#[repr(align)]`** — it is per-architecture and guarantees address identity since 0.8.22. The hand-rolled version ships as an asset with a test asserting a 128-byte gap.
- **Order of work: layout before threads before heap.** Layout changes dominate and are cheapest; adding threads to bad layout just multiplies cache misses.
- **Locks removal ranked above lock tuning.** Sharding/ownership/atomics eliminate the problem; a faster mutex only hides it.
- **Leaks are defects.** Safe Rust prevents use-after-free, not leaks, and `At t-end` is a hard number. Encoded as `--leak` plus the cycle/unbounded-cache list.
- **`target-cpu=native` called out as a shipping bug**, with runtime detection required. Source 1 recommends `RUSTFLAGS` for local profiling, which is exactly the trap — it is fine locally, fatal in a shipped binary.
- **Scripts detect, never assume.** A skipped check prints its reason and is explicitly "not a pass", because a green CI on a host without valgrind must not be read as leak-free.
- Rejected: a single do-everything `perf.sh`. Split into `doctor`, `profile`, `heap`, `coverage`, `bugs` so each is independently readable, testable, and replaceable — matching the modularity requirement.

## Conflicts and resolution

- The Perf Book recommends `strip` sometimes and `debug = "line-tables-only"` for profiling; both cannot hold. Resolved: profiling profile keeps debug info, and `Gotchas` warns against enabling strip together with it.
- Common blog advice says 64-byte padding. Primary sources (3, 10) contradict it. Primary wins; documented in Gotchas.
- `cargo flamegraph` vs `samply`: flamegraph needs perf/DTrace, samply is cross-platform. Default to samply on macOS, perf on Linux, decided in `profile.sh` by host detection.

## Follow-ups (open)

- Consider adding a `criterion` scaffold asset once a real benchmark workflow is observed.
- `bugs.sh` detects loom readiness by grepping for `cfg(loom)`; upgrade to a real build probe if false skips appear.
- `heap.sh` intentionally does not modify source to wire dhat; revisit only if unattended heap runs become routine.

## Verification log (executed, not assumed)

Tested against a real crate on `aarch64-apple-darwin` (rustc 1.96, cache line 128).

| Check | Result |
|---|---|
| `assets/cache-padded.rs` compiled + its 3 tests | pass — 128-byte gap assertion holds on real hardware |
| `doctor.sh` on a project with planted defects | caught `repr(align(64))`, `Box::leak`, `Vec::new` in hot path |
| `heap.sh` with real dhat wiring | dhat reported `At t-end: 1,089 bytes` — the planted leak |
| `coverage.sh --min 90` | exit 1 at 24.14% lines; `--min 20` exit 0 |
| `bugs.sh loom` with a planted lost-update race | exit 1, `test race_lost_updates ... FAILED` |
| `bugs.sh loom` with the race using `std` atomics | **exit 0 (race missed)** — confirms the documented loom visibility gotcha |
| `bugs.sh audit` with unmarked `unsafe` | exit 1 |
| `bugs.sh cpu` with `#[target_feature]` and no detection | exit 1 |
| `bugs.sh miri` / `leaks` when unavailable | SKIP with reason, exit 0, summary says skipped != pass |

Bugs found and fixed during verification:
- `bugs.sh` aborted under `set -euo pipefail` when a grep found nothing — masked the summary and produced false passes. Fixed by guarding every grep.
- Loom test files without `#![cfg(loom)]` broke plain `cargo test` **and** `cargo llvm-cov`, because neither passes `--cfg loom`. Fixed in the asset and documented in both the reference and the SKILL body's gotchas.

This also corrects the two earlier follow-ups: coverage JSON parsing and the loom path are now verified, not heuristic. The `cfg(loom)` grep in `bugs.sh` remains a heuristic for *detecting* setup, but its skip message tells the agent to consult `references/testing.md`.

