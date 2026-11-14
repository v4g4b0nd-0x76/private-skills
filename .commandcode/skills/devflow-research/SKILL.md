---
name: devflow-research
description: Stage 1 of devflow — gather project evidence and current external best practices for a task, then write .devflow/research.md with sourced findings, options, and decisions. Use when devflow routing returns devflow-research, when the task depends on unfamiliar APIs or conventions, or when the user asks for research or investigation first. Don't use when an approved plan already specifies the approach, or for purely mechanical edits.
metadata:
  version: "1.0"
  devflow-stage: "1"
---

# Devflow Research

Produce `.devflow/research.md`. Do not write production code in this stage.

`$SKILL_DIR` in the commands below means the absolute path of this skill's own directory.

## Preconditions

- The user's task is stated in the conversation.
- No upstream artifact is required (this is the first stage).

## Steps

1. **Restate the task** in one paragraph and list what you do not yet know: APIs, versions, project conventions, failure modes.
2. **Search the web** for anything external or version-sensitive. This is mandatory, not optional:
   - at least two focused queries with the current year
   - prefer primary sources: official docs, specs, changelogs, source repositories
   - if a search returns nothing useful, record that fact and the query used
3. **Inspect the local project** — relevant files, existing conventions, dependency versions, tests, and git history for prior attempts. Project evidence outranks generic advice.
4. **Create the artifact** from `assets/research.md`:
   ```bash
   mkdir -p <project-root>/.devflow
   ```
   Copy `assets/research.md` to `.devflow/research.md` and fill every section.
5. **Validate**:
   ```bash
   bash $SKILL_DIR/scripts/check-research.sh <project-root>
   ```
   Fix every reported error and re-run until it exits 0.
6. **Complete** — set `status: complete` and `updated:` to today in the header.
7. **Route** — run `next.sh` from the devflow skill and follow its output.

## Output rules

- Findings are one bullet per fact, each with a source: local path, URL, or command output.
- Options table must contain at least two real options unless the task is mechanically constrained.
- Record rejected options with the reason. This prevents the plan stage from relitigating.
- Open questions that block planning are marked `BLOCKER`; non-blocking ones become risks in the plan.

## Gotchas

- Research that only contains web links and no local evidence is incomplete. The plan stage will send it back.
- Do not paste long documentation into the artifact. Summarize the fact and keep the URL.
- If the task is a bug, the reproduction attempt and its result belong in Findings.
- Do not set `status: complete` while a `BLOCKER` question is unresolved.

## Checklist

- [ ] Task restated, unknowns listed
- [ ] >=2 web searches run, current year, sources preferred
- [ ] Local evidence inspected
- [ ] `research.md` filled from template
- [ ] `check-research.sh` exits 0
- [ ] `status: complete` set

## Dependencies

Uses `assets/research.md` and `scripts/check-research.sh` from this directory. Routing is handled by `../devflow/`.
