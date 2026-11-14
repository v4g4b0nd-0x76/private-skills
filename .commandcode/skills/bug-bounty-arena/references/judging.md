# Judging: Deduplicate, Reject, Rank

Load this before running the judge or reviewing its output. The judge's job is to turn N hunter files into one ranked set of unique, real findings — which means throwing most of them away.

## Why this is the hard part

Independent hunters converge. Five hunters on one app will find the same missing authorization check five times with five different titles. A report that lists all five is worse than useless: it hides the real issues in noise.

The empirical picture supports strict judging:

- Traditional SAST produces **68–95% false positives** (Ogurtsov & Rumiantsev, 2026 survey of 100 sources).
- **PoC validation is the one approach that reached zero false positives** in that survey — confirming exploitability, not pattern-matching it.
- Hybrid pipelines eliminated **94–98%** of false positives in one industrial study — but only because something filtered.

So: a confirmation gate, then dedup, then ranking. In that order.

## Step 1 — Confirmation gate

A finding survives only if it has all of:

| Requirement | Fails when |
|---|---|
| Reproduction steps | "the endpoint looks vulnerable" |
| Observed effect | a status code, a guess, timing alone |
| In-scope target | anything off the lab network |
| Matching plan class | hunting outside the assignment |
| Evidence file present | claim with no artifact |

Anything missing is **rejected**, listed with the reason, not silently dropped.

## Step 2 — Deduplicate

Findings are the same bug when they share a **root cause**, not a title or an endpoint. Fingerprint on:

```
class + normalised-endpoint + root-cause-token
```

- **class**: the vulnerability class (bola, injection, authn, …)
- **normalised-endpoint**: method + path with identifiers replaced by `:id`, query strings sorted, trailing slashes stripped, case-folded
- **root-cause-token**: the missing control, named (`missing-owner-check`, `trusted-client-role`, `concat-sql`). The hunter may supply it; otherwise the judge infers it from the title and evidence.

Examples that should merge:

```
GET /rest/basket/2          bola  missing-owner-check
GET /rest/basket/7          bola  missing-owner-check     -> same finding
```

Examples that must not merge:

```
GET /api/orders/:id         bola  missing-owner-check
PATCH /api/orders/:id       bola  missing-owner-check     -> different verbs, different impact
GET /api/users/:id          bola  missing-tenant-scope    -> different control missing
```

When merging:

- Keep the **highest severity** and the **strongest evidence** (reproduction with an observed effect beats one without).
- List every contributing hunter — independent confirmation raises confidence.
- Note the count: `confirmed by 3 hunters` is meaningful signal.

## Step 3 — Rank

Score = severity × confidence × impact, with severity dominating.

| Factor | Values |
|---|---|
| Severity | critical 4, high 3, medium 2, low 1 |
| Confidence | confirmed 1.0, unverified 0.4 |
| Impact | takeover/authz-bypass 1.0, data-read 0.8, logic-abuse 0.7, info-leak 0.5 |

Report order:

1. Unique **critical** and **high** confirmed findings — the ones worth an engineer's day.
2. Unique confirmed medium.
3. Merged duplicates of the above (grouped under their canonical finding).
4. Appendix: rejected, with reasons.

Low findings go to the appendix unless they chain into something higher.

## What the judge must not do

- **Keep everything "just in case".** A judge that accepts all input has done nothing.
- **Discard duplicates as invalid.** Duplicates are confirmation. Merge and count them.
- **Invent a finding to fill the report.** An empty confirmed list is a valid outcome.
- **Re-hunt.** The judge reads and decides; if a finding is unproven it is rejected, not upgraded by the judge doing the hunter's work.
- **Judge its own findings.** Run the judge in a fresh context, ideally a different model, so a hunter cannot launder its own false positives.

## Machine-readable output

`judge.sh` writes:

```
.arena/<lab>/judged.json
```

```json
{
  "lab": "demo",
  "canonical": [
    {
      "fingerprint": "bola|GET /rest/basket/:id|missing-owner-check",
      "title": "Cross-user basket read",
      "class": "bola",
      "severity": "high",
      "confidence": "confirmed",
      "confirmed_by": ["a01-bola", "a04-authz"],
      "endpoint": "GET /rest/basket/:id",
      "evidence": "...",
      "score": 2.4
    }
  ],
  "merged": [ { "fingerprint": "...", "into": "...", "hunters": [...] } ],
  "rejected": [ { "hunter": "a02", "title": "...", "reason": "no observed effect" } ],
  "stats": { "raw": 14, "unique_confirmed": 3, "merged": 8, "rejected": 3 }
}
```

The `stats` block is the judge's own report card. A healthy run shows **raw ≫ unique confirmed** — that ratio is the point.

## Human review

The judge ranks; a human decides what to act on. Read the top findings' reproductions before filing anything. A judge that is right 90% of the time still ships one false positive in ten, and the cost of a bad report is that the next one is ignored.
