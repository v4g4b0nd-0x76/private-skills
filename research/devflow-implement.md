# Research: devflow-implement

- **Date:** 2026-11-14
- **Change:** created `devflow-implement`

## Queries run

1. `AI coding agent implementation stage scope control best practices 2026`
2. `agentskills.io using scripts best practices`

## Sources

| # | Source | Type | What it established |
|---|--------|------|---------------------|
| 1 | https://agentskills.io/skill-creation/best-practices | vendor docs | match specificity to fragility; add gotchas for environment-specific traps |
| 2 | https://agentskills.io/specification | spec | scripts/ for deterministic checks, clear error output |
| 3 | https://github.com/mgechev/skills-best-practices | source repo | offload fragile checks to tested scripts instead of prose |

## Project evidence

- Plans carry exact file lists, so scope can be verified mechanically with `git diff`.
- The user wants small, localized changes (modularity taste).

## Decisions

- **`check-scope.sh` compares the working tree to `Files to touch`** and excludes `.devflow/`. A script is more reliable than asking the agent to remember.
- **Downstream artifacts marked stale at the start** — otherwise a rerun after review would route to review with an outdated test report.
- **No commits in this stage** — devflow tracks working-tree changes; committing is the user's decision.
- Rejected: editing the plan artifact in place to tick steps. Artifacts are immutable from downstream stages; progress lives in `implement.md`.

## Conflicts and resolution

- None.

## Follow-ups

- Confirm the parser handles plans that list a directory instead of individual files.
