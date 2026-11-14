# Research: bug-bounty-arena

- **Date:** 2026-11-14
- **Change:** created `bug-bounty-arena`
- **Purpose:** isolated lab + concurrent hunters, one class each, persistent reports, judged and deduplicated

## Queries run

1. `multi-agent LLM autonomous penetration testing framework 2026 vulnerability discovery deduplication`
2. `best isolated lab environment pentest vulnerable app docker compose 2026 OWASP juice shop DVWA safe testing`
3. `vulnerability report deduplication clustering false positive triage LLM 2026`

## Sources

| # | Source | Type | What it established |
|---|--------|------|---------------------|
| 1 | https://oddsequence.com/research/reducing-false-positives | preprint survey (100 sources, Mar 2026) | SAST FP rate 68–95%; **PoC validation reached zero false positives**; hybrid pipelines eliminated 94–98%; triage memories give fast ROI |
| 2 | https://blog.bogdancaraman.com/pentesting-lab-docker-vulnerable-web-apps/ | practitioner, detailed | concrete vuln-app images and ports; **`internal` network + outbound DROP** isolation model; pin tags for reproducibility; first-run DB init needed per app |
| 3 | https://arxiv.org/abs/2601.22952 | academic | LLM agents used specifically as **FP filters** for vulnerability findings |
| 4 | https://offensive360.com/blog/set-up-security-testing-lab-vulnerable-web-apps/ | practitioner | network isolation and authenticated DAST benchmarking practice |
| 5 | https://api-security.owasp.org/ | standards body | BOLA as API1 (carried from `backend-security-test`) |
| 6 | https://www.abacusnews.com/ai-vulnerability-detection-faces-false/ | reporting | 2026 evidence: FPs, duplicate reports and scope errors still limit autonomous scanning |

## Project evidence

- Existing `backend-security-test` covers one target, one pass, with an opt-in localhost probe. It has no concept of concurrent hunters, persistent per-hunter artifacts, or deduplication — so this skill complements rather than duplicates it.
- `thirdparty-e2e` already ships a WireMock/Toxiproxy compose and safety-guard pattern; the guard style is reused here (refuse non-local, require explicit arming).
- Host has docker + compose + jq + python3, so the harness can be shell+python without new dependencies.

## Decisions

- **`internal: true` over firewall rules.** Source 2 uses firewalld + DROP; a Docker `internal` network removes the route entirely and is verifiable from `docker network inspect`. Cheaper to audit and harder to get wrong. Cost: images must be pulled before going offline, documented.
- **No published ports, ever.** Publishing binds on the host and is reachable from the LAN; that is the most likely way a lab leaks. Both `--init` and `--status` refuse.
- **Destructive testing gated by snapshot + explicit arm.** The user asked for backup-then-break semantics. Encoded as `--snapshot` then `--arm-destructive`; `arena.sh --record --destructive` refuses without the arm file, and the judge rejects destructive findings when the arm is missing.
- **One class per hunter, no wandering.** Depth is the requested behaviour; a hunter that covers five classes shallowly produces work the judge discards.
- **Proof standard is an observed effect, not a status code.** Directly from source 1: PoC validation is the only approach with zero false positives, so the gate is "did something actually happen".
- **Dedup by root cause, not title.** Fingerprint = class + normalised endpoint (ids → `:id`) + root-cause token. Endpoint-normalisation is what lets `GET /rest/basket/2` and `GET /rest/basket/7` merge, while different verbs stay separate.
- **Duplicates are kept as corroboration**, never discarded — independent confirmation raises confidence and the report shows `confirmed by N hunters`.
- **The judge runs in a fresh context.** A hunter grading its own findings launders its own false positives.
- **2–6 hunters is the useful range.** SkillsBench: 2–3 skills optimal, diminishing after 4; 20 hunters mostly manufactures duplicates.
- Rejected: YAML/DB persistence for findings. JSONL per hunter is append-only, concurrent-safe without locks, and greppable.
- Rejected: auto-filing reports to a platform. Findings stay local; filing is the owner's decision.

## Conflicts and resolution

- Source 2 recommends a bridged adapter so containers are reachable on the LAN; that directly conflicts with isolation. Rejected the bridged model — reachability from the LAN is the risk we are removing. Hunters run *inside* the network instead.
- Source 1 finds triage memories give fast ROI, but a memory store is state that drifts. Encoded the cheaper version: rejected hypotheses are recorded in `plan.md` as known dead ends.

## Verification log (executed, not assumed)

| Check | Result |
|---|---|
| `scripts/validate-skills.sh` | 11 skills, 0 errors |
| `check-all.sh` gates | pass |
| `lab.sh --init` | creates lab, refuses compose without `internal: true`, refuses compose with `ports:` |
| `lab.sh --status` | passes on the generated compose; fails a compose with published ports |
| `lab.sh --arm-destructive` with no snapshot | **refused, exit 2** |
| `arena.sh --record` confirmed without evidence file | **refused** |
| `arena.sh --record --destructive` unarmed | **refused, exit 2** |
| `judge.sh` with duplicates | merged `GET /rest/basket/2` + `/7` into one finding |
| `judge.sh` with a different verb | kept separate (correct) |
| `judge.sh` with an unverified finding | rejected with reason |
| `report.sh` + `check-arena.sh` | report rendered, placeholders flagged |
| `check-arena.sh` on a report with a live key | rejected as possible credential |

## Follow-ups (open)

- Real hunting runs need per-hunter container instances for stateful targets; currently one shared lab, documented as a concurrency caveat.
- The judge's root-cause inference is heuristic. A hunter supplying `--fingerprint` is materially better; the reference explains this.
- No automated CVSS scoring; severity is hunter-assigned and judged by agreement.
