# Research: <skill-name>

- **Date:** YYYY-MM-DD
- **Agent:** <model or person>
- **Change:** <created | edited | deleted> `<skill-name>`

## Queries run

1. `<search query>`
2. `<search query>`

## Sources

| # | Source | Type | What it established |
|---|--------|------|---------------------|
| 1 | <URL> | spec / vendor docs / source repo / blog | <fact> |
| 2 | <URL> | | |
| 3 | <URL> | | |

## Project evidence

- <existing skill, script, artifact, git history, or failure case inspected>

## Decisions

- <decision> — <why>; rejected: <alternative and why>

## Conflicts and resolution

- <where sources disagreed and how it was resolved>

## Follow-ups

- <what still needs testing in a real project>

## Verification log (executed, not assumed)

Gates passed is not verification. Record what actually ran.

| Check | Result |
|---|---|
| `check-all.sh` | <pass/fail> |
| `description-lint.sh` | <errors/warnings> |
| `trigger-eval.sh --dry-run` | <queries, near-misses> |
| Scripts run against a real project | <which, what they caught> |
| With-skill vs without-skill delta | <measured improvement, or "not measured yet"> |

Bugs found and fixed during verification:
- <bug> — <root cause> — <what now guards against it>
