# Memory Layout and Access Patterns

Load this when choosing a data structure, restructuring a hot type, or when a profile shows cache misses rather than instruction count.

## Start from the access pattern

Ask one question first: **does the code touch whole records, or one field of many records?**

| Access pattern | Layout | Why |
|---|---|---|
| Iterate records, use most fields | array-of-structs `Vec<Record>` | one cache line brings all fields; sequential prefetch works |
| Iterate many records, touch one field | struct-of-arrays `struct { xs: Vec<f32>, ys: Vec<f32> }` | 16x fewer bytes touched per element |
| Mixed, hot subset + cold bulk | hot/cold split: `struct Hot { ... }` + `Vec<Cold>` indexed by `u32` | hot loop stays dense |
| Random access by id | flat array or open-addressed map keyed by integer index | pointer chasing is the cost |
| Append-only, no deletes | `Vec<T>` | contiguous, amortized growth |
| Frequent middle inserts, small n | `SmallVec` | avoids heap entirely |

The wrong answer for every row above is "linked list of boxed nodes". Each node is a separate allocation, a separate cache line, and a pointer chase.

## Cost of common shapes

- `Vec<T>`: one allocation, sequential access, prefetch-friendly. Default choice.
- `Vec<Box<T>>`: one allocation per element plus an indirection per access. Usually wrong.
- `LinkedList<T>`: one allocation per node, no prefetch, no SIMD. Wrong for hot paths.
- `HashMap<K,V>`: one allocation, but probe sequences are random. Fine for lookups, bad for ordered scans.
- `BTreeMap<K,V>`: pointer chasing per node, terrible for scans in cache terms.
- `Rc<RefCell<T>>` graphs: allocation, refcount traffic, and interior checks per access. Use indices into a `Vec` instead ("arena" or "index graph").

## Shrinking hot types

Order fields largest to smallest to reduce padding. Real example:

```rust
// 24 bytes: u8 then u64 forces 7 bytes of padding
struct Bad { tag: u8, value: u64, flag: bool }
// 16 bytes: no internal padding
struct Good { value: u64, tag: u8, flag: bool }
```

Other reductions that matter in hot arrays:
- `Option<&T>`/`Option<Box<T>>` are free (niche optimization); `Option<u32>` is not — use `NonZeroU32` or a sentinel.
- `Box` a large enum variant only if it is rare; otherwise accept the size.
- Store `u32` indices instead of `usize` when the collection cannot exceed `u32::MAX`; halves index traffic in node arrays.
- Verify with `std::mem::size_of::<T>()`, ideally asserted in a test so regressions fail CI.

## Allocation-free patterns

- `Vec::with_capacity(n)` whenever `n` is known or bounded; growth copies are invisible in profiles but real.
- `SmallVec<[T; N]>` for collections that usually have <= N elements. Note it is slightly slower per op than `Vec`; benchmark.
- `ArrayVec<[T; N]>` when the bound is exact — no heap path at all, so `push` cannot allocate and cannot fail.
- `Cow<'a, str>` / `Cow<'a, [T]>` for mostly-borrowed strings and buffers.
- `clone_from(&other)` reuses the destination allocation; `a = b.clone()` does not.
- Workhorse buffers: hoist a `Vec` out of a loop and `clear()` it instead of allocating per iteration.
- `BufRead::read_line` into a reused `String` instead of `.lines()`, which allocates per line.
- Arena: allocate one `Vec<u8>` or bump allocator per request/phase, hand out slices, drop all at once. Great fit for parsers.

## Reducing copies between subsystems

Moving data costs more than touching it. Design to transfer ownership or borrow:

- Take `&[T]`/`&str` in APIs; return owned only when the callee must allocate.
- Pass `Vec<T>` by value into consumers that need it (ownership transfer, no copy) instead of `&Vec<T>` then `.to_vec()`.
- Batch: process 1k items in one call instead of 1k calls, amortizing syscalls and dispatch.
- Prefer `read`-into-buffer APIs (`Read::read`, `recv_into`) over allocating per message.
- Distinguish cold data from hot data in the same struct; do not drag a 4 KB config blob through a 10M-iteration loop.

## Padding and false sharing

Two independent writers must not share a cache line.

```rust
use crossbeam_utils::CachePadded;
use std::sync::atomic::{AtomicU64, Ordering};

struct Counters {
    hits: CachePadded<AtomicU64>,
    misses: CachePadded<AtomicU64>,
}
```

Without padding, `hits` and `misses` sit in the same line and every store invalidates the other core's copy — classic false sharing, invisible in single-threaded benchmarks.

When not using `crossbeam`:

```rust
#[repr(align(128))] // 128, not 64: x86-64/aarch64 prefetch pairs, Apple Silicon is 128
struct Padded(AtomicU64);
```

Rules:
- Pad **between** independently written values, not after every field — padding costs memory bandwidth on reads.
- Do not pad values that are always read together.
- Confirm the real width on the machine (`doctor.sh`); never assume 64.
- `CachePadded<T>` has the same address as its inner `T` since crossbeam-utils 0.8.22, so `&*padded as *const T` is valid.

## Measuring layout wins

1. Record the baseline benchmark.
2. Change one layout dimension (AoS -> SoA, or shrink the type).
3. Re-run. If the delta is inside run-to-run noise, revert — the extra complexity is not paying for itself.
4. For cache-specific evidence, use `perf stat -e cache-misses,cache-references,LLC-load-misses` on Linux before and after.
