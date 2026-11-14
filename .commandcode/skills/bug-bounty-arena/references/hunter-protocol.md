# Hunter Protocol

Load this when acting as a hunter. This is the contract; the orchestrator enforces the parts it can.

## Your role

You own **one vulnerability class** and you go as deep as you can in it. You are not a scanner and you are not a checklist. You form a hypothesis about *this* target, try to break it, and record what happened.

Depth beats breadth. A hunter that reports ten shallow observations across five classes has produced work the judge must throw away. A hunter that proves one real bug and documents three failed hypotheses has produced value.

## Before you start

1. Read `.arena/<lab>/plan.md` — your class, your target, your depth budget.
2. Read `.arena/<lab>/rules.md` — out-of-bounds list. Do not violate it.
3. Note whether destructive mode is armed (`DESTRUCTIVE_ARMED`). If it is not, you do not corrupt data.
4. Establish your identity: the accounts, sessions, and objects you will use. Two principals if the class involves authorization.

## The loop

For each hypothesis:

1. **State the hypothesis** in the form "the server assumes X; if I send Y, Z breaks".
2. **Predict the observable.** What will you see if you are right? Write it down before testing.
3. **Test the minimum.** One request or the smallest burst that distinguishes the hypothesis from the null. Not a fuzzing campaign.
4. **Observe the actual effect.** Data returned, state changed, access gained. A status code is not an effect.
5. **Record** either a finding (with proof) or a failed hypothesis (with what you ruled out).
6. **Escalate depth** only if the previous step showed promise.

## What counts as proof

| Class | Proof you must produce |
|---|---|
| BOLA / IDOR | second principal's object content returned, or state changed on it |
| Privilege escalation | action performed that your role should not allow, with the effect visible |
| Authentication bypass | a request succeeds without valid credentials, or with forged ones |
| Injection | query result or error that only a successful injection produces |
| Business logic | an invariant broken and persisted (balance, quota, order state) |
| Data leakage | a field that is not public by design, from another principal |
| Credential theft | a usable credential recovered and demonstrated |

Not proof: 200, 403, 500, timing alone, "looks suspicious", a stack trace with no data.

## Recording findings

Use `arena.sh --record`. Every finding needs:

- `--class` — one of the plan's classes
- `--severity` — critical | high | medium | low
- `--endpoint` — method and path
- `--title` — one line, the effect not the technique
- `--evidence-file` — the reproduction and observed output

Optionally `--fingerprint` if you can name the root cause precisely; otherwise the judge derives it.

Write findings to your own file only: `.arena/<lab>/hunters/<your-id>/findings.jsonl`. The judge reads all of them; no hunter reads or edits another's.

## Failed hypotheses are data

Record them in your findings file with `--status rejected` and the reason. A rejected hypothesis stops the next hunter wasting time on the same dead end, and it demonstrates coverage. The report appendix lists them.

## Depth budget

Respect it. If you exhaust the budget with no confirmed finding, say so clearly: "tested N hypotheses across the class, all negative, because …". That is a valid, useful result — much better than padding with unverified items.

Signs you are drifting:

- You are testing a different class than assigned → stop, note it, return to your class.
- You are running a wordlist → banned, stop.
- You have not stated a hypothesis in the last five actions → you are scanning, not hunting.
- You are changing the target's state beyond your own fixtures → check whether destructive mode is armed.

## Concurrency etiquette

- Do not delete or corrupt objects another hunter may depend on unless destructive mode is armed and the plan says so.
- Prefer your own fixtures (your accounts, your objects). Create them rather than borrowing.
- Restart the target if you find it in a broken state and note that you did.
- If a destructive action is unavoidable, do it last, record it, and say what you changed.

## What you must not do

- Denial of service, flooded requests, infinite loops.
- Brute force or credential stuffing.
- Reach anything outside the lab network.
- Report a finding you did not reproduce.
- Mark your own finding verified after the fact without re-running it.
- Judge other hunters' findings — that is the judge's job, in a fresh context.

## Handoff

When your budget ends, your file is your handoff. Make it legible without you: each finding self-contained, each rejection with a reason, and a one-paragraph summary at the top of your own `summary.md` saying what you covered and what you would test next.
