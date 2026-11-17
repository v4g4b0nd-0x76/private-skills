# Hardware Audit Dimensions (A–E)

Load this during **Phase 1**. Produce a prioritized refactor backlog ranked by expected p99 / throughput impact. One hypothesis per backlog item.

Order-of-magnitude latencies below are **typical x86_64 @ ~3 GHz**, not measured evidence for the host under test. Prefer `perf` / `scripts/doctor.sh` for claims about *this* machine.

| Event | ~ns | Budget note |
| --- | ---: | --- |
| L1d hit | 1–1.5 | Target for hot data |
| L2 hit | ~4 | |
| Branch mispredict | ~5 | |
| L3 hit | 12–15 | |
| False sharing (HITM) | 50–130 | |
| Local DRAM | 80–100 | 3 misses blow a 300 ns budget |
| Remote NUMA DRAM | 130–180+ | |
| Heap alloc | 100–500 | + multi-ms compaction tails |
| Minor page fault | 700–1000 | |
| Context switch / futex | 5k–50k | |

---

## A — Heap, VM, page faults

**Static scan** (or run `scripts/audit-static.sh`):

```bash
rg 'Vec|String|Box|Arc|Rc|HashMap|BTreeMap|collect\(|clone\(|format!|to_owned|to_string' <hot-modules>
```

**Flag**

- Any heap alloc / realloc / cross-thread `Drop` after warmup
- `mem::take` on reusable `Vec`s (capacity → 0) — use `clear()`
- Unprefaulted buffers (first-write minor faults)
- Missing `mlockall` / huge pages when dTLB thrashing
- THP left in `always` (`khugepaged` stalls)

**Patterns (5 lifetime classes)**

1. Forever: alloc at startup, prefault, share `&T` / `Arc<T>`
2. One message/batch: engine-owned `Vec` + `clear()`, or `bumpalo` reset per batch
3. Bounded small: `SmallVec` / `heapless::Vec` / `ArrayVec`
4. Across events: fixed-capacity generational slab + LIFO free-list
5. Cross-thread: TLS pool or return-path SPSC (never drop across cores)

---

## B — Hidden copies (`@llvm.memcpy`) & serialization

**Scan**

```bash
cargo rustc --release -p <crate> --lib -- --emit=llvm-ir
# inspect target/release/deps/*.ll for @llvm.memcpy ... large sizes
```

Flag `serde_json` / `bincode` / `prost` / byte-at-a-time decode on hot wire paths. Flag `&field` on `#[repr(C, packed)]` (alignment UB).

**Patterns**

- Pass large state by `&mut` when RVO fails
- Flat frames: `zerocopy` (`FromBytes`/`TryFromBytes`/`IntoBytes`/`Unaligned`) or `bytemuck` (`Pod`/`Zeroable`)
- Complex graphs over SHM: `rkyv` (+ `bytecheck` for untrusted) or `epserde` for huge read-only maps
- Prefill outbound headers; patch only dynamic fields in place

---

## C — Cache-line density, layout, false sharing

**Scan**

- `size_of` / `align_of` for hot structs
- `perf stat -e cycles,instructions,cache-misses,LLC-load-misses,L1-icache-load-misses`
- `perf c2c record` / `perf c2c report` for HITM

**Flag**

- Padding waste from mixed field sizes
- `Option<u64>` where `Option<NonZeroU64>` niches work
- Hot+cold fields in one struct; AoS scanned for 1–2 fields
- Two writers in the same 128B padded region (Intel adjacent-line prefetch; pad with `CachePadded`)
- Cold `format!`/error paths inlined into hot loops (L1i pollution)

**Patterns**

- Largest-align-first `#[repr(C)]`; assert hot size 32/64B
- Hot collections → SoA (`soa-rs` / `soa_derive`)
- Prefetch (`_mm_prefetch`) ≥100–200 cycles before cold slab deref; `_MM_HINT_NTA` for streaming
- `#[cold] #[inline(never)]` for error/slow paths

---

## D — Branches, dispatch, SIMD

**Scan:** `cargo asm --release --mca <symbol>`

**Flag**

- `dyn Trait` in hot loops
- Runtime `%` → `div`/`idiv`
- Per-iter bounds checks; data-dependent branches
- `sum::<f32>` blocked from auto-vec; `is_x86_feature_detected!` inside tight loops

**Patterns**

- Generics / closed `enum` instead of `dyn`
- Power-of-two rings: `idx & (N - 1)`
- `select_unpredictable` / occupancy bitmaps + `trailing_zeros`
- SIMD stack: (1) shaped auto-vec over `as_chunks`, (2) token multiversioning (`fearless_simd` / `pulp` / `wide`), (3) explicit `core::arch` intrinsics

---

## E — I/O, concurrency, OS jitter

**Scan:** `Mutex` / `mpsc` / contended `RwLock`, work-stealing across cores, blocking I/O, `RefCell` across `.await`, `perf stat -e context-switches,cpu-migrations`

**Patterns**

- SPSC rings (`rtrb` / `ringbuf` / `disruptor` / custom `CachePadded`) with cached remote indices; `Acquire`/`Release` (ARM-safe); `SeqCst` only on park/wakeup flags
- Reader-silent broadcast: single-line SeqLock instead of `RwLock` for TOB-like state
- µs storage/net: pinned `compio`/`io_uring` (`REGISTER_BUFFERS`/`FILES`, `SINGLE_ISSUER`, `DEFER_TASKRUN`, optional `SQPOLL`)
- Sub-µs wire: `AF_XDP` ZC / `ef_vi` / `DPDK`
- Host: `isolcpus` + `nohz_full` + `rcu_nocbs`; first-touch after pin; optional `cargo pgo` → BOLT
