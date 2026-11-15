# Concurrency Without Contention

Load this when adding threads, when a profile shows lock wait or HITM contention, or when designing shared state.

## The order of attack

Cheapest first. Do not skip a level because the next one is more interesting.

1. **Remove sharing.** Duplicate the data or partition the work so threads never touch the same value.
2. **Transfer ownership.** Move data between threads through a channel instead of sharing it.
3. **Shard.** Give each thread its own slot; merge results once at the end.
4. **Atomics with relaxed ordering** for simple counters and flags.
5. **Lock, but only if 1–4 failed.** Then prefer a well-tested `std::sync::Mutex` over a hand-rolled spinlock.

Lock-free code is a maintenance cost that is usually not repaid. Reach for it only when measured contention justifies it.

## Patterns that remove locks

**Per-thread accumulation, single merge**

```rust
use std::sync::atomic::{AtomicU64, Ordering};
use crossbeam_utils::CachePadded;

// Each worker owns one shard; nobody contends during the loop.
let shards: Vec<CachePadded<AtomicU64>> =
    (0..workers).map(|_| CachePadded::new(AtomicU64::new(0))).collect();

// worker i: shards[i].fetch_add(delta, Ordering::Relaxed);
// at the end:
let total: u64 = shards.iter().map(|s| s.load(Ordering::Relaxed)).sum();
```

**Ownership transfer via channels**

Prefer `crossbeam_channel` bounded channels for backpressure. Send owned messages; never send `Arc<Mutex<_>>` just to share state.

**Sharded map**

Hash the key to `shard_id`, give each shard its own `Mutex<HashMap<_,_>>` or `RwLock`. Contention drops by roughly the shard count. Read-mostly data wants `RwLock` or an immutable snapshot swapped through an `ArcSwap`.

**Snapshot + swap**

Writers build a new immutable structure and publish it atomically; readers clone an `Arc` and read without locks. Ideal when reads dominate.

## Memory ordering

Start at `Relaxed` and only strengthen when a happens-before edge is required.

| Use | Ordering |
|---|---|
| counter increments, statistics | `Relaxed` |
| publish data, then set a flag | store `Release`, load `Acquire` |
| simple flag where only the flag matters | `Relaxed` for both is often enough — prove it |
| global invariant, or you cannot reason about it | `SeqCst` |

`Relaxed` gives atomicity, not ordering. Any value read under `Relaxed` that then guards memory access needs a release/acquire pair.

## Padding shared writes

Independently written values in one cache line serialize the cores. Pad state per thread or per shard:

```rust
use crossbeam_utils::CachePadded;
struct Shard { counter: CachePadded<AtomicU64>, /* ... */ }
```

See [memory-layout.md](memory-layout.md) for why padding width is 128 on x86-64/aarch64 (prefetch pairs / Apple Silicon), even when the hardware L1 line is 64.

## Locks, when you must

- `Mutex` for mutation; `RwLock` only when reads genuinely dominate and hold times are short. `RwLock` is slower than `Mutex` under write pressure and has writer starvation on some platforms.
- Keep critical sections to a few instructions. Never hold a lock across I/O, allocation, or a syscall.
- Consistent lock ordering by address or by declared rank; document the order next to the struct.
- Do not call user callbacks or `Drop` implementations while holding a lock.
- `parking_lot` is faster than `std` when the lock is genuinely hot, but it is a dependency and not poison-based.

## Async is not parallelism

`tokio` gives concurrency for I/O, not CPU parallelism. For CPU-bound work inside async:
- use `spawn_blocking` for blocking calls and syscalls;
- never hold a `std::sync::Mutex` guard across `.await`;
- bound the number of CPU tasks to the core count, not thousands of tasks.

## Verifying concurrency

- `loom` explores interleavings deterministically, but only for the types it replaces — see [testing.md](testing.md).
- `perf c2c` on Linux reports HITM lines: the concrete evidence of false sharing.
- Thread sanitizer (`-Zsanitizer=thread`) catches data races at runtime; nightly only, Linux/macOS.
- Stress tests with many threads and random yields find order-dependent bugs faster than a single-threaded assertion.
