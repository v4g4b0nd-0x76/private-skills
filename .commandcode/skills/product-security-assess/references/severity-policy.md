# Severity policy

Load when normalizing Bright or whitebox findings into JSONL / the report.

## Ranked report (must appear)

| Severity | Include |
|----------|---------|
| Critical | yes |
| High | yes |
| Medium | yes |
| Low | yes |
| Info | **no** — appendix only, never ranked |

`report.sh` drops any finding whose severity normalizes to `info` / `informational`.
`check-assess.sh` fails if a ranked `### FINDING-` block has Severity Info.

## Normalization

Map Bright / scanner labels case-insensitively:

- `critical` → Critical
- `high` → High
- `medium` / `moderate` → Medium
- `low` → Low
- `info` / `informational` / `note` → Info (filtered)

Unknown severity → treat as `unverified` Medium and flag in the finding notes; do not invent Critical.

## Confidence

Only: `confirmed` | `unverified` | `rejected`.
Confirmed requires Bright evidence id or an observed effect recorded in the finding.
