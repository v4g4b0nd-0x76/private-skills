# Profiling Matrix

Load this when choosing a profiler, interpreting a profile, or when `profile.sh` says a tool is unavailable.

## Which tool where

| Tool | Platform | Answers | Notes |
|---|---|---|---|
| `perf record`/`report` | Linux | where CPU time goes (sampling) | needs `perf_event_paranoid` <= 2 |
| `perf c2c` | Linux | false sharing, HITM lines | the only practical proof of false sharing |
| `perf stat` | Linux | cache misses, IPC, branch misses | counters, not stacks |
| `samply` | macOS/Linux/Windows | CPU profile, Firefox Profiler UI | simplest cross-platform option |
| `cargo flamegraph` | Linux + DTrace platforms | flame graph | uses perf or DTrace underneath |
| Instruments | macOS | CPU, allocations, threads | GUI, best for Apple Silicon |
| `valgrind --tool=callgrind` | Linux/Unix | instruction counts, call graph | deterministic, ~50x slower |
| `valgrind --tool=cachegrind` | Linux/Unix | simulated cache/branch behavior | deterministic, no real hardware counters |
| `valgrind --tool=dhat` | Linux/Unix | allocation sites, lifetimes | **not available on Apple Silicon macOS** |
| `dhat-rs` | all platforms | allocation sites, lifetimes, heap tests | requires source hook + feature flag |
| `heaptrack` | Linux | allocation timeline | GUI |
| `strace -c` | Linux | syscall counts and time | find syscall-heavy hot paths |
| `criterion` | all | statistically sound benchmarks | the only defensible before/after |

## Making profiles readable

Release builds drop symbols by default:

```toml
[profile.release]
debug = "line-tables-only"
```

And force frame pointers, or stacks are truncated:

```bash
RUSTFLAGS="-C force-frame-pointers=yes" cargo build --release
```

If symbols show as `_ZN...` or `_R...`, add `-C symbol-mangling-version=v0` or demangle with `rustfilt`.

Standard library internals stay unsymbolized in shipped toolchains; do not chase `Vec::push` frames you cannot see into.

## Reading a profile

1. Sort by self time, not cumulative. Cumulative points at the entry point, self time points at the cost.
2. Look for the expected hot function. If it is missing, your model of the program is wrong — investigate before optimizing.
3. Distinguish three bottleneck classes, because the fix differs:
   - **instructions**: the algorithm is wrong or unoptimized — improve complexity or vectorize.
   - **cache misses**: the data layout is wrong — see [memory-layout.md](memory-layout.md).
   - **syscalls/lock wait**: I/O or contention — batch, buffer, or shard; see [concurrency.md](concurrency.md).
4. Check `perf stat` IPC: high IPC with high time means real work; low IPC usually means stalls (memory or branches).

## Allocation profiling

`dhat-rs`, minimal wiring:

```rust
#[cfg(feature = "dhat-heap")]
#[global_allocator]
static ALLOC: dhat::Alloc = dhat::Alloc;

fn main() {
    #[cfg(feature = "dhat-heap")]
    let _profiler = dhat::Profiler::new_heap();
    // ...
}
```

Add to `Cargo.toml`:

```toml
[features]
dhat-heap = []
[profile.release]
debug = 1
```

Run with `cargo run --release --features dhat-heap`, then open `dhat-heap.json` in DHAT's viewer (`https://nnethercote.github.io/dh_view/dh_view.html`).

Reading the output:
- `Total` — allocation traffic; the rate is what to reduce.
- `At t-gmax` — peak live memory; the number to cap.
- `At t-end` — **blocks still alive at exit**; nonzero means a leak.
- Per-site backtraces tell you exactly which `Vec`/`String`/`Box` is hot.

`dhat` only profiles within `main`; allocations before/after are invisible. If output is empty you forgot the `#[global_allocator]`.

On Linux, `valgrind --tool=dhat` needs no source changes and also reports `memcpy` hot spots; prefer it when available.

## Leaks in safe Rust

Safe Rust rules out use-after-free, not leaks. Real sources:

- `Rc`/`Arc` reference cycles — break with `Weak`.
- `Box::leak`, `mem::forget`, `ManuallyDrop` on a path that never drops.
- Unbounded caches, `HashMap` that only grows, log buffers never drained.
- Detached threads or tasks holding state forever; `JoinHandle` dropped means the thread still runs.
- `Arc` held in a global registry that never evicts.

Detection, in increasing cost:
1. `dhat --leak`: `At t-end` nonzero.
2. `valgrind --leak-check=full` for precise stacks (Linux).
3. Long-running soak test with RSS sampled over time; a monotonic rise is a leak even without a trace.

## Syscall reduction

- Batch writes; use `BufWriter` with a capacity chosen for the write size, and flush explicitly.
- Use `read_into`/`recv_into` into a reused buffer instead of allocating per call.
- Prefer `io_uring`/`epoll` on Linux for high-connection-count servers; `kqueue` on macOS.
- `strace -c -f` gives counts per syscall; a million `futex` calls usually means lock contention, not I/O.
- `mmap` large read-only files instead of reading into memory when the file is bigger than the hot subset.

## Benchmarking discipline

- `criterion` with a saved baseline (`--save-baseline before`, `--baseline before`).
- Pin the CPU where possible; disable turbo/thermal throttling for stable numbers.
- Report median and outlier counts; a single fast run is not a result.
- Never benchmark with `--debug`; the optimizer removes the work you meant to measure.
- Watch for dead-code elimination: use `std::hint::black_box` on inputs and outputs.
