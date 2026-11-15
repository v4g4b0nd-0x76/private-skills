# Research: rust-systems-perf

- **Date:** 2026-11-15
- **Agent:** Cursor Auto
- **Change:** edited `rust-systems-perf` — corrected cache-line vs padding wording; added grounding rules

## Queries run

1. `x86-64 cache line size 64 vs 128 bytes false sharing CachePadded 2026`
2. `agentskills.io progressive disclosure best practices 2026`
3. `reducing LLM hallucination agent skills grounded verification scripts 2026`
4. Prior queries retained from 2026-11-14 create pass (see git history)

## Sources

| # | Source | Type | What it established |
|---|--------|------|---------------------|
| 1 | https://docs.rs/crossbeam-utils/latest/crossbeam_utils/struct.CachePadded.html | crate docs | On x86-64/aarch64/powerpc64, CachePadded uses **N=128** because Intel spatial prefetch pulls **pairs of 64-byte lines**; N is a padding guess, not a guarantee of hardware line length |
| 2 | https://stackoverflow.com/questions/72126606/should-the-cache-padding-size-of-x86-64-be-128-bytes | practitioner + Intel opt manual discussion | Hardware L1 line remains 64B on x86-64; adjacent-line prefetch can worsen bouncing when two hot lines are paired |
| 3 | https://nnethercote.github.io/perf-book/profiling.html | vendor docs | profiler matrix; keep `debug = "line-tables-only"` for usable profiles |
| 4 | https://agentskills.io/skill-creation/best-practices | spec/vendor | gotchas + validation loops; add only what the agent lacks |
| 5 | https://github.com/srinitude/building-deterministic-skills | source repo | insufficient-context escape hatch; offload exact checks to scripts |

## Project evidence

- `doctor.sh` already distinguishes measured cache line (often 64 on Linux x86-64) from "still pad to 128" — SKILL.md body previously contradicted that by saying the line "is 128 on x86-64".
- `assets/cache-padded.rs` comments were already correct; body text was the drift.

## Decisions

- **Separate hardware line size from padding width in SKILL.md** — source 1+2; rejected: leaving "line is 128 on x86-64" because agents copy that into incorrect comments/docs.
- **Add Grounding rules** — require `doctor.sh` / measured baselines before claims; rejected: relying on prose alone.
- Keep preferring `CachePadded` over hand-rolled `align(64)`.

## Conflicts and resolution

- Blog/memory advice says "cache line = 64, pad to 64". Crossbeam + Intel prefetch guidance say pad to 128 on x86-64 even when the line is 64. Primary crate docs win; wording now states both facts.

## Follow-ups

- Re-run `doctor.sh` on a Linux x86-64 host to confirm the WARN path for 64-byte measured lines still reads correctly after the prose change.

## Verification log (executed, not assumed)

| Check | Result |
|---|---|
| Web + primary docs for CachePadded / line size | confirmed: pad N=128, hardware often 64 on x86-64 |
| Skill body wording | updated; references/memory-layout.md + concurrency.md aligned |
| `check-all.sh` | see repo run after this edit batch |
| With-skill vs without-skill delta | not re-measured this pass |

Bugs found and fixed during verification:
- SKILL.md conflated hardware cache-line size with CachePadded N — fixed to match crossbeam docs and `doctor.sh`.
