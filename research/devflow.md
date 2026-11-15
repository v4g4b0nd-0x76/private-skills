# Research: devflow

- **Date:** 2026-11-15
- **Agent:** Cursor Auto
- **Change:** edited `devflow` + stage skills — anti-hallucination / grounding; research validator requires sourced findings
- **Purpose:** orchestrator that routes work through research → plan → implement → test → review

## Queries run

1. `multi-agent orchestration handoff planning coding agent workflow best practices 2026`
2. `agentskills.io specification progressive disclosure best practices`
3. `agent skill SKILL.md best practices 2026`
4. `agentskills.io progressive disclosure best practices 2026` (refresh)
5. `reducing LLM hallucination agent skills grounded verification scripts 2026`

## Sources

| # | Source | Type | What it established |
|---|--------|------|---------------------|
| 1 | https://agentskills.io/specification | spec | directory layout, frontmatter rules, progressive disclosure, one-level-deep references |
| 2 | https://agentskills.io/skill-creation/best-practices | vendor docs | plan-validate-execute, checklists, validation loops, "add what the agent lacks" |
| 3 | https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns | vendor docs | sequential/handoff patterns; explicit context passed between agents |
| 4 | https://github.com/mgechev/skills-best-practices | source repo | skill composition/router pattern, <500 line body, third-person imperative |
| 5 | https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices | vendor docs | progressive disclosure; TOC for long refs; one-level-deep links |
| 6 | https://github.com/srinitude/building-deterministic-skills | source repo | insufficient-context hatch; scripts for exact checks |
| 7 | https://github.com/pedro-angel/agent-methodology/blob/main/skills/grounded-verifiable-gates/SKILL.md | source repo | cite→verify→pure decision function; fail closed |

## Project evidence

- Empty repository; no prior conventions to preserve. Taste file asks for modular, one-directory-per-unit tooling and approval gates.

## Decisions

- **Anti-hallucination across the chain:** research findings must cite sources (enforced in `check-research.sh`); plan/implement must not invent paths/APIs; test must not invent exit codes; review findings need locations; orchestrator must read status from scripts. Rejected: prose-only "be accurate" without a validator.
- **Router + five stage skills**, not one giant skill — matches the composition pattern and keeps each body small.
- **Artifacts as state** in `.devflow/` instead of a JSON state file — each stage is independently readable, no schema migration, and the trail is reviewable in the diff.
- **Gates at plan approval and before the full test suite** — user selected this in the design conversation; also matches the "plan-validate-execute" pattern.
- **Stale propagation** via `status: stale` + cleared verdicts — prevents infinite reroute loops after a review requests changes.
- Rejected: a single `coding-workflow` skill with all stages inline. It would exceed the body budget and could not be installed or changed per stage.

## Conflicts and resolution

- mgechev warns against documentation files inside skill directories, while the user requires documented research. Resolved by keeping skill directories lean and putting research logs at `research/<skill>.md` in the repo root.

## Follow-ups

- Run the chain against a real multi-file change; confirm the stale propagation feels right and no gate is skipped.

## Verification log (executed, not assumed)

| Check | Result |
|---|---|
| `scripts/chain-coverage.sh` | 31 assertions across every devflow edge, all passing |
| Forward edges | research→plan→implement→test→review→done each asserted |
| Backward edges | test fail→implement, changes-requested→implement, stale→re-gate asserted |
| Gate enforcement | `next.sh` emits `GATE` at plan approval and before the full suite |
| Stale propagation | `mark-stale.sh` sets `status: stale` and clears `verdict` |
| Validators | each check-*.sh asserted to accept valid input and reject invalid |

Bugs found and fixed during verification:
- Routing gave the plan gate lower precedence than a `draft` plan, so approval was skipped. Precedence corrected.
- Backward path left `verdict: approve` in place after marking stale, causing a routing loop. Verdicts now cleared.
