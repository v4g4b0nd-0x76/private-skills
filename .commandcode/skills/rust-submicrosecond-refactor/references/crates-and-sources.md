# Crates & Sources

Load when choosing a concrete refactor pattern (Phase 3) or justifying a backlog item (Phase 1). Prefer the **default** in each row; escape hatches are secondary.

## Crates by layer

| Layer | Default | Escape / related |
| --- | --- | --- |
| Allocators / arenas | `bumpalo`, `mimalloc` | `tikv-jemallocator`, `smallvec`, `heapless`, `arrayvec` |
| Zero-copy / ser | `zerocopy` | `bytemuck`, `rkyv` + `bytecheck`, `epserde` |
| Layout / SoA | `crossbeam-utils` (`CachePadded`) | `soa-rs`, `soa_derive` |
| SIMD | `fearless_simd` or `pulp` | `wide`, `core::arch::{x86_64,aarch64}` |
| Lock-free | `rtrb` (SPSC) | `ringbuf`, `disruptor`, `loom` for model checks |
| I/O / pin / bench | `compio`, `core_affinity`, `divan` | `cargo-show-asm`, `cargo-pgo` |

Pin crate majors in the project; do not invent APIs from memory — check docs.rs for the pinned version.

## Foundational references

- **Kernel isolation:** Linux CPU isolation (`isolcpus=managed_irq,domain`, `nohz_full`, `rcu_nocbs`, `irqaffinity`, `idle=poll`, `intel_idle.max_cstate`); Fixstars / LLTune / `PREEMPT_RT` jitter guides; Intel MPK/PKU for in-process domains.
- **Compiler / PGO / SIMD:** `cargo-pgo` + BOLT writeups; safe SIMD / `#[target_feature]` token patterns (Rust 1.87+); auto-vectorization shaping.
- **Memory / atomics / zero-copy:** Mara Bos *Rust Atomics and Locks* (hardware models); Rustonomicon data layout; `rkyv` relative pointers; diagnosing `@llvm.memcpy`.
- **TPC / HFT architecture:** thread-per-core + `io_uring` (`compio`, Glommio-style); ordered TSC reads; open-loop latency methodology.

## Sibling skill

For general layout / heap / loom / coverage (not the sub-µs dual-gate campaign), prefer **`rust-systems-perf`**.
