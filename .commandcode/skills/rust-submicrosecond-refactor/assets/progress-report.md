## Module Refactor Progress Report: `<module_name>` — `<optimization_title>`

### 1. Executive Summary & Decision

- **Status:** `[ACCEPTED — COMMITTED]` or `[REJECTED — REVERTED]` (Mann–Whitney U: p = …)
- **Hypothesis:** <one mechanism changed>
- **Primary Bottleneck Eliminated / Why Rejected:** <evidence from counters or asm>
- **Evidence paths:** `.bench-history/<module>_….json`, `samples/…`

### 2. Quantitative Progress Rate

| Metric | Original Baseline | Previous Step | Current Step | Step Progress | Cumulative |
| --- | ---: | ---: | ---: | ---: | ---: |
| p50 Latency | | | | | |
| p99 Latency | | | | | |
| p99.9 Latency | | | | | |
| p99.99 Latency | | | | | |
| Tail Ratio (p99.9/p50) | | | | | |
| Throughput | | | | | |
| System Budget Share | | | | | |

### 3. Hardware Counter & Memory Shift

- IPC:
- LLC MPKI:
- Branch miss %:
- `perf c2c` HITM:
- Hot-path allocs / op:
- Asm / IR: `cargo asm` / `@llvm.memcpy` notes
