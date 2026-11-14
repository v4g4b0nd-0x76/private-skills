# Hunt Plan: <lab>

- **Created:** YYYY-MM-DD
- **Lab:** <lab name>
- **Isolation verified:** no (run `lab.sh <lab> --status`)
- **Destructive mode:** not armed

## Scope

Targets (from `targets.json`):

| Target | URL (in-network) | Classes applicable |
|---|---|---|
| juice-shop | http://juice-shop:3000 | bola, logic, injection, leakage |
| dvwa | http://dvwa:80 | injection, authn |
| webgoat | http://webgoat:8080 | authn, authz |
| dvna | http://dvna:9090 | logic, injection |

In scope: <what a hunter may touch>
Out of scope: DoS, brute force, host escape, anything outside the lab network.

## Hunter assignments

One class per hunter. Depth beats breadth.

| Hunter | Class | Target | Depth budget | What "proven" means |
|---|---|---|---|---|
| a01-bola | bola | juice-shop | 20 hypotheses | second principal's object content returned |
| a02-injection | injection | dvwa | 15 hypotheses | query result only an injection produces |
| a03-authn | authn | webgoat | 15 hypotheses | request succeeds without valid credentials |

## Depth budget

Per hunter: <N> hypotheses or <N> minutes, whichever ends first. Report partial
results rather than drifting.

## Credentials and fixtures

- Primary principal: <how to create>
- Second principal: <how to create, required for authz classes>
- Owned objects per principal: <how to create>

## Destructive actions

Planned: <yes/no>. If yes:
- [ ] snapshot taken (`lab.sh <lab> --snapshot`)
- [ ] armed (`lab.sh <lab> --arm-destructive`)
- [ ] affected hunters notified
- [ ] restore step agreed (`lab.sh <lab> --restore`)

## Known dead ends

<rejected hypotheses, so the next hunter does not repeat them>

## Success criteria

<e.g. at least one unique confirmed finding, or a documented negative result
per class with what was ruled out>
