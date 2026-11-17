# Research: rust-submicrosecond-refactor

- **Date:** 2026-11-17
- **Agent:** Cursor Auto (Composer)
- **Change:** edited `rust-submicrosecond-refactor` — progressive disclosure rewrite; added references, scripts, assets, evals

## Queries run

1. `agentskills.io progressive disclosure skill creation best practices 2026`
2. `Rust sub-microsecond latency optimization benchmarking Mann-Whitney TSC open-loop 2025 2026`
3. Prior: agentskills using-scripts + specification (fetched primary pages)

## Sources

| # | Source | Type | What it established |
|---|--------|------|---------------------|
| 1 | https://agentskills.io/skill-creation/best-practices | spec/vendor | Keep SKILL.md under 500 lines / ~5k tokens; progressive disclosure with *when-to-load* links; gotchas + validation loops; compact beats encyclopedic |
| 2 | https://agentskills.io/skill-creation/using-scripts | spec/vendor | Bundle fragile/repeated logic as scripts; structured stdout; no interactive prompts; clear exit codes; relative paths from skill root |
| 3 | https://github.com/tfrmma/latency-benchmarking-suite | source repo | Sub-µs methodology: fenced `rdtsc`/`rdtscp`, core pin, cache warm, zero heap; `chrono`/`Instant` overhead dominates ns paths |
| 4 | https://github.com/bruno-medeiros/rust-low-latency-hft/blob/main/Benchmark-Methodology.md | source repo | TSC vs Instant overhead; governor/turbo/IRQ isolation for stable tails; HDR percentiles |
| 5 | https://github.com/nbenchmark/NBenchmark/blob/main/docs/statistics/significance.md | source repo | Mann–Whitney U for skewed bench timings; non-parametric vs t-test |
| 6 | https://github.com/enekos/aatxe | source repo | Dual gate pattern: effect-size threshold + MWU p-value + noise gate for accept/reject |
| 7 | https://docs.rs/crossbeam-utils/latest/crossbeam_utils/struct.CachePadded.html | crate docs | Pad N=128 on x86-64/aarch64 (adjacent-line prefetch), independent of measured 64B hardware line |

## Project evidence

- Prior body was a single ~353-line encyclopedia (audit A–E + formulas + crate catalog + report template) with no scripts — agents would re-implement MWU/progress math and invent baselines.
- `rust-systems-perf` already owns general layout/heap/coverage; this skill must negatively trigger away from it.
- Repo AI.md mandates research log, evals, `check-all.sh`, and scripts-as-adjudicators for pass/fail claims.
- Frontmatter had non-spec top-level `version` + `tags` (Claude upload risk); moved `version` under `metadata`.

## Decisions

- **Split into SKILL + references/ + scripts/ + assets/** — sources 1–2 + SkillsBench compact-wins guidance in AI.md; rejected: keeping one mega-body.
- **Scripts decide ACCEPT/REJECT** (`gate.py`, `persist_baseline.py validate`) — sources 2, 5, 6 + AI.md anti-hallucination; rejected: prose-only dual gate.
- **Pure-Python MWU** (stdlib) — source 2 dependency-light; rejected: requiring scipy for the gate.
- **Default practical gate 2% median, alpha 0.01, optional p99-only** — aligns with skill’s original dual-gate intent; aatxe uses 5%/0.05 as a different product default — kept stricter alpha from original skill.
- **Silicon latency table demoted to reference with “not host evidence”** — AI.md §9a; rejected: presenting table as measured fact in the always-loaded body.
- **Negative trigger → rust-systems-perf** — avoid dual activation on ordinary perf work.

## Conflicts and resolution

- Original skill used p&lt;0.01 and ≥2% median; aatxe defaults p&lt;0.05 and 5% median. Kept original campaign thresholds; documented in `gate.py` flags so agents can relax explicitly.
- Hardware cache line vs pad width: doctor + gotchas follow crossbeam (source 7), same as `rust-systems-perf`.

## Follow-ups

- Run a real open-loop bench in a latency crate and feed samples through `gate.py` end-to-end.
- Consider adding a tiny Rust TSC helper asset if projects repeatedly reinvent fencing.

## Verification log (executed, not assumed)

| Check | Result |
|---|---|
| Web + primary agentskills pages | fetched; progressive disclosure + scripts guidance applied |
| Domain methodology (TSC / MWU / open-loop) | confirmed via sources 3–6 |
| `scripts/validate-skills.sh` | pass (0 errors) |
| `scripts/description-lint.sh` | pass after single-line description + overlap exception |
| `scripts/trigger-eval.sh --dry-run` | 19 queries validated (9+/10−) |
| `scripts/script-tests.sh` | 97 passed incl. new persist/gate/progress/doctor/audit cases |
| `scripts/check-all.sh` | ALL GATES PASSED |
| Scripts against fixture samples | ACCEPT on 100→40 ns shift; REJECT on identical samples |
| With-skill vs without-skill delta | not measured yet (structural optimize pass) |

Bugs found and fixed during verification:
- YAML `description: >` folded form parsed as `>` (1 char) by repo linters — fixed to single-line description.
- Overlap warn with `rust-systems-perf` on heap/cache — rewrote negative trigger; added documented exception pair in `description-lint.sh`.


---

## Follow-up change: devflow bench-env integration (2026-11-17)

### Queries
1. `production-like test environment fixtures WireMock Testcontainers deterministic latency benchmarking 2025 2026`
2. Prior agentskills progressive disclosure / using-scripts (retained)

### Sources added
| # | Source | What it established |
|---|--------|---------------------|
| 8 | https://www.wiremock.io/post/running-effective-load-tests-using-mocks-and-simulated-environments | Own deps around SUT; baseline-zero then prod-like latency; avoid unrealistically fast mocks |
| 9 | https://wiremock.org/docs/solutions/testcontainers/ | WireMock as containerized stub layer |
| 10 | devflow handoff-contract + thirdparty-e2e testing-layers (repo) | Artifact routing; mock what you do not own |

### Decisions
- Optional devflow hop via `plan.bench_env: required` → `NEXT: rust-submicrosecond-refactor` — rejected: new devflow-bench-env stage skill (keeps package count down; latency skill already owns dual-gate).
- Compose thirdparty-e2e inventory rather than duplicating it.
- `check-bench-env.sh` adjudicates readiness; agents cannot mark complete without it.
