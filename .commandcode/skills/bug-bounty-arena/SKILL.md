---
name: bug-bounty-arena
description: Set up an isolated virtual lab and run one or many agents as concurrent bug-bounty hunters, each specializing in one vulnerability class and going as deep as possible, persisting findings to disk, then judge and deduplicate them into a ranked unique report. Use when asked to run a bug bounty, hunt vulnerabilities in a lab target, compare hunters, or triage a pile of findings. Destructive techniques require an approved snapshot. Don't use for scanning systems without authorization, for denial-of-service or brute-force, or for production targets that are not isolated copies.
argument-hint: "[init | spawn | hunt | judge | report] [target]"
metadata:
  version: "1.0"
allowed-tools: Read Grep Glob Bash
---

# Bug Bounty Arena

An isolated lab, a set of hunters each owning one vulnerability class, persistent per-hunter reports, and a judge that keeps only unique, real, severe findings.

`$SKILL_DIR` in the commands below means the absolute path of this skill's own directory.

## Step 0 — Safety contract (do not skip)

Run this before anything else:

```bash
bash $SKILL_DIR/scripts/lab.sh <lab-name> --init
```

It refuses unless all of these hold:

1. The target is a **container local-network address**, not a public host.
2. The lab compose file declares an `internal: true` network, so a compromised container cannot reach the internet.
3. The user has authorized testing of this target.

**Destructive techniques** (data corruption, credential theft, wiping state) additionally require:

```bash
bash $SKILL_DIR/scripts/lab.sh <lab-name> --snapshot     # capture baseline
bash $SKILL_DIR/scripts/lab.sh <lab-name> --arm-destructive  # explicit approval
```

`--arm-destructive` writes `.arena/<lab>/DESTRUCTIVE_ARMED` and records the snapshot digest. Without it, hunters run read-only probes and non-destructive proof (see [references/rules-of-engagement.md](references/rules-of-engagement.md)).

Never run this skill against production. If the user wants to test their own app, the correct flow is: copy it into the lab compose file, snapshot, hunt, restore. Not "test prod carefully."

## Step 1 — Stand up the lab

`lab.sh --init` writes:

```
.arena/<lab>/
├── docker-compose.yml     # isolated: internal network, no host port publishing
├── rules.md               # scope, allowed techniques, what is out of bounds
├── snapshot.json          # baseline digests when armed
└── targets.json           # resolved container IPs and ports
```

Default target set (see [references/lab-setup.md](references/lab-setup.md)):

| Target | Container port | Good for |
|---|---|---|
| OWASP Juice Shop | 3000 | authz, business logic, injection, XSS |
| DVWA | 80 | classic injection, file inclusion |
| WebGoat | 8080 | authn/authz, deserialization |
| DVNA | 9090 | Node-specific logic flaws |

Use the ports from `.arena/<lab>/targets.json` (written by `lab.sh --init`), not memorized host-publish ports. Inside the arena network the URLs are `http://juice-shop:3000`, `http://dvwa:80`, `http://webgoat:8080`, `http://dvna:9090`.

Bring it up:

```bash
bash $SKILL_DIR/scripts/lab.sh <lab-name> --up
bash $SKILL_DIR/scripts/lab.sh <lab-name> --status
```

`--status` verifies the network really is internal and prints each target's URL. If the network is not isolated, stop.

## Step 2 — Plan the hunt

Before spawning, write `.arena/<lab>/plan.md` from `assets/hunt-plan.md`:

- which vulnerability classes are in scope
- which target each class applies to
- depth budget per hunter (attempts, time)
- what "proven" means for each class
- out-of-bounds list (DoS, brute force, destructive without arm)

A single-agent run writes the same plan and works the classes sequentially, deepest-first.

## Step 3 — Spawn hunters

```bash
bash $SKILL_DIR/scripts/arena.sh <lab-name> --spawn a01-bola,a02-injection,a03-authn
bash $SKILL_DIR/scripts/arena.sh <lab-name> --list
```

Each hunter gets its own identity, its own class, and its own workspace. Read [references/hunter-protocol.md](references/hunter-protocol.md) — that file is the contract every hunter must follow.

Rules that make the arena work:

- **One class per hunter.** Depth beats breadth; a hunter that wanders is a wasted slot.
- **Write findings to your own file only.** No hunter edits another's report; that is how duplicates survive.
- **Prove it or mark it unverified.** A finding needs a reproduction and an observed effect. Status codes alone are not proof.
- **Stop at the depth budget.** Report what you have rather than drift.

```bash
bash $SKILL_DIR/scripts/arena.sh <lab-name> --record a01-bola \
  --class bola --severity high --endpoint "GET /rest/basket/2" \
  --title "Cross-user basket read" --evidence-file /tmp/ev.txt
```

## Step 4 — Judge

```bash
bash $SKILL_DIR/scripts/judge.sh <lab-name>
```

The judge does three things, in order:

1. **Deduplicate** by fingerprint (class + normalized endpoint + root cause). Duplicates are merged, keeping the strongest evidence and listing contributing hunters.
2. **Reject** findings without reproduction or without an observed effect, and findings on out-of-scope targets.
3. **Rank** survivors by severity × confidence × impact, then emit only the ones that are unique and critical-or-high.

Read [references/judging.md](references/judging.md) for the fingerprinting rules and the dedup/rank policy. A judge that keeps everything has not judged anything.

## Step 5 — Report

```bash
bash $SKILL_DIR/scripts/report.sh <lab-name>
```

Emits `.arena/<lab>/report.md` with unique confirmed findings first, merged duplicates listed beneath with their contributing hunters, and rejected items in an appendix with reasons.

Then validate:

```bash
bash $SKILL_DIR/scripts/check-arena.sh <lab-name>
```

It fails if any confirmed finding lacks reproduction, if a destructive finding lacks an armed snapshot, or if the report contains unfilled placeholders.

## Multi-agent vs single-agent

| | Multi-agent | Single agent |
|---|---|---|
| Coverage | broad, one class each | deep, sequential |
| Duplicates | expected; judge merges | rare |
| Cost | N× tokens | 1× |
| Best for | wide surface, parallel classes | one suspected class, deep |

SkillsBench found **2–3 skills per task optimal, diminishing after 4** — the same applies here. 3–6 hunters is the useful range; 20 hunters mostly produces duplicates for the judge to discard.

## Grounding rules (anti-hallucination)

- Hunters record only what they **observed** (body, state change, access gained). Do not invent endpoints, payloads, or severity from memory of Juice Shop/DVWA challenges.
- Resolve target URLs from `targets.json` / `--status` output. Do not invent host ports.
- The judge rejects findings without reproduction or observed effect; do not "help" a finding by inventing missing evidence.
- If depth budget is exhausted without proof, mark `unverified` and stop — do not escalate confidence.

## Gotchas

- **Publishing host ports defeats isolation.** Bind to the lab network, not `0.0.0.0`. `--status` checks this.
- **`internal: true` blocks outbound, including package installs inside containers.** Pull images before going offline.
- **A 200 or 500 is not a finding.** Prove the effect: data changed, access gained, credential recovered.
- **Juice Shop keeps state in memory.** Restart it between destructive runs or results leak across hunts.
- **Hunters drift into each other's classes.** Assign by the finding's root cause, not the endpoint hit.
- **The judge must not be a hunter.** Use a fresh context; a hunter grading its own work keeps its false positives.
- **Duplicate ≠ invalid.** Two hunters finding the same bug independently raises confidence; merge, do not discard.
- **Never run destructive tests against prod "just to check".** Snapshot, or do not run.

## Checklist

- [ ] `lab.sh --init` passed the safety contract
- [ ] Network verified internal; no public host ports
- [ ] `plan.md` written with classes, targets, depth budget
- [ ] Destructive techniques gated by `--arm-destructive` + snapshot
- [ ] Each hunter wrote only its own report file
- [ ] Every confirmed finding has reproduction and observed effect
- [ ] Judge ran: duplicates merged, unproven rejected
- [ ] Report contains only unique, ranked findings
- [ ] `check-arena.sh` exits 0

## Dependencies

`references/rules-of-engagement.md`, `references/lab-setup.md`, `references/hunter-protocol.md`, `references/judging.md`. Scripts: `lab.sh`, `arena.sh`, `judge.sh`, `report.sh`, `check-arena.sh`. Assets: `hunt-plan.md`, `hunter-report.md`, `report.md`, `docker-compose.yml`. Coordinates with `backend-security-test` (single-target abuse) — this skill orchestrates many hunters over an isolated lab.
