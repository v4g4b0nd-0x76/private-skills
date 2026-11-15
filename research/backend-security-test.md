# Research: backend-security-test

- **Date:** 2026-11-15
- **Agent:** Cursor Auto
- **Change:** edited `backend-security-test` — corrected BOLA 42% framing; added grounding rules; re-verified Kaur 2026 stats
- **Purpose:** adversarial backend security testing — map logic, generate attack suites, optionally probe a local target

## Queries run

1. `OWASP API Security Top 10 2025 2026 backend testing methodology authorization broken object level`
2. `business logic vulnerability testing race condition idempotency API 2025 2026 research paper`
3. `bug bounty report patterns authentication JWT bypass IDOR privilege escalation backend 2025 2026`
4. `OWASP WSTG testing guide authentication session management authorization test cases checklist`
5. `BOLA IDOR bug bounty study 107 reports vertical escalation percentage HTTP methods` (2026-11-15 refresh)
6. `reducing LLM hallucination agent skills grounded verification scripts 2026`

## Sources

| # | Source | Type | What it established |
|---|--------|------|---------------------|
| 1 | https://arxiv.org/abs/2605.25865 (HTML + PDF) | peer-reviewed preprint (empirical) | 200 tag-matched → 107 classified → **84 confirmed (42% of 200; 78.5% of classified)**; families Action-Level 41.7%, Direct Ref 36.9%, Tenant 8.3%, Workflow 6.0%, Chained 4.8%, Rebinding 2.4%; vertical 11.9%; Modify+Delete+Trigger = **46.4%**; Read alone 52.4%; non-sequential IDs 39.2% of known-format |
| 2 | https://api-security.owasp.org/ | standards body | OWASP API Security Top 10 framing; BOLA as API1 |
| 3 | https://arxiv.org/pdf/2312.14479 | peer-reviewed survey | race conditions are the most prevalent concurrency bug class; CWE-362/367; lockset vs happens-before; false-positive rates of >70% for static detectors |
| 4 | https://wstg.owasp.org/ | standards body | WSTG test-case structure for authn/session/authz |
| 5 | https://bugbounty.info/Attack-Surface/Web/Authorization/Privilege-Escalation | practitioner corpus | horizontal vs vertical escalation framing |
| 6 | https://bugbounty.info/Chains/IDOR-and-Mass-Assignment | practitioner corpus | IDOR + mass assignment chain to privilege escalation |
| 7 | https://github.com/aw-junaid/bug-bounty/blob/main/resources/cheatsheets/JWT.md | practitioner corpus | JWT attack classes: alg confusion, alg:none, kid injection, 2025–2026 CVEs |

Also inspected the existing `security-review` skill (17 references) to avoid duplication: it is **static code review** with confidence gating. This skill tests behavior and generates runnable suites, and explicitly defers to it for read-only review.

## Project evidence

- The repo already contains `security-review` with `authorization.md`, `authentication.md`, `business-logic.md`. Those cover *patterns to look for* in code; they do not generate tests or exercise a running service. The new skill links to it rather than restating it.
- User chose: generate suite + optional local probe; scope auth + authz + logic + leakage.

## Decisions

- **Cite 42% as 84/200 of the tag-matched sample**, not "survived classification" — the classified confirmation rate is 78.5%. Rejected the prior false-positive.md wording that conflated the two denominators.
- **Add Grounding rules** — map/observed effect before findings; scripts adjudicate reports.
- **Empirical frequencies drive test priority.** The single most useful thing in the research is the disclosure distribution. It justifies "test all verbs" and "test vertical" with numbers instead of opinion, and it corrects the common single-account, GET-only, horizontal-only test habit.
- **Two-principal fixtures are mandatory.** A one-account suite cannot prove a boundary. `conftest.py` requires alice + bob and fails loudly when `own()` is unfilled.
- **Tests fail loudly on unfilled TODOs** (`NotImplementedError`), because a security test that silently passes is worse than none. This is the main false-negative risk in a generated suite.
- **False positives are a first-class concern.** Source 1 shows tag-level heuristics overstate BOLA by more than half. Hence `references/false-positive.md`, the confirmed/unverified/rejected vocabulary, and `check-report.sh` enforcing reproduction + impact per finding.
- **Safety gates in code, not prose.** `probe.sh` refuses non-local hosts and requires `--i-own-this-target`; destructive verbs need a third flag; dry-run is the default suggested path. Generating is always safe, sending is not.
- **No automated exploitability for logic bugs.** Logic abuse cannot be pattern-matched; the skill maps invariants and instructs the agent to break them, which is why `business-logic.md` is framed as questions rather than a checklist.
- **Race tests assert on side effects, not status codes**, and repeat rounds, because intermittent passes are meaningless.
- Rejected: a ZAP/nuclei wrapper. It would add a heavy dependency and produce exactly the tag-level noise source 1 warns about. The generated pytest suite is auditable and repo-resident.

## Conflicts and resolution

- `security-review` recommends "report HIGH confidence only"; this skill must also report **unverified** items because behavioral testing legitimately leaves gaps. Resolved by defining exactly three allowed labels and requiring rejected candidates to be listed — stricter in a different dimension, not looser.
- Practitioner sources emphasize IDOR on reads; the empirical paper shows state-changing actions are 46.4%. Primary empirical source wins, and both are covered.

## Verification log (executed, not assumed)

| Check | Result |
|---|---|
| `map-surface.sh` on a fixture backend | detected all planted flaws: unscoped `db.query(Task).filter(Task.id==...)`, `owner_id` from body, `password_hash`/`api_key` in a response, `@PreAuthorize` vs `@login_required` gap, raw `db.execute` with `%` interpolation |
| `map-surface.sh --json` | valid JSON (`python -m json.tool`) |
| `probe.sh` against `https://example.com`, `https://api.github.com`, `http://10.0.0.5` | **refused, exit 2** each |
| `probe.sh http://localhost:8080` without `--i-own-this-target` | refused, exit 2 |
| `probe.sh --dry-run` | prints plan, sends nothing, exit 0 |
| `probe.sh` vs a live local HTTP server | 6 requests, correct 401/401/200/401 discrimination, exit 0 |
| `gen-suite.sh` | writes 8 files; refuses overwrite; `--force` works |
| generated suite collection | **43 tests collected**, no syntax errors |
| generated suite vs a dead localhost | fails with a real ConnectionError, does not silently pass |
| `Principal.own()` unfilled | raises `NotImplementedError` — the key anti-false-negative guard |
| suite host guard with `BASE_URL=https://example.com` | raises `RuntimeError: REFUSED ... not local` |
| `check-report.sh` on the blank template | rejected: 15 unfilled placeholders |
| `check-report.sh` on a valid report | passes |
| confirmed finding without reproduction | rejected |
| `Confidence: high` / `likely` (bold or not) | rejected; `unverified` accepted |
| missing `## Rejected candidates` / empty `## What was not tested` | rejected |

Bugs found and fixed during verification:
- `probe.sh` crashed with `extra[@]: unbound variable` under `set -u` when no extra curl args were passed — every real invocation. Fixed by guarding the array length.
- `check-report.sh` accepted the blank template because it only validated findings, and there were none. Added `<placeholder>` and TODO/TBD detection.
- The vague-confidence regex did not match markdown bold (`Confidence:** high`), so the vocabulary rule was unenforced. Fixed the pattern.

## Follow-ups (open)

- `test_authz_bola.py` skips Chained Disclosure until the agent maps an id-returning endpoint; that is intentional but should be revisited if it proves too easy to skip.
- Add GraphQL-specific probes (global ID decode/increment/re-encode) once a GraphQL backend is tested for real.
- `probe.sh` intentionally does not guess object ids — it only exercises authn and leakage. Cross-user probing stays in the generated suite, where assertions live.
