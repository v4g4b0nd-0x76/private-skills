---
name: product-security-assess
description: "Run a three-phase black/gray/white authorized security assessment of a company product by domain or IP: ensure ffuf/nmap/nuclei, allowlisted recon into assets.json, Bright DAST, then whitebox code mapping; drop Info findings; gate destructive checks behind a restoration plan. Use when assessing a live company domain/IP, installing recon tools for product security, black gray white phases, or harnessing Bright scans with ROE. Don't use for unauthorized targets, Juice Shop/DVWA lab hunts (use bug-bounty-arena), or backend-only suite generation without a live product scope (use backend-security-test)."
argument-hint: "[init | tools | recon | black | gray | white | report | check] [domain-or-ip]"
compatibility: "bash, python3, go (to install ffuf/nuclei), nmap package or installable via ensure-tools.sh"
metadata:
  version: "1.1"
allowed-tools: Read Grep Glob Bash
---

# Product Security Assess

Harness-friendly orchestrator:
**init → tools → recon → black → gray → white → report → check**.

Wide recon uses **ffuf / nmap / nuclei** (installed by this skill) against the
allowlist only; vulnerability testing of live hosts goes through **Bright DAST +
Repeater**. This is not an exploit playbook.

`$SKILL_DIR` means the absolute path of this skill's directory.
Workspace: `.product-security/<run-id>/`.

## Safety contract (do not skip)

1. Written authorization in `roe.md` with `authorized: true`.
2. Every host/IP under test is in `targets.json` (allowlist).
3. Recon tools never expand past the allowlist; off-allowlist hits are dropped.
4. Live vulnerability testing uses Bright Repeater / auth objects — no
   agent-crafted XSS, overflow, SQLi, domain-hijack, or “break the DB” payloads.
5. Destructive or product-breaking checks need a filled `RESTORE.md` and
   `assess.sh <run> --arm-destructive` (writes `DESTRUCTIVE_ARMED`).
6. Ranked reports **exclude Info**; Info may appear only in an appendix.

Refuse and stop (exit 2 from scripts) if any of these fail.

## Step 0 — Init ROE and allowlist

```bash
bash $SKILL_DIR/scripts/assess.sh <run-id> --init --target <domain-or-ip> [--extra-host <h>]...
```

Creates `.product-security/<run-id>/` with `roe.md`, `targets.json`, `RESTORE.md`,
`phase.json`, and empty `findings/`, `scans/`, `whitebox/`.

Fill `roe.md` from [references/roe.md](references/roe.md): set `authorized: true`,
scope dates, stop contact, `credentials.ref` path (gray), `code-root` (white).
Never put secrets in the workspace — only a path reference.

Confirm:

```bash
bash $SKILL_DIR/scripts/assess.sh <run-id> --status
```

## Step 0b — Get recon tools

Read [references/recon-tools.md](references/recon-tools.md). Before black-box recon:

```bash
bash $SKILL_DIR/scripts/ensure-tools.sh --check \
  || bash $SKILL_DIR/scripts/ensure-tools.sh --install
export PATH="$(bash $SKILL_DIR/scripts/ensure-tools.sh --print-path):$PATH"
```

Required: **ffuf**, **nmap**, **nuclei**. `--install` fetches ffuf/nuclei via
`go install` into the skill tools bin and installs nmap via the OS package manager.

## Step 0c — Wide recon → assets.json

Requires ROE authorized. Runs allowlisted nmap + ffuf (+ nuclei discovery tags)
and writes `assets.json` for Bright entrypoints:

```bash
bash $SKILL_DIR/scripts/assess.sh <run-id> --recon
# equivalent: bash $SKILL_DIR/scripts/recon.sh <run-id>
```

Harness / offline: `recon.sh <run-id> --skip-ffuf --skip-nmap --skip-nuclei` is
not useful; prefer a fixture `assets.json` only in tests.

## Step 1 — Black box (unauthenticated Bright)

Requires phase `init` complete, ROE authorized, and `assets.json` present
(from `--recon` or an explicit inventory).

1. Read [references/bright-orchestration.md](references/bright-orchestration.md).
2. Bright: setup project + Repeater for the allowlisted host(s).
3. Register HTTP entrypoints from `assets.json` urls/ports (plus user OpenAPI).
   Client JS is **entrypoint discovery only** — no payload crafting from bundles.
4. Run unauthenticated Bright scans; omit destructive/special-case tests unless
   `DESTRUCTIVE_ARMED` exists. Prefer `api`, `server_side`, `client_side`,
   `business_logic` buckets from Bright's live catalogue — do not hardcode tags.
5. Persist scan config to `scans/black.json` and findings to
   `findings/black.jsonl` (one JSON object per line).

```bash
bash $SKILL_DIR/scripts/assess.sh <run-id> --phase black
```

The script advances `phase.json` after the agent has written scan/findings
artifacts (or records a planned non-destructive intent if Bright is unavailable
in the harness fixture).

## Step 2 — Gray box (authenticated Bright)

Requires phase `black` and a non-empty `credentials.ref` in `roe.md`.

1. Bright setup-auth → `authObjectId` (protected resource such as a profile/me URL).
2. Re-scan / extend entrypoints with auth; same destructive gate as black.
3. Write `scans/gray.json` and `findings/gray.jsonl`.

```bash
bash $SKILL_DIR/scripts/assess.sh <run-id> --phase gray
```

## Step 3 — White box (code map)

Requires phase `gray` and `code-root` in `roe.md` pointing at an owned repo.

1. Map routes, identity sources, object refs, privileged actions (see
   [references/phases.md](references/phases.md)). Prefer
   `backend-security-test` `map-surface.sh` when the tree is a backend.
2. Write `whitebox/surface.md` and `whitebox/gaps.md` — gaps are review/test
   candidates, not exploit steps against the live host.
3. Optional local suite (non-prod harness only):

```bash
bash $SKILL_DIR/scripts/assess.sh <run-id> --phase white --suite
```

Without `--suite`, only the map artifacts are required.

## Step 4 — Destructive arm (only when needed)

```bash
# Fill restoration steps (DB restore, redeploy, feature-flag rollback, etc.)
bash $SKILL_DIR/scripts/assess.sh <run-id> --write-restore
# Edit RESTORE.md, then:
bash $SKILL_DIR/scripts/assess.sh <run-id> --arm-destructive
```

`--arm-destructive` exits 2 unless `RESTORE.md` has real steps (no empty
template). Read [references/roe.md](references/roe.md) stop conditions before arming.

## Step 5 — Report

```bash
bash $SKILL_DIR/scripts/report.sh <run-id>
```

Merges findings JSONL, **drops Info**, dedupes by class+normalized endpoint,
writes `report.md` from [assets/report.md](assets/report.md). Severity policy:
[references/severity-policy.md](references/severity-policy.md). Falsify candidates
with [references/false-positive.md](references/false-positive.md) before marking
`confirmed`.

## Step 6 — Check (harness gate)

```bash
bash $SKILL_DIR/scripts/check-assess.sh <run-id>
```

Exits 0 only when ROE is authorized, phase order is complete through report,
High/Critical rows have evidence, Info is absent from ranked findings,
destructive work (if any) has `DESTRUCTIVE_ARMED` + restore steps, and no
inline secrets appear in artifacts.

## Grounding rules

- Cite observed Bright findings, files read under `code-root`, or script output.
  Do not invent endpoints, severities, or hosts outside `targets.json`.
- Status codes alone are not proof; confirmed needs an observed effect or Bright
  evidence id.
- Missing Bright / missing code-root → record `BLOCKER` in the report gaps
  section; do not fabricate coverage.
- Scripts decide pass/fail (`check-assess.sh`).

## Gotchas

- **Allowlist is code-enforced.** A host in conversation text but not in
  `targets.json` is out of scope; recon drops off-allowlist URLs.
- **Tools before recon.** Missing ffuf/nmap/nuclei → `ensure-tools.sh --install`
  (needs Go for ffuf/nuclei).
- **ffuf wordlist is the skill’s path list**, not a payload pack — do not replace
  it with attack dictionaries.
- **nuclei tags are fixed** to discovery/tech/config/exposure; do not widen into
  arbitrary exploit template runs against live prod.
- **Gray without credentials.ref fails closed** (exit 2).
- **White without code-root fails closed** (exit 2).
- **Hardcoding Bright test tags** silently under-scans; always `listTests` first.
- **Info in ranked findings fails the check** — filter in `report.sh`, do not
  hand-edit severity to sneak them in.
- **Arm without restore** is refused; restore without arm still runs
  non-destructive only.
- **Not bug-bounty-arena.** Live company products use this skill; lab Juice Shop
  uses the arena.

## Checklist

- [ ] `assess.sh --init` wrote workspace + targets
- [ ] `roe.md` has `authorized: true` and stop contact
- [ ] `ensure-tools.sh --check` passes (ffuf, nmap, nuclei)
- [ ] `assess.sh --recon` wrote `assets.json`
- [ ] Black Bright scan artifacts present
- [ ] Gray auth object + scan artifacts present
- [ ] Whitebox surface + gaps present
- [ ] Destructive work armed only with RESTORE.md
- [ ] `report.sh` dropped Info; deduped
- [ ] `check-assess.sh` exits 0

## Dependencies

Bright plugin skills (`setup-repeater`, `setup-auth`, `register-entrypoints`,
`run-scan`, `analyze-codebase`). Optional: sibling
`../backend-security-test` for `map-surface.sh` / local suite generation.
References: `roe.md`, `phases.md`, `bright-orchestration.md`, `recon-tools.md`,
`severity-policy.md`, `false-positive.md`. Scripts: `ensure-tools.sh`, `recon.sh`,
`assess.sh`, `report.sh`, `check-assess.sh`. Assets: `wordlist-paths.txt`.
