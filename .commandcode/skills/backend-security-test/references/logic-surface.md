# Mapping the Logic Surface

Load this after running `map-surface.sh`, to turn grep hits into an actual model of what the backend does.

## Why map first

Tests written without a model of the target are a checklist, and checklists produce false positives on code where the concern does not apply. The map is also the evidence you will need later to argue that an attacker controls a value.

## The six columns

Produce this table before writing a single test.

| Column | What to record | Why |
|---|---|---|
| Entry point | route/method, handler, RPC, consumer, job | where requests land |
| Identity | how the caller is identified (session, JWT claim, API key, mTLS) | what "this user" means |
| Object reference | identifiers in path/body/query that name a resource | BOLA input |
| Ownership source | session-derived, DB-derived, or client-supplied | the rebinding test |
| Privilege | role/permission check on the route | BFLA vs BOLA |
| Sensitivity | fields that must never leave the backend | leakage checks |

## How to build it

1. Read the route table (`routes.*`, `urls.py`, `router.*`, `#[*]`, controllers). One row per route.
2. For each route, find the authorization check:
   - decorator/middleware (`@login_required`, `requires_role`, guard, interceptor)
   - in-handler check (`if user.id != obj.owner_id`)
   - query-level scoping (`WHERE tenant_id = :current_tenant`)
3. Classify the result:
   - **no check found** — candidate BOLA; test it hardest.
   - **check present** — verify it covers *every* verb and every identifier path (body, header, nested, batch).
   - **query-scoped** — usually safe; look for raw queries and join paths that escape the scope.
4. Record every client-supplied ownership field you see. Those are rebinding candidates even when a check exists elsewhere.
5. Note object lifecycle states (draft/archived/deleted) because those are Workflow-Context tests.

## Where checks hide (so you do not report a false positive)

| Layer | Pattern | Test implication |
|---|---|---|
| Middleware/guard | global auth, tenant resolution | confirms identity, may not check object ownership |
| Decorator | per-route role check | BFLA covered, BOLA not |
| ORM scoping | `get_queryset` filtered by user | real BOLA protection — verify joins and raw queries |
| DB policy | Postgres RLS / row policy | real protection — verify it is enabled for the connection user used by the app |
| Serializer | field allowlist | protects mass assignment, not authorization |
| Response shaper | explicit field list | protects leakage, not authorization |

If protection is at the query layer, BOLA is unlikely. If it is only "user is logged in", every object-taking route is a candidate.

## Output template

Write this to `.security/surface.md` (or `map-surface.sh --json` output) and reference it from the report:

```markdown
## Endpoint: PATCH /api/tasks/{id}

- Identity: bearer JWT, `sub` = user uuid
- Object ref: path `{id}`; body may include `owner_id`
- Ownership source: **client-supplied `owner_id`** (rebind candidate)
- Privilege: none beyond authenticated
- Lifecycle: active, archived
- Checks found: handler verifies membership in the task's project, not task ownership
- Tests: Action-Level BOLA (archive/assign), Object Rebinding (`owner_id`), Workflow-Context (archived task)
```

## Prioritization

Spend effort where the empirical data says bugs are:

1. Any route that mutates an object identified in the path/body (Action-Level, 41.7%).
2. Any route taking a sequential integer id (Direct Reference, 22.6% of mechanisms).
3. Multi-tenant routes accepting a tenant/organization identifier (8.3%).
4. State-transition routes that re-use an old grant (6.0%).
5. Endpoints returning foreign identifiers (Chained Disclosure, 4.8%).
6. Any request schema with an ownership field (Object Rebinding, 2.4%, highest impact per case).

Routes with no object reference and no state are the lowest priority — say so in the report instead of padding it.
