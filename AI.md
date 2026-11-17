# AI.md — Skill Development Rules

This repository is a reusable collection of Agent Skills in the [agentskills.io](https://agentskills.io/specification) format. Skills are installed into projects with `scripts/install-skills.sh`.

Any agent creating, editing, or deleting a skill MUST read this file first and follow it exactly.

## 0. Research is mandatory

Never write or change a skill from model memory alone. Before touching `.commandcode/skills/`, complete all three passes:

1. **Web search for current practice.** Run at least two focused searches with the current year in the query, e.g.
   - `agent skill SKILL.md best practices <year>`
   - `<domain> <task> best practices <year>`
   - `agentskills.io progressive disclosure <year>`
2. **Read the primary sources.** The official spec and best-practices pages outrank blog posts:
   - https://agentskills.io/specification
   - https://agentskills.io/skill-creation/best-practices
   - https://agentskills.io/skill-creation/using-scripts
3. **Inspect project evidence.** Existing skills, scripts, `.devflow/` artifacts, git history, and real failure cases in the target project. Generic advice is not evidence.

**Record every pass in `research/<skill-name>.md`.** Use `research/_template.md`. A change with no research entry is rejected, the same way a change with failing validation is rejected.

Evidence bar:
- At least 3 sources, at least 2 of them primary (spec, vendor docs, source repository).
- State the date, the queries used, and what you rejected and why.
- When sources disagree, rank: official spec > vendor documentation > project evidence > blog posts.
- If research contradicts a convention already encoded here, say so explicitly in the research file and update AI.md in the same change.

## 1. Repository layout

```
skills/
├── AI.md                         # this file — rules for changing skills
├── research/                     # mandatory research log, one file per skill
│   ├── _template.md
│   └── <skill-name>.md
├── evals/                        # triggering accuracy, one query set per skill
│   └── <skill-name>/eval_queries.json
├── scripts/                      # tooling for this repo, not for agents at runtime
│   ├── check-all.sh              # run every gate; the only command you need
│   ├── validate-skills.sh        # spec structure + frontmatter + links
│   ├── description-lint.sh       # triggering quality heuristics
│   ├── chain-coverage.sh         # every devflow edge asserted
│   ├── script-tests.sh           # regression tests for all skill scripts
│   ├── trigger-eval.sh           # measure triggering against a query set
│   ├── run-trigger-evals.sh      # run all trigger evals
│   ├── new-skill.sh              # scaffold a compliant skill
│   └── install-skills.sh         # copy/symlink skills into a target project
└── .commandcode/skills/
    └── <skill-name>/
        ├── SKILL.md              # required: metadata + instructions
        ├── scripts/              # optional: deterministic helpers
        ├── references/           # optional: docs loaded on demand
        └── assets/               # optional: templates and static files
```

One skill per directory. A skill directory may not contain `README.md`, `CHANGELOG.md`, or install guides — those consume context the agent does not need. Put repo-level documentation here in AI.md instead.

## 2. Frontmatter rules (enforced by `validate-skills.sh`)

```yaml
---
name: kebab-case-name          # required, 1-64 chars, [a-z0-9-], no --, must equal directory name
description: What it does. Use when ... Don't use for ...   # required, 1-1024 chars
license: MIT                   # optional
compatibility: ...             # optional, <=500 chars, only real environment requirements
metadata:                      # optional, string-to-string
  version: "1.0"
allowed-tools: Read Bash       # optional, experimental
argument-hint: "<task>"        # Command Code extension, optional
---
```

The `description` carries the entire discovery burden. Write it as **what it does + when to use it + when NOT to use it**, in the words a user would actually say. Two or three sentences. No "helps with X".

## 3. Body rules

- **Budget:** keep `SKILL.md` under 500 lines / ~5,000 tokens. Past that, move detail into `references/` and tell the agent exactly when to load it.
- **Progressive disclosure:** metadata is always loaded; the body loads on activation; supporting files load only when a step tells the agent to read them. Never make the body a dumping ground.
- **Write for an agent:** third-person imperative, numbered steps, exact commands. "Extract the text", not "you should extract".
- **Match specificity to fragility:** rigid command sequences where consistency matters; principles where judgment matters.
- **Defaults, not menus:** pick one recommended tool/approach and mention the escape hatch once.
- **Include gotchas:** concrete, project-specific corrections the agent would otherwise get wrong. This is the highest-value section in most skills.
- **Add checklists** for multi-step work and **validation loops** ("run validator, fix, repeat until pass") for anything that can be checked.
- **Use `plan → validate → execute`** for batch or destructive work: write a plan artifact, validate it against a source of truth, then act.
- **One level deep:** references link to files in `references/`, `assets/`, `scripts/` only. No nested reference chains. Relative paths with forward slashes.

## 4. Script rules

Write a script when the operation is fragile, repetitive, or must be deterministic; do not write library code inside a skill.

- Tiny CLI: positional args, `--help`, sane exit codes (`0` success, `1` actionable failure).
- Self-contained, dependency-light (`bash`, `python3`, `node` only when required).
- Errors go to stderr and say what to do next, in a form the agent can self-correct from.
- Never prompt interactively. Never mutate state without an explicit flag.
- Scripts that only read state are preferred; mutating scripts must be obvious about what they change.

## 5. Modularity rules

- Each skill owns its directory and can be deleted without breaking the others, except the documented devflow package relationship.
- Shared runtime logic is duplicated only when tiny; otherwise one skill owns the script and the dependent skill names it explicitly.
- Cross-skill references use relative paths from the skill root and are listed in a `## Dependencies` line inside the body.
- Install with `scripts/install-skills.sh <target> --link` while iterating; edit here, never in the installed copy.

## 5a. Installing into other agents

`scripts/install-skills.sh` targets Command Code, Codex, Cursor, Claude Code and Gemini CLI. Paths are documented in `references/agent-targets.md`; run `--list` for the matrix.

```
scripts/install-skills.sh <project> [--agent LIST] [--scope project|user] [--link] [--force] [--dry-run]
```

Key facts that shape the defaults:

- **`.agents/skills/` is read natively by Codex, Cursor and Gemini.** One copy covers three agents; installing each natively creates duplicate trees for no benefit. Auto-detection collapses them to the shared path and says so.
- **Claude Code needs `.claude/skills/`.** It is the only agent that cannot share the `.agents` copy.
- **Use spec frontmatter only** (`name`, `description`, `license`, `compatibility`, `metadata`, `allowed-tools`). Claude Code hard-errors on unknown keys when a skill is uploaded; other agents silently ignore them. Agent-specific metadata belongs under `metadata:` or in the agent's own sidecar file.
- **`--link` is for iterating here.** Symlinks are followed by all target agents, so edits apply live; switch to copies for a committed install.
- **Vendor paths drift.** If a skill does not appear, re-read that agent's own docs and update `references/agent-targets.md` and the `--list` matrix in the same change.

## 6. The devflow package

`.commandcode/skills/devflow*` is a chain, not a set of independent skills:

```
devflow-research → devflow-plan → [GATE: user approval] → devflow-implement
                 → [optional] rust-submicrosecond-refactor   # when plan.bench_env: required
                 → devflow-test → [GATE: user approval] → full suite → devflow-review
```

Contract: `.commandcode/skills/devflow/references/handoff-contract.md`. Every stage reads its upstream artifact before acting and writes exactly one artifact. Changing the artifact header schema means updating the contract, all stage skills, and the devflow scripts in one change.

Optional latency branch: when `plan.md` sets `bench_env: required` (and usually `latency_campaign: true`), `next.sh` routes to `rust-submicrosecond-refactor` to stand up `.bench-env/` + `.devflow/bench-env.md` (owned deps real, third parties simulated via patterns from `thirdparty-e2e`) before dual-gate measurement. Do not skip that hop.

Approval gates are required. Do not remove a gate without the user asking for it explicitly.

## 7. Change workflow

Follow in order; do not skip a step because the change "looks small".

1. **Research** — section 0. Create or update `research/<skill-name>.md`.
2. **Scope** — one coherent capability per skill. Split unrelated jobs into separate skills.
3. **Draft** — `scripts/new-skill.sh <name> --full` or edit the existing skill.
4. **Write** — frontmatter first, then body as numbered steps. Put long material in `references/`, templates in `assets/`.
5. **Validate structurally** — `scripts/validate-skills.sh`. Fix every error.
6. **Validate discovery** — paste only the frontmatter into a fresh LLM chat and ask for 3 prompts that should trigger it, 3 that should not, and a critique. Adjust the description if it misfires.
7. **Validate logic** — feed the body and directory tree to a fresh LLM as an autonomous agent and ask it to simulate execution, flagging every line where it must guess.
8. **Test in a real project** — install, run the skill against a real task, read the trace, fix vague steps. Add each corrected mistake to a `## Gotchas` section.
9. **Record** — update the research file with what changed and why.

## 8. Definition of done

Run `scripts/check-all.sh` — it enforces gates 1-5 below and exits non-zero on any failure.

- [ ] **Structure**: `scripts/validate-skills.sh` exits 0
- [ ] **Triggering**: `scripts/description-lint.sh` exits 0; query set exists for the skill
- [ ] **Chain**: `scripts/chain-coverage.sh` passes (devflow edges still correct)
- [ ] **Scripts**: `scripts/script-tests.sh` passes (guards and validators still enforce)
- [ ] **Research**: research file has >=3 sources and a verification section
- [ ] **Discipline**: body under 500 lines, links exist, no README/CHANGELOG in the skill dir
- [ ] **Real run**: the skill was actually executed against a real project, and the
      research file's verification log records what it found

The last item cannot be automated. A skill that compiles, validates, and lints but
never ran is unverified, no matter how green the gates are.

## 9. Measuring quality, not just shape

Structural checks catch broken skills. They cannot tell you whether a skill *works*.
Two things measure that, and both are required before calling a skill done.

**Triggering accuracy.** A skill nobody loads is worthless. Every skill with a real
scope needs `evals/<skill>/eval_queries.json`: 16-20 realistic prompts, 8-10 that
should trigger and 8-10 that should not, including at least 3 near-misses that share
keywords with a positive. Then:

```bash
bash scripts/trigger-eval.sh <skill> --dry-run   # validate the set
bash scripts/trigger-eval.sh <skill>             # needs TRIGGER_RUNNER
```

A query passes if the trigger rate crosses the threshold in the direction of its
label. Run each query 3 times: model behaviour is nondeterministic, and a single run
is not evidence.

Avoid overfitting: keep 60% of queries as train (use them to fix the description) and
40% as validation (use them only to check the fix generalised). The best description
may be an earlier iteration, not the last one.

**Output quality.** Beyond triggering, compare with-skill against without-skill on a
real task, and record the delta in the research file. Source of truth:
https://agentskills.io/skill-creation/evaluating-skills. Keep 3-5 well-designed cases
rather than 50 noisy ones.

**What the evidence says about skill design** (SkillsBench, 86 tasks, 7 model configs):
- Skills raise performance by ~16 percentage points on average, but **vary by domain**:
  +51.9pp in healthcare vs **+4.5pp in software engineering**. For domains models already
  know well, a skill adds less — and 16 of 84 tasks got *worse* with a skill applied.
- **2-3 skills per task is optimal**; 4+ shows diminishing returns.
- **Compact beats comprehensive by ~4x** (+18.9pp vs +5.7pp). This is the strongest
  argument for the 500-line body limit and for pushing detail into `references/`.
- Full skills with executable examples (L3) reach 45.5% vs 16.4% without — the
  *procedural* content and working code drive the gain, not the presence of context.

Practical consequence for this repo: trim before you add. If a skill is not measurably
better than the bare model on its target task, it is costing context for nothing.

## 9a. Anti-hallucination rules for skill bodies

Skills that tell the agent to "decide" or "recall" without a source of truth produce
confident wrong answers. Encode these constraints in every skill that produces claims,
reports, plans, or measurements:

1. **Evidence before claim.** Every factual bullet (finding, metric, API shape, port,
   severity) must cite something the agent observed in this run: script output, a file
   path it read, a fetched URL, or a command exit code. If there is no evidence, write
   an open question / `unverified` / skip — never invent the missing piece.
2. **Scripts decide pass/fail.** Where a check can be mechanical (`check-*.sh`,
   `doctor.sh`, `status.sh`, pytest, k6 thresholds), the script's exit code is the
   verdict. The model proposes; code adjudicates.
3. **Fail closed on unknowns.** Missing tool, skipped sanitizer, unreachable sandbox,
   unmapped endpoint → record the gap. Do not treat absence of evidence as a pass.
4. **No memorized environment facts.** Ports, cache-line sizes, CLI flags, vendor
   default URLs, and library APIs change. Prefer `doctor`/`status`/`--help`/primary docs
   over training memory. When a skill embeds a number (study %, default port), name the
   source and the date it was verified in `research/<skill>.md`.
5. **Insufficient-context escape hatch.** Instruct the agent explicitly: if required
   inputs are missing, stop and ask or mark `BLOCKER` — do not fill gaps with plausible
   fiction. (See also deterministic-skill authoring patterns that offload exact checks
   to scripts.)

When editing a skill, hunt for lines that force a guess ("typical port", "usually 64",
"assume Stripe returns…") and replace them with a measurement step or an explicit
unknown path.

## 10. Keeping skills accurate over time

Skills rot silently: routes move, tool flags change, a validator stops rejecting what it
used to. Three defenses:

1. **Regression tests for behaviour.** `scripts/script-tests.sh` asserts that each
   guard still refuses, each validator still rejects, and each generator still writes
   what it promises. When you fix a bug found by testing, add the assertion that would
   have caught it. Every bug in this repo's history is represented there.
2. **Chain coverage.** `scripts/chain-coverage.sh` exercises every devflow edge,
   including backward edges (test fail → implement, changes requested → implement,
   stale → re-gate). Forward-only tests miss the paths that actually break.
3. **Freshness in research logs.** Each `research/<skill>.md` records a date. When a
   skill is touched, re-run at least two current-year searches and update the log; do
   not inherit stale claims. A skill whose research is over a year old should be
   re-verified before being trusted.

## 11. Offensive skills: lab isolation is a code requirement

`bug-bounty-arena` hunts vulnerabilities. Any skill that attacks something must enforce
its sandbox in code, not prose, because the failure mode is "we touched something real".

Rules for offensive skills:

- **Isolation is verified, not asserted.** `lab.sh --status` parses the compose file for
  an *active* `internal: true` (ignoring comments — a comment mentioning it is not a
  setting) and refuses published `ports:`. A false pass here is the worst bug the repo
  can ship.
- **Destructive techniques need a snapshot and an explicit arm.** Backup before breaking:
  `--snapshot` then `--arm-destructive`. The recorder refuses destructive findings without
  the arm file, and the judge rejects them if the arm is missing.
- **Proof is an observed effect, not a status code.** The 2026 survey of false-positive
  reduction found PoC validation is the only approach reaching zero false positives;
  everything else filters heuristically.
- **Never broaden the target.** No production, no third-party hosts, no host escape.
  If the user asks to "test prod carefully", the answer is: copy it into the lab.
- **Deduplicate by root cause.** Independent hunters converge; a report that lists the
  same bug five times hides the real ones. Merge, credit every hunter, keep the strongest
  evidence.

## Sources

- [Agent Skills specification](https://agentskills.io/specification)
- [Best practices for skill creators](https://agentskills.io/skill-creation/best-practices)
- [Evaluating skill output quality](https://agentskills.io/skill-creation/evaluating-skills)
- [Optimizing skill descriptions](https://agentskills.io/skill-creation/optimizing-descriptions)
- [Claude skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
- [SkillsBench: Benchmarking Agent Skills](https://arxiv.org/abs/2602.12670)
- [mgechev/skills-best-practices](https://github.com/mgechev/skills-best-practices)
- [mgechev/skillgrade](https://github.com/mgechev/skillgrade)
- [Building deterministic skills (grounding / insufficient-context)](https://github.com/srinitude/building-deterministic-skills)
- [Grounded verifiable gates](https://github.com/pedro-angel/agent-methodology/blob/main/skills/grounded-verifiable-gates/SKILL.md)
- [Multi-agent orchestration patterns](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns)
- [Reducing False Positives in Vulnerability Detection](https://oddsequence.com/research/reducing-false-positives)
- [Docker pentesting lab isolation](https://blog.bogdancaraman.com/pentesting-lab-docker-vulnerable-web-apps/)
- [crossbeam CachePadded (pad width ≠ hardware line)](https://docs.rs/crossbeam-utils/latest/crossbeam_utils/struct.CachePadded.html)
- [BOLA in the wild taxonomy](https://arxiv.org/abs/2605.25865)
