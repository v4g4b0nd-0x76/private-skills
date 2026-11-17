---
name: rust-submicrosecond-refactor
description: Module-by-module micro-optimization for already-fast Rust hot paths targeting tens-to-hundreds of nanoseconds — modularize, stand up production-grade bench fixtures/mocks when needed, persist TSC/open-loop baselines, change one variable, dual-gate with Mann–Whitney U, report progress rates. Use when refactoring sub-microsecond / HFT / kernel-bypass / io_uring / lock-free / SIMD Rust for p99 and tail jitter, when devflow routes here for bench_env, or when asking for a sub-µs campaign with .bench-history. Don't use for ordinary Rust services, general allocation or locality reviews (use rust-systems-perf), greenfield features, or micro-opts without a baseline.
argument-hint: "[bench-env | modularize | audit | baseline | refactor | report | <module>]"
compatibility: Linux x86_64 preferred (serialized TSC, perf/c2c); python3 + rg required for bundled scripts
metadata:
  version: "1.2"
---

# Sub-Microsecond Rust Refactor

`$SKILL_DIR` = absolute path of this skill directory.

Work **module by module**. Scripts adjudicate accept/reject; do not claim a win without their exit codes and persisted JSON.

```
Phase 0 Modularize → Env (if needed) → 1 Audit → 2 Bench+Persist → 3 One-var refactor+gate → 4 Progress report
```

## Softflow integration

When devflow `next.sh` returns `NEXT: rust-submicrosecond-refactor`:

1. Read `.devflow/plan.md` (`bench_env`, `latency_campaign`, `## Bench environment`).
2. Run **Bench environment** below until `.devflow/bench-env.md` is `status: complete` and `check-bench-env.sh` exits 0.
3. If `latency_campaign: true`, continue Phases 0–4. Else re-run devflow `next.sh` (usually the test gate).
4. Mark env stale after new implements: `bash ../devflow/scripts/mark-stale.sh <root> bench-env test review`.

## Preconditions

- Code already correct and roughly optimized; this skill squeezes hidden ns, not first-pass design.
- Run host triage first:
  ```bash
  bash $SKILL_DIR/scripts/doctor.sh <project-root>
  ```
- If benches need mock data or third-party access, the env phase is mandatory before Phase 2.
- If required inputs are missing (no hot module, no bench harness, no samples), stop with `BLOCKER` — do not invent counters or p-values.

## Non-negotiables

1. Never optimize blindly: modularize → audit → persist baseline → one hypothesis → re-bench → progress rate.
2. One architectural variable per step (so IPC / LLC MPKI / HITM shifts are attributable).
3. `unsafe` / SIMD / SeqLock / `io_uring` behind a safe API + `// SAFETY:` + loom/miri/property tests where applicable.
4. Evidence before claim: every metric cites a file under `.bench-history/` or script stdout from this run.



## Phase 0 — Modularize & deterministic build

Decompose hot flow into compile-benchmarkable boundaries:

| Crate / area | Owns |
| --- | --- |
| `*-clock` | TSC timers, open-loop generator, CTE helpers |
| `*-wire` | Zero-copy parse / prefilled egress templates |
| `*-state` / `*-book` | Slabs, SoA, bitmaps, SIMD kernels |
| `*-sync` | `CachePadded` SPSC/MPSC, SeqLocks |
| `*-io` / `*-runtime` | Pinned `io_uring` / XDP / DPDK, NUMA first-touch |
| `benches/` | `divan` + end-to-end open-loop |

Merge `assets/Cargo.toml.fragment.toml` and `assets/cargo-config.toml.fragment.toml` into the project (drop what does not apply). Prefer `target-cpu=native` only for local measurement — not for heterogeneous fleet shipping.



## Phase 1 — Audit backlog

```bash
bash $SKILL_DIR/scripts/audit-static.sh <hot-module-paths>
```

Then read [references/audit-dimensions.md](references/audit-dimensions.md) and finish dimensions **A–E** (alloc, memcpy, layout/false-sharing, branches/SIMD, I/O/jitter) with `perf` / `perf c2c` / `cargo asm` as needed.

Output: prioritized backlog. Each item = one hypothesis (module, change, expected asm/counter shift).

For crate choice while designing a fix, read [references/crates-and-sources.md](references/crates-and-sources.md).



## Phase 2 — Bench & persist baseline

If the plan or workload needs fixtures/third parties, **Bench environment** must already be complete. Read [references/benchmarking.md](references/benchmarking.md) before writing harness code.

Rules of thumb (details in the reference):

- Serialized TSC on x86_64 — not `Instant`
- Open-loop intended arrivals — not closed-loop / `sleep`
- `AllocProfiler` / counting allocator → 0 allocs after warmup

Persist:

```bash
mkdir -p .bench-history/samples
python3 $SKILL_DIR/scripts/persist_baseline.py write \
  --out .bench-history/<module>_baseline.json \
  --module <module> --stage baseline_v0 \
  --from-env --latency-json <percentiles.json> --force
python3 $SKILL_DIR/scripts/persist_baseline.py validate \
  .bench-history/<module>_baseline.json
```

Schema example: [assets/baseline.example.json](assets/baseline.example.json).



## Phase 3 — One-module refactor & dual gate

Typical order: `wire` → layout/SoA → branchless/SIMD → sync rings → io/runtime + PGO/BOLT.

For each backlog item:

1. State hypothesis (one mechanism).
2. Implement; keep API safe.
3. Correctness: unit + property (+ `loom` for atomics/rings).
4. Codegen: `cargo asm --release --mca <fn>`; IR for unexpected `@llvm.memcpy`.
5. Interleaved A/B samples → dual gate:

```bash
python3 $SKILL_DIR/scripts/gate.py \
  --before .bench-history/samples/<module>_before.json \
  --after  .bench-history/samples/<module>_after.json \
  --alpha 0.01 --min-median-improvement-pct 2.0 --allow-p99-only
```

| Gate | Pass when |
| --- | --- |
| Statistical | Mann–Whitney U two-sided `p < 0.01` |
| Practical | ≥2% median improvement **or** p99/CTE improvement (`--allow-p99-only`) and no alloc/safety regression |

- **Both pass** → commit; write `.bench-history/<module>_step_<N>.json`.
- **Either fails** → revert immediately; note failure in `.bench-history/PROGRESS_LEDGER.md`; next hypothesis.

`gate.py` exit code is the verdict. Do not override a REJECT with narrative.



## Phase 4 — Progress report

```bash
python3 $SKILL_DIR/scripts/progress.py \
  --base .bench-history/<module>_baseline.json \
  --prev .bench-history/<module>_step_<N-1>.json \
  --curr .bench-history/<module>_step_<N>.json \
  --append-ledger .bench-history/PROGRESS_LEDGER.md
```

Fill [assets/progress-report.md](assets/progress-report.md) for the user-facing write-up (status, hypothesis, table, counter shifts, evidence paths).



## Grounding rules

- Optimize only against a recorded baseline. No before/after JSON → no performance claim.
- Platform facts (governor, turbo, isolcpus, cache line) come from `doctor.sh`, not memory.
- Silicon latency tables in the audit reference are order-of-magnitude aids, not host measurements.
- Skipped `perf`/`c2c`/loom checks are gaps, not passes — record them.
- Insufficient context → `BLOCKER` and ask; never fabricate samples for `gate.py`.

## Gotchas

- `Instant` / `clock_gettime` overhead can exceed the path under test — use fenced TSC on x86_64.
- Closed-loop load generators hide coordinated omission; use open-loop intended times.
- `mem::take` on reusable buffers resets capacity and re-allocates — use `clear()`.
- Pad independently written shared atomics with `CachePadded` (128 on x86-64/aarch64), even when the hardware line is 64.
- `dyn Trait` and runtime `%` in hot loops show up as indirect `call` / `div` in `cargo asm`.
- Interleave A/B on one isolated core; otherwise MWU measures thermal/scheduler noise.
- Do not ship `-C target-cpu=native` to mixed fleets.
- Zero-latency stubs hide production p99 — use `prod-like` profiles with sourced delays; keep `baseline-zero` only for code-vs-code dual-gate.
- Softflow `bench_env: required` without a complete `.devflow/bench-env.md` is a hard stop before measuring.

## Checklist

- [ ] `doctor.sh` run; isolation/governor warnings acknowledged
- [ ] Bench env checked when mocks/third parties required (`check-bench-env.sh`)
- [ ] Module boundaries compile/bench independently
- [ ] Audit backlog written (dimensions A–E as applicable)
- [ ] Baseline JSON validated under `.bench-history/`
- [ ] One-variable refactor + correctness suite
- [ ] `gate.py` ACCEPT before commit (or REJECT + revert recorded)
- [ ] `progress.py` ledger row + report template filled
- [ ] Evidence paths cited for every claimed metric

## Dependencies

- References: [references/audit-dimensions.md](references/audit-dimensions.md), [references/benchmarking.md](references/benchmarking.md), [references/crates-and-sources.md](references/crates-and-sources.md), [references/bench-env.md](references/bench-env.md)
- Scripts: `scripts/doctor.sh`, `scripts/audit-static.sh`, `scripts/setup-bench-env.sh`, `scripts/check-bench-env.sh`, `scripts/persist_baseline.py`, `scripts/gate.py`, `scripts/progress.py`
- Assets: `assets/Cargo.toml.fragment.toml`, `assets/cargo-config.toml.fragment.toml`, `assets/baseline.example.json`, `assets/progress-report.md`, `assets/bench-env.md`, `assets/docker-compose.bench.yml`, `assets/toxiproxy.json`, `assets/wiremock/`
- Siblings: `devflow` (optional `bench_env` / `latency_campaign` routing), `thirdparty-e2e` (inventory + mock/fault patterns), `rust-systems-perf` (general layout/heap — not this campaign)
