# Research: product-security-assess

- **Date:** 2026-11-18
- **Agent:** Cursor Auto (Composer)
- **Change:** created `product-security-assess`; edited to add `ensure-tools.sh` / `recon.sh` (ffuf, nmap, nuclei)
- **Purpose:** harness-friendly three-phase (black → gray → white) authorized assessment of live company domains/IPs via allowlisted recon tools + Bright DAST + whitebox code map; Info filtered; destructive gated by restore + arm

## Queries run

1. `agentskills.io skill creation best practices progressive disclosure 2026`
2. `Bright Security DAST repeater authenticated scan rules of engagement production 2026`
3. `OWASP DAST black box gray box white box assessment methodology production authorization 2026`

## Sources

| # | Source | Type | What it established |
|---|--------|------|---------------------|
| 1 | https://agentskills.io/specification | primary spec | Progressive disclosure; SKILL.md under 500 lines; one-level references; description drives discovery |
| 2 | https://agentskills.io/skill-creation/best-practices | primary docs | Compact beats dump; load references on demand; match specificity to fragility |
| 3 | https://docs.brightsec.com/docs/on-premises-repeater-local-agent | vendor docs | Repeater proxies Bright cloud → private/live targets without opening inbound firewall holes |
| 4 | https://docs.brightsec.com/docs/scanning-at-the-enterprise-level | vendor docs | Enterprise/live scans use Repeater; disconnect fails the scan; prefer always-on Repeater VM |
| 5 | https://docs.brightsec.com/docs/add-new-auth-object | vendor docs | Gray-box needs an auth object + protected-resource validation URL; re-auth triggers |
| 6 | https://owasp.github.io/DevSecOpsGuideline/2-Process/2-4-Test/2-4-2-Dynamic-Application-Security-Testing/ | standards | Authenticated DAST required for real coverage; tune scope/rate; avoid destructive tests on shared env without care |
| 7 | https://owasp.github.io/APTS/standard/appendix/Rules_of_Engagement_Template.html | standards | ROE fields: authorization, allow/deny lists, actions requiring explicit human approval |
| 8 | https://owasp.github.io/DevSecOpsGuideline/2-Process/2-7-Operate/2-7-3-Pentest/ | standards | Black/gray/white knowledge model; written ROE before testing |

## Project evidence

- `backend-security-test` maps code and generates local attack suites; `probe.sh` refuses non-local hosts — complementary for whitebox/local, not for live company domains.
- `bug-bounty-arena` isolates lab targets and gates destructive work with `--snapshot` + `--arm-destructive`; harness-friendly exit codes and `check-arena.sh` are the pattern to reuse for arm/restore/check.
- Bright plugin skills (`setup-repeater`, `setup-auth`, `register-entrypoints`, `run-scan`) are the only approved path for live remote traffic in this skill.
- AI.md §11 says lab skills must never broaden to production. This skill is a deliberate exception for **written, allowlisted company products** with Bright mediation — conflict recorded below.

## Decisions

- **Bright-only live traffic** — agent-crafted exploit payloads against live hosts are out of scope; Bright selects tests from its catalogue (do not hardcode tags). Source 3–5.
- **ROE + allowlist in code** — `assess.sh` refuses phases unless `authorized: true` and the target is in `targets.json`. Source 7.
- **Destructive = RESTORE.md + `--arm-destructive`** — same arm pattern as arena (source: project evidence); without arm, phases record non-destructive intent only. Source 6 + arena.
- **Drop Info from ranked report** — product ask; Info may go to an appendix but must not appear in ranked findings. `check-assess.sh` enforces.
- **Strict phase order** init → black → gray → white → report — harness-assertable via `phase.json`.
- **Whitebox maps gaps, does not freestyle-exploit prod** — optional local suite via `backend-security-test` mapper only when `code-root` is set; never point generated suites at live domain unless Bright-mediated and armed.
- Rejected: embedding XSS/overflow/SQLi recipes in references — policy + plan constraint.
- Rejected: speculative subdomain takeover / third-party host scanning — only user-provided + Bright-discovered assets in allowlisted scope.
- **Recon toolchain ffuf + nmap + nuclei** — operator ask for “ffuf, ninja, etc.”; mapped ninja→nmap/nuclei (not the Ninja build system). Tools are bootstrapped by `ensure-tools.sh` and constrained to allowlisted discovery; Bright remains the live vuln engine. Nuclei limited to discovery/tech/config/exposure tags.

## Conflicts and resolution

- **AI.md §11 “Never … production” vs live company domain ask.** Resolved: this skill allows live company hosts **only** when ROE `authorized: true`, host is allowlisted, and remote probes go through Bright Repeater. It is not a general offensive lab skill; `bug-bounty-arena` remains the isolated Juice Shop/DVWA path. Documented in SKILL.md Safety contract.
- **OWASP DAST guidance prefers staging for active scans** (source 6) vs user requirement for live. Resolved: default Bright launches omit destructive/special-case tests unless armed; ROE must name stop contact and restore plan.

## Follow-ups

- Real Bright MCP run against a company staging/live allowlisted host (Repeater + auth object).
- With-skill vs without-skill delta on a real product assessment (not measured yet).

## Verification log (executed, not assumed)

| Check | Result |
|---|---|
| `scripts/validate-skills.sh` | pass — 12 skills, 0 errors |
| `scripts/description-lint.sh` | pass — 0 errors; overlap warnings vs backend-security-test / thirdparty-e2e (distinct Don't-use clauses) |
| `scripts/script-tests.sh` (PSA section) | pass — tools print-path/check, init, recon/black unauthorized refuse, arm/restore, phase order, Info filter, High evidence, credential scan, gray-before-black refuse |
| `scripts/check-all.sh` | pass — all 5 gates (after tools addition; 118 script tests) |
| `trigger-eval.sh --dry-run` | pass — 20 queries (10+/10−), 5 near-miss negatives |
| Scripts run against a fixture workspace | pass — `script-tests.sh` temp project under `psa-proj` |
| With-skill vs without-skill delta | not measured yet (needs live Bright company target) |

Bugs found and fixed during verification:

- Multiline YAML `description: >-` parsed as 2-char description by lint awk — collapsed to a single quoted line.
- `check-assess.sh` High/Critical evidence check used `$?` after `|| errors=...` (always 0) — rewritten as if/then so failures increment correctly.
