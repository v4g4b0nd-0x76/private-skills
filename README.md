# Skills

A modular collection of [Agent Skills](https://agentskills.io) for coding agents, plus the tooling that keeps them honest.

Each skill is one directory with a `SKILL.md`, optional `references/`, `scripts/` and `assets/`. Change one without touching the others.

## Install into your agent

```bash
# shared .agents/skills (Codex, Cursor, Gemini) + .claude/skills (Claude Code)
scripts/install-skills.sh ~/path/to/project --agent agents,claude

# just one agent
scripts/install-skills.sh ~/path/to/project --agent cursor
scripts/install-skills.sh ~/path/to/project --agent commandcode

# user-level, all projects
scripts/install-skills.sh --user --agent agents,claude

# see every supported path
scripts/install-skills.sh --list
```

Add `--link` to symlink while iterating (edits here apply live), `--dry-run` to preview, `--force` to overwrite.

`.agents/skills/` is read natively by Codex, Cursor and Gemini; Claude Code needs its own `.claude/skills/`. Details in [references/agent-targets.md](references/agent-targets.md).

## What's here

| Skill | Use it for |
|---|---|
| `devflow` + 5 stages | gated research → plan → implement → test → review with approval gates |
| `rust-systems-perf` | cache-aware layout, lock contention, heap traffic, profiling and UB/race gates |
| `backend-security-test` | adversarial authz/BOLA/logic testing, suite generation, report validation |
| `thirdparty-e2e` | third-party inventory, E2E suites, load profiles, fault injection |
| `bug-bounty-arena` | isolated lab, concurrent hunters by class, deduplicated judged report |

## Quality gates

```bash
scripts/check-all.sh              # structure, descriptions, chain, scripts, research
scripts/check-all.sh --with-evals # also measure skill triggering (needs TRIGGER_RUNNER)
```

| Gate | Enforces |
|---|---|
| `validate-skills.sh` | spec structure, name/dir match, links, body size |
| `description-lint.sh` | trigger clause, negative trigger, action verb, no overlap |
| `chain-coverage.sh` | every devflow edge, including backward ones |
| `script-tests.sh` | guards still refuse, validators still reject, installer targets |
| research check | ≥3 sources and a verification log per skill |

A green run is necessary, not sufficient: a skill that never ran against a real project is unverified.

## Creating a skill

```bash
scripts/new-skill.sh my-skill --full
```

Then read [AI.md](AI.md) — research is mandatory, and the change workflow is ordered. `research/_template.md` has the required verification log.

## Layout

```
AI.md                  rules for changing skills
research/<skill>.md    mandatory research + verification log per skill
evals/<skill>/         triggering query sets
references/            cross-repo docs (agent target matrix)
scripts/               gates and tooling
.commandcode/skills/   the skills
```
