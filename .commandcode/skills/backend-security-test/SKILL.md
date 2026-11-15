---
name: backend-security-test
description: Adversarial security testing of backend systems — map the code's logic surface, then generate runnable attack suites for authentication, authorization (BOLA/IDOR, privilege escalation), mass assignment, race conditions, data leakage, and business-logic abuse. Use when asked to security-test an API or backend, break or abuse its logic, check authz enforcement, or find privilege-escalation and data-leak paths. Don't use for frontend/CLI code, for reviewing code without testing it (use security-review), or against systems you do not own or have written authorization to test.
argument-hint: "[map | suite | probe | report] [path-or-target]"
metadata:
  version: "1.0"
allowed-tools: Read Grep Glob Bash
---

# Backend Security Test

Adversarial testing of backend logic. Two modes: **generate runnable attack suites** from the codebase, and **optionally probe a local target** you own.

`$SKILL_DIR` in the commands below means the absolute path of this skill's own directory.

## Safety rule (non-negotiable)

Only test systems the user owns or is authorized to test. Before any request is sent:

1. The target host must be `localhost`, `127.0.0.1`, `::1`, or a `.test`/`.localhost` hostname.
2. `probe.sh` refuses anything else and exits 2.
3. Never test third-party APIs, production domains, or shared staging without explicit written authorization.

Generating a suite is always safe. Sending traffic is not. That is why the default is generate-only.

## Step 1 — Map the logic surface (always first)

```bash
bash $SKILL_DIR/scripts/map-surface.sh <backend-root>
```

Read its output, then read [references/logic-surface.md](references/logic-surface.md) to turn the grep hits into a real model:

- **Entry points**: routes, handlers, RPC methods, jobs, consumers.
- **Identity sources**: session cookie, bearer JWT, API key, mTLS identity.
- **Object references**: every path/body field that names an object the server must authorize against.
- **Ownership fields**: `owner_id`, `account_id`, `tenant_id`, `user_id` in request bodies — these are the rebinding attack surface.
- **Privileged actions**: delete, approve, transfer, refund, invite, impersonate.
- **Data fields**: anything that should never leave the backend (`password_hash`, `ssn`, `internal_*`, tokens).

Write the model to a file before generating tests. Tests written without it are guesswork.

## Step 2 — Generate the attack suite

```bash
bash $SKILL_DIR/scripts/gen-suite.sh <backend-root> --out .security/suite
```

It creates a ready-to-run pytest suite with two-account fixtures, because **single-account testing cannot prove a cross-user boundary failure**:

```
.security/suite/
├── conftest.py            # two accounts, two tenants, role fixtures
├── test_authn.py          # token/session handling, expiry, algorithm confusion
├── test_authz_bola.py     # the six BOLA families, all HTTP verbs
├── test_privesc.py        # vertical escalation, role manipulation
├── test_mass_assign.py    # ownership fields, role/is_admin injection
├── test_race.py           # concurrent duplicate/concurrent state-change
├── test_leakage.py        # error disclosure, over-fetch, caching, logs
└── README.md              # how to run it, what each test proves
```

Then fill each test from the mapped surface. Read [references/authorization.md](references/authorization.md) for the six BOLA families and the exact test shape for each, and [references/business-logic.md](references/business-logic.md) for workflow abuse and races.

Scale the suite to the code, not to a checklist: test the objects and actions that actually exist.

## Step 3 — Optional: probe a local target

```bash
bash $SKILL_DIR/scripts/probe.sh http://localhost:8080 --dry-run
bash $SKILL_DIR/scripts/probe.sh http://localhost:8080 --i-own-this-target
```

- `--dry-run` prints the exact request plan and sends nothing. Start here.
- `--i-own-this-target` is required to send traffic; the script refuses non-local hosts and exits 2.
- Defaults are conservative: low concurrency, a request budget, a delay, no destructive verbs unless `--allow-destructive` is passed.
- Never point it at anything you do not run.

## Step 4 — Try to falsify your own findings

False positives are the main failure mode of security testing. For every candidate finding, use [references/false-positive.md](references/false-positive.md) and answer:

- Is the input attacker-controlled, or is it server config? (Re-read the data flow.)
- Does a middleware, decorator, or DB-level scoping already enforce this?
- Did the request actually cross a boundary, or did I just see a 200?
- Would this reproduce on a fresh account and a fresh object?
- Is the leaked field actually sensitive, or a public value by design?

A finding that survives these questions gets written up. Anything else gets recorded as "unverified" with the reason.

## Step 5 — Report

Use `assets/report.md`. One finding per entry with: severity, class, endpoint, the exact reproduction, observed vs expected, impact, and a concrete fix. Then:

```bash
bash $SKILL_DIR/scripts/check-report.sh <report-file>
```

It enforces that every finding has reproduction steps and impact, and that unverified items are labelled. Fix and re-run until it exits 0.

## Grounding rules (anti-hallucination)

- Do not invent routes, field names, middleware, or ownership checks. Cite a path from `map-surface.sh` output or a file the agent actually read.
- A finding needs an **observed effect** (response body, persisted state, second-principal access). Status codes alone are not proof.
- If the map is incomplete, mark the gap in the report under what was not tested — do not fill it with guessed endpoints.
- Prefer `check-report.sh` over self-grading; if it fails, fix the report, do not weaken the claim.

## Gotchas

- **Single-account testing proves nothing about authorization.** Every authz test needs two principals that own different objects.
- **Test every verb, not just GET.** In Kaur 2026 (84 confirmed of 107 classified HackerOne reports), state-changing actions (modify + delete + trigger) were 46.4% of confirmed BOLA; read-only testing misses nearly half.
- **Vertical (user→admin object) failures were 11.9% of confirmed cases** and are underrepresented in most playbooks. Test them explicitly. Vertical BOLA is object-ownership failure, not RBAC/BFLA endpoint gating.
- **UUIDs and opaque IDs do not prevent BOLA.** 39.2% of known-format cases used non-sequential IDs; GraphQL Global IDs are often decode→increment→re-encode.
- **Re-check authorization when object state changes** (archived, deactivated, transferred). Static ownership checks at grant time miss Workflow-Context BOLA.
- **A 403 on the happy path does not prove the check.** Also test the object's own valid state, alternate routes, HTTP method override, and batch/bulk endpoints that may bypass the per-object check.
- **Race conditions need synchronized bursts**, not sequential calls. Fire N identical requests in parallel and inspect the final state.
- **Do not treat a 500 as a finding** unless you can show it leaks data or is triggered by an attacker-controlled input.
- **Never "verify" by brute-forcing real user IDs** outside your own test fixtures.
- **Report a false positive as loudly as a miss.** Both get fixed the same way: read the code.

## Checklist

- [ ] Ownership/authorization map written before any test
- [ ] Every authorization test uses two accounts with distinct objects
- [ ] Verbs beyond GET covered
- [ ] Vertical escalation included
- [ ] State-change objects (archived/deactivated/transferred) tested
- [ ] Race tests use parallel bursts
- [ ] Leakage checks look at errors, over-fetch, and headers
- [ ] Every finding passed the false-positive gate
- [ ] `check-report.sh` exits 0

## Dependencies

`references/logic-surface.md`, `references/authorization.md`, `references/authentication.md`, `references/business-logic.md`, `references/data-leakage.md`, `references/false-positive.md`. Scripts: `map-surface.sh`, `gen-suite.sh`, `probe.sh`, `check-report.sh`. Assets: `report.md`, `suite/conftest.py`, `suite/test_authz_bola.py`. Complements `security-review` (static code review) — this skill tests behavior.
