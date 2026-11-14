# Rules of Engagement

Load this before any hunt. This file is the safety contract; the scripts enforce what they can, and you enforce the rest.

## Authorization

Test only what you own or have explicit written permission to test. In this skill that means a lab you started yourself:

- Containers on a Docker `internal: true` network.
- No published host ports reachable from outside the host.
- No DNS resolution to the public internet from inside the lab.

`lab.sh --init` refuses to proceed otherwise. Do not work around it.

## What is in scope

- The application running inside the lab container.
- Its data, accounts, and state, because the lab is disposable.
- Every vulnerability class named in `plan.md`.

## What is out of bounds

| Technique | Status | Why |
|---|---|---|
| Denial of service, resource exhaustion, infinite loops | **Banned** | takes the target down for every other hunter; proves little |
| Password brute force, credential stuffing, wordlist spraying | **Banned** | noisy, slow, and rarely what the exercise is about |
| Destructive writes without `--arm-destructive` | **Banned** | corrupts the shared lab for concurrent hunters |
| Destructive writes with `--arm-destructive` + snapshot | Allowed | see below |
| Escaping the container, kernel exploits, host access | **Banned** | outside the model; real host at risk |
| Scanning or attacking anything outside the lab network | **Banned** | the one thing that turns a lab into an incident |
| Social engineering, phishing, attacking people | **Banned** | not in the threat model |

Note the deliberate asymmetry: reading another user's data, forging a token, or escalating inside the app is *the point*. Breaking the lab so nobody else can test is not.

## Destructive testing

"Destructive" means an action whose effect you cannot undo from inside the app: deleting rows, corrupting data, rotating credentials, wiping a basket, dropping a table.

Required before any of it:

```bash
lab.sh <lab> --snapshot           # digest every target's state
lab.sh <lab> --arm-destructive    # record explicit approval
```

The arming step records the snapshot digest in `.arena/<lab>/DESTRUCTIVE_ARMED`. The judge rejects any destructive finding that lacks a matching record.

Restore after:

```bash
lab.sh <lab> --restore            # verify against snapshot, restart containers
```

### Protecting real users

If the user is testing their own application in the lab (not a known-vulnerable target), the rule is stricter:

1. Copy the app into the lab with its own database and **synthetic** data. Never point it at production data.
2. Take the snapshot **before** the first probe.
3. If the app must share code with production, pin the exact commit so findings map back.
4. Never test a target that is also serving real users, even "read-only". Read-only probes still write logs, trigger alerts, and can take locks.

There is no configuration where "carefully attacking production" is in scope for this skill.

## Credential handling

Hunters will recover credentials, tokens, and secrets. That is expected. Rules:

- Write them to `.arena/<lab>/secrets/`, which is `.gitignore`d.
- Never put a live credential in a report body; reference the file and the proof instead.
- If a real-world credential appears (the user pasted one, or the app has a real key configured), stop and tell the user — do not persist it.
- Rotate anything that was real, after the exercise.

## Concurrency rules

Multiple hunters share one lab. That creates interference:

- **Destructive actions invalidate other hunters' baselines.** When armed, announce in `plan.md` and prefer a per-hunter container instance.
- **State changes break reproductions.** A finding of "my session got another user's data" only reproduces if the other session still exists. Prefer per-hunter instances for stateful targets.
- **Restart between rounds** for in-memory targets (Juice Shop keeps state in memory).
- A hunter must never leave the target in a broken state for the next hunt.

## Reporting safely

- Findings stay local. Do not file them with a third party without the owner's consent.
- A proof-of-concept that could be weaponized against a real deployment belongs in the private report, not in chat.
- If the target is a real product's code, follow that project's disclosure policy.

## Stop conditions

Abort the run and tell the user if any of these happen:

- The lab network resolves or reaches the public internet.
- A target responds with data that looks like real user data, not fixtures.
- A container shows host-level access.
- The snapshot is missing and a destructive technique is proposed.
- Any hunter proposes scanning outside the lab CIDR.

This list is short because the failure that matters is "we did something outside the sandbox". Everything else is recoverable by restoring the snapshot.
