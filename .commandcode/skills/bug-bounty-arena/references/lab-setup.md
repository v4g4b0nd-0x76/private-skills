# Lab Setup: Isolated by Default

Load this when standing up a lab, adding a target, or when `--status` reports a problem.

## The isolation requirement

A bug-bounty lab is only safe if a compromised container cannot reach anything you care about. That means:

1. A Docker network with **`internal: true`** — no gateway, no outbound route.
2. **No `ports:` publishing.** Publishing binds on the host and is reachable from the LAN.
3. Hunters run **inside** the network (or from a container attached to it), addressing targets by service name.

`lab.sh --status` verifies 1 and 2 and fails loudly otherwise.

## Compose skeleton

```yaml
services:
  juice-shop:
    image: bkimminich/juice-shop:v19.2.0
    networks: [arena]
    # no ports: — reachable only inside the arena network

  dvwa:
    image: vulnerables/web-dvwa:latest
    networks: [arena]

  hunter:
    image: python:3.12-slim
    networks: [arena]
    depends_on: [juice-shop, dvwa]
    command: sleep infinity
    volumes:
      - ../../:/arena:ro     # reports are written by the orchestrator

networks:
  arena:
    internal: true
```

Reach a target from inside as `http://juice-shop:3000`, not `localhost:3000`.

## Why `internal: true` and not just a firewall

A firewall on the host is one more thing that can be wrong. `internal: true` removes the route at the network layer: the container has no path to the internet even if it is fully compromised. It also makes the intent legible in the compose file, so a reviewer sees the isolation without trusting your iptables.

Cost: containers cannot install packages or pull images once the network is internal. Pull first:

```bash
docker compose -f .arena/<lab>/docker-compose.yml pull
lab.sh <lab> --up
```

## Target catalogue

| Target | Image | Port | Strengths |
|---|---|---|---|
| OWASP Juice Shop | `bkimminich/juice-shop:v19.2.0` | 3000 | authz/BOLA, business logic, injection, XSS, file upload |
| DVWA | `vulnerables/web-dvwa` | 80 | classic SQLi, command injection, file inclusion, CSRF |
| OWASP WebGoat | `webgoat/webgoat` | 8080 | authn/authz lessons, deserialization, JWT |
| DVNA | `appsecco/dvna:sqlite` | 9090 | Node business-logic flaws, prototype pollution |

Pin tags. `latest` on a deliberately vulnerable app means your baseline changes under you and a reproduction stops working.

## First-run initialization

Some targets need a one-time setup or they 500 on every request:

- **DVWA**: log in `admin`/`password`, click *Create/Reset Database*.
- **WebGoat**: register an account at `/WebGoat/registration`.
- **Juice Shop**: register a user in the UI; no DB step.
- **DVNA** (sqlite): register a user directly.

Do this in a `--bootstrap` step before hunters start, or every hunter reports "app is broken" as a finding.

## State and resets

| Target | State lives in | Reset |
|---|---|---|
| Juice Shop | memory | restart container |
| DVWA | MySQL container | restart + reset DB button |
| WebGoat | H2 in container | restart container |
| DVNA (sqlite) | file in container | restart container |

Between hunt rounds, restart everything. `lab.sh --restore` does a compose down/up and re-verifies the snapshot.

## Adding the user's own application

The realistic case: the user wants their own service hunted.

1. Add it to `docker-compose.yml` under the `arena` network, with a **copy** of its database.
2. Seed **synthetic** data only. If the service reads `DATABASE_URL` from the environment, point it at a disposable one.
3. Build the image from a pinned commit so a finding maps to code.
4. Disable outbound calls (email, payments) or point them at a stub in the same network — otherwise the app tries to reach a real provider from an isolated network and every request errors.
5. Snapshot, then hunt.

Never mount a production database, never point at a production endpoint, and never share credentials.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `--status` reports "network is not internal" | compose missing `internal: true` | fix compose, re-init |
| Host port is open | `ports:` present | remove it; use service DNS |
| Container cannot resolve `juice-shop` | hunter not on the `arena` network | add it |
| All probes return connection refused | target still starting | poll `/health` or wait for the banner |
| Every request 500s | DB not initialized | run the bootstrap step |
| Image pull fails after `--up` | internal network blocks egress | `docker compose pull` first |
| Findings vanish between hunters | in-memory state reset | expected; reproduce within a round |
