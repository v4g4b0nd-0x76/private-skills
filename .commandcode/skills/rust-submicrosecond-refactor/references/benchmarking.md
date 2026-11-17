# Benchmarking & Persistence

Load this during **Phase 2** (baseline) and **Phase 3** (A/B gate). Persist every accepted step under `.bench-history/`.

## Construction rules

1. **No `std::time::Instant` in sub-µs loops** — vDSO/`clock_gettime` is tens of ns. On x86_64 use serialized TSC:
   - start: `_mm_lfence(); _rdtsc()`
   - stop: `__rdtscp(&mut aux); _mm_lfence()`
   - reject sample if `(aux & 0xfff)` core ID changed
   - calibrate TSC Hz over ~200 ms against `CLOCK_MONOTONIC`
2. **Open-loop arrivals** (avoid coordinated omission): intended time `t0 + i * Δt` on a spinning pinned core; record `t_done - t_intended(i)`. Never `thread::sleep` in the generator.
3. **Zero alloc proof:** `divan::AllocProfiler` or a counting `GlobalAlloc`; assert alloc/realloc/dealloc/bytes == 0 after warmup.
4. **Conditional Tail Excess** for stage `i` over end-to-end tail set `T_q` (e.g. q=0.99), with `m_i` = all-order median of stage `i`:

   `Excess_i = mean( max(0, d_i - m_i) for d in T_q )`

5. **Interleaved A/B:** `A → B → A → B …` on an isolated, frequency-locked core.

## Persist layout

```
.bench-history/
  <module>_baseline.json      # stage baseline_v0
  <module>_step_<N>.json      # accepted refactor N
  PROGRESS_LEDGER.md          # human cumulative table
  samples/
    <module>_before.json      # raw latency_ns arrays for gate.py
    <module>_after.json
```

Copy schema from `assets/baseline.example.json`. Write with:

```bash
python3 $SKILL_DIR/scripts/persist_baseline.py write \
  --out .bench-history/<module>_baseline.json \
  --module crates/foo --stage baseline_v0 \
  --from-env --latency-json latency.json
```

## Dual gate (scripts decide)

```bash
python3 $SKILL_DIR/scripts/gate.py \
  --before .bench-history/samples/<module>_before.json \
  --after  .bench-history/samples/<module>_after.json \
  --alpha 0.01 --min-median-improvement-pct 2.0
```

| Gate | Rule | Fail action |
| --- | --- | --- |
| 1 Statistical | Mann–Whitney U two-sided `p < alpha` (default 0.01) | revert |
| 2 Practical | ≥ `min-median-improvement-pct` median win **or** p99 / CTE reduction; no alloc/safety regression | revert |

Latency distributions are right-skewed; MWU is non-parametric (no normality assumption). Do not substitute a t-test.

## Progress formulas

```bash
python3 $SKILL_DIR/scripts/progress.py \
  --base .bench-history/<module>_baseline.json \
  --prev .bench-history/<module>_step_<(N-1)>.json \
  --curr .bench-history/<module>_step_<N>.json \
  --append-ledger .bench-history/PROGRESS_LEDGER.md \
  --report-template $SKILL_DIR/assets/progress-report.md
```

- Latency reduction %: `(L_before - L_after) / L_before * 100`
- Speedup: `L_before / L_after`
- Throughput gain %: `(T_after - T_before) / T_before * 100`
- Tail ratio: `L_p99.9 / L_p50` (target ≈ 1–3× when deterministic)
- Budget share %: `L_module_p99 / L_system_budget_p99 * 100`
